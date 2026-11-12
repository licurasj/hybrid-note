package com.yonghao.hybridnote

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.os.SystemClock
import android.util.Log
import com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver
import com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.Locale

// After a reboot or an app update, books the reminders again (T-13 unit 10,
// F6) and shows the ones whose time passed (T-13 unit 12, owner's decision
// 2026-11-11, in place of F6's "no catch-up"). It runs in place of
// flutter_local_notifications' own boot receiver, which books every stored
// ring again as it was. First it sorts the stored one-shot rings whose time
// has passed:
// - due since the phone came back on, or up to [GRACE_MS] before: it rings
//   now, as normal. Android sends BOOT_COMPLETED only after the first unlock,
//   and some phones take minutes more (about 2 min on the owner's Sony), so
//   the boot time is now minus the time since boot, not when this runs;
// - due earlier: shown now without sound or vibration on the quiet
//   [MISSED_CHANNEL], one notification per item (its latest time) with its
//   Done button, grouped under a summary when there are two or more.
// After an app update (T-13 unit 14, G4) the phone did not restart, so only
// rings due in the last [GRACE_MS] ring; older ones show quietly.
// Rings booked on an old channel move to the current one, with its chime, so
// Android never makes the old channel again. Then the plugin's receiver books
// what is left, and the passed rings are shown through the plugin's own
// receiver, as if their alarm went off.
//
// No passed ring is lost on a failure (G1): everything is worked out before
// the store is rewritten, and if that fails or the store is not written, the
// store stays as it was and the plugin books its passed rings again, which
// ring at once. Once written, the passed rings are shown whatever the
// plugin's rebooking does, and a quiet one that cannot be shown is shown as
// it was booked.
//
// Then it notes the boot it handled (G2): until then the app keeps the rings
// that passed before this boot in the store for it (RingBooker).
class RingBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val nowMs = System.currentTimeMillis()
        val booted = intent.action != Intent.ACTION_MY_PACKAGE_REPLACED
        val bootMs = nowMs - SystemClock.elapsedRealtime()
        var shown: List<Shown> = emptyList()
        try {
            shown = tidy(context, nowMs, if (booted) bootMs else nowMs)
        } catch (error: Exception) {
            Log.e(TAG, "Stored rings not tidied", error)
        }
        try {
            ScheduledNotificationBootReceiver().onReceive(context, intent)
        } catch (error: Exception) {
            Log.e(TAG, "Rings not booked again", error)
        }
        for (ring in shown) {
            show(context, ring)
        }
        if (booted) {
            context.getSharedPreferences(FLUTTER_PREFERENCES, Context.MODE_PRIVATE)
                .edit()
                .putLong(BOOT_HANDLED_KEY, bootMs)
                .apply()
        }
    }

    // Shows [ring] as if its alarm went off; its alarm, if one is still set
    // (an update keeps them), goes (G4).
    private fun show(context: Context, ring: Shown) {
        val id = ring.ring.optInt("id", MISSED_SUMMARY_ID)
        if (id != MISSED_SUMMARY_ID) {
            try {
                cancelAlarm(context, id)
            } catch (error: Exception) {
                Log.e(TAG, "Passed ring's alarm not cancelled", error)
            }
        }
        for (details in listOfNotNull(ring.ring, ring.plain)) {
            try {
                ScheduledNotificationReceiver().onReceive(
                    context,
                    Intent(context, ScheduledNotificationReceiver::class.java)
                        .putExtra(DETAILS, details.toString()),
                )
                return
            } catch (error: Exception) {
                Log.e(TAG, "Passed ring not shown", error)
            }
        }
    }

    // The plugin's alarm for [id], matched as the plugin makes it (its
    // cancelNotification): same receiver, same request code.
    private fun cancelAlarm(context: Context, id: Int) {
        val alarm = PendingIntent.getBroadcast(
            context,
            id,
            Intent(context, ScheduledNotificationReceiver::class.java),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        ) ?: return
        context.getSystemService(AlarmManager::class.java)?.cancel(alarm)
        alarm.cancel()
    }

    // What to do with one stored ring after a restart.
    enum class Fate { BOOK, RING, QUIET, DROP }

    // A stored ring as [plan] sees it: [item] is its list and item (null when
    // unknown), [atMs] its time (null when unreadable).
    data class Stored(val item: String?, val atMs: Long?, val oneShot: Boolean)

    // A passed ring to show: [ring] as worked out, and [plain], the same ring
    // as it was booked, shown if [ring] cannot be (null for the summary and
    // for loud rings, which are shown as booked).
    data class Shown(val ring: JSONObject, val plain: JSONObject?)

    // The store as it is to be written, and the passed rings to show.
    data class Sorted(val kept: String, val shown: List<Shown>)

    // The texts of the quiet rings, in the app's language.
    interface Words {
        fun channel(): String
        fun title(): String
        fun count(count: Int): String
    }

    companion object {
        private const val TAG = "RingBootReceiver"

        // The plugin's store of booked rings (a Gson list of its
        // NotificationDetails), file and key alike.
        private const val STORE = "scheduled_notifications"
        private const val DETAILS = "notificationDetails"

        // As in lib/reminders/local_ring_platform.dart.
        private const val CHANNEL = "reminders_chime"
        private val OLD_CHANNELS = setOf("reminders")
        private const val SOUND = "reminder_chime"

        // The quiet channel and group for rings missed while the phone was
        // off. The summary's id is negative, so it never meets a ring's id
        // (RingBooker.idOf is 0 or more).
        const val MISSED_CHANNEL = "reminders_missed"
        private const val MISSED_GROUP = "com.yonghao.hybridnote.MISSED"
        const val MISSED_SUMMARY_ID = -1

        // A ring due up to this long before the phone came back on still
        // rings as normal: it came due during the restart itself.
        const val GRACE_MS = 10 * 60 * 1000L

        // The app's language (AppSettingsCubit.localeKey) and the boot this
        // receiver handled (LocalRingPlatform.bootHandledKey), through
        // shared_preferences.
        private const val FLUTTER_PREFERENCES = "FlutterSharedPreferences"
        private const val LOCALE_KEY = "flutter.settings.locale"
        private const val BOOT_HANDLED_KEY = "flutter.reminders.bootHandled"

        private val REPEATS = listOf(
            "repeatInterval",
            "repeatIntervalMilliseconds",
            "scheduledNotificationRepeatFrequency",
            "matchDateTimeComponents",
        )

        // Sorts the stored rings (one [Fate] each, in order). Rings that are
        // not one-shots, or whose time is unreadable or still to come, are
        // booked as before. Of the passed ones, each item keeps only its
        // latest (an occurrence's other leads, a repeat's earlier times).
        fun plan(rings: List<Stored>, nowMs: Long, bootMs: Long): List<Fate> {
            val fates = rings.map { ring ->
                val at = ring.atMs
                when {
                    !ring.oneShot || at == null || at > nowMs -> Fate.BOOK
                    at >= bootMs - GRACE_MS -> Fate.RING
                    else -> Fate.QUIET
                }
            }.toMutableList()
            val latest = HashMap<String, Int>()
            for (i in rings.indices) {
                if (fates[i] == Fate.BOOK) continue
                val item = rings[i].item ?: continue
                val before = latest[item]
                if (before == null) {
                    latest[item] = i
                } else if (rings[i].atMs!! > rings[before].atMs!!) {
                    fates[before] = Fate.DROP
                    latest[item] = i
                } else {
                    fates[i] = Fate.DROP
                }
            }
            return fates
        }

        // Rewrites the store with the rings still to book, written last and
        // only once everything else is worked out; returns the passed rings
        // to show now, quiet ones (and their summary) first. Nothing to show
        // when the store was not written.
        fun tidy(context: Context, nowMs: Long, bootMs: Long): List<Shown> {
            val preferences = context.getSharedPreferences(STORE, Context.MODE_PRIVATE)
            val json = preferences.getString(STORE, null) ?: return emptyList()
            val sorted = sort(json, nowMs, bootMs) { words(context) }
            if (!preferences.edit().putString(STORE, sorted.kept).commit()) {
                Log.e(TAG, "Stored rings not rewritten")
                return emptyList()
            }
            return sorted.shown
        }

        // [tidy]'s work on the store's JSON, with nothing written. [words] is
        // asked only when a ring shows quietly.
        fun sort(json: String, nowMs: Long, bootMs: Long, words: () -> Words): Sorted {
            val stored = JSONArray(json)
            val rings = (0 until stored.length()).map { stored.getJSONObject(it) }
            val fates = plan(
                rings.map { ring ->
                    Stored(itemOf(ring), timeOf(ring), REPEATS.all { ring.isNull(it) })
                },
                nowMs,
                bootMs,
            )
            val kept = JSONArray()
            val loud = ArrayList<Shown>()
            val quiet = ArrayList<JSONObject>()
            for ((i, ring) in rings.withIndex()) {
                if (ring.optString("channelId") in OLD_CHANNELS) {
                    ring.put("channelId", CHANNEL)
                    ring.put("playSound", true)
                    ring.put("sound", SOUND)
                    ring.put("soundSource", "RawResource")
                }
                when (fates[i]) {
                    Fate.BOOK -> kept.put(ring)
                    Fate.RING -> loud.add(Shown(ring, null))
                    Fate.QUIET -> quiet.add(ring)
                    Fate.DROP -> {}
                }
            }
            if (quiet.isEmpty()) {
                return Sorted(kept.toString(), loud)
            }
            val texts = words()
            val shown = ArrayList<Shown>()
            for (ring in quiet) {
                val plain = JSONObject(ring.toString())
                quieten(ring, texts)
                shown.add(Shown(ring, plain))
            }
            if (quiet.size > 1) {
                shown.add(Shown(summary(quiet.first(), quiet.size, texts), null))
            }
            return Sorted(kept.toString(), shown + loud)
        }

        private fun quieten(ring: JSONObject, words: Words) {
            ring.put("channelId", MISSED_CHANNEL)
            ring.put("channelName", words.channel())
            ring.put("channelDescription", JSONObject.NULL)
            ring.put("importance", 2) // NotificationManager.IMPORTANCE_LOW
            ring.put("priority", -1) // NotificationCompat.PRIORITY_LOW
            ring.put("playSound", false)
            ring.put("sound", JSONObject.NULL)
            ring.put("soundSource", JSONObject.NULL)
            ring.put("enableVibration", false)
            ring.put("vibrationPattern", JSONObject.NULL)
            ring.put("groupKey", MISSED_GROUP)
            ring.put("setAsGroupSummary", false)
        }

        // The group's summary, shaped like one of its rings (small icon,
        // channel) but with no item: a tap opens the app.
        private fun summary(ring: JSONObject, count: Int, words: Words): JSONObject {
            val summary = JSONObject(ring.toString())
            summary.put("id", MISSED_SUMMARY_ID)
            summary.put("title", words.title())
            summary.put("body", words.count(count))
            summary.put("setAsGroupSummary", true)
            for (key in listOf(
                "payload", "actions", "subText", "color", "largeIcon",
                "largeIconBitmapSource", "tag", "scheduledDateTime", "timeZoneName",
            )) {
                summary.put(key, JSONObject.NULL)
            }
            return summary
        }

        // The app's strings in the app's language (as reminderLocalizations
        // picks it), else the phone's.
        private fun words(context: Context): Words {
            val code = context
                .getSharedPreferences(FLUTTER_PREFERENCES, Context.MODE_PRIVATE)
                .getString(LOCALE_KEY, null)
            val strings = if (code == null) {
                context.resources
            } else {
                val configuration = Configuration(context.resources.configuration)
                configuration.setLocale(Locale(code))
                context.createConfigurationContext(configuration).resources
            }
            return object : Words {
                override fun channel() = strings.getString(R.string.ring_missed_channel)
                override fun title() = strings.getString(R.string.ring_missed_title)
                override fun count(count: Int) =
                    strings.getQuantityString(R.plurals.ring_missed_count, count, count)
            }
        }

        private fun itemOf(ring: JSONObject): String? {
            return try {
                val payload = JSONObject(ring.getString("payload"))
                payload.getString("l") + "/" + payload.getString("i")
            } catch (error: Exception) {
                null
            }
        }

        private fun timeOf(ring: JSONObject): Long? {
            if (ring.isNull("scheduledDateTime") || ring.isNull("timeZoneName")) {
                return null
            }
            return try {
                ZonedDateTime.of(
                    LocalDateTime.parse(ring.getString("scheduledDateTime")),
                    ZoneId.of(ring.getString("timeZoneName")),
                ).toInstant().toEpochMilli()
            } catch (error: Exception) {
                null
            }
        }
    }
}
