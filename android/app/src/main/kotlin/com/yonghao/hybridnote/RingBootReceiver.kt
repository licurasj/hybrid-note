package com.yonghao.hybridnote

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.content.res.Resources
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
// Rings booked on an old channel move to the current one, with its chime, so
// Android never makes the old channel again. Then the plugin's receiver books
// what is left, and the passed rings are shown through the plugin's own
// receiver, as if their alarm went off.
class RingBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        var late: List<JSONObject> = emptyList()
        try {
            val nowMs = System.currentTimeMillis()
            late = tidy(context, nowMs, nowMs - SystemClock.elapsedRealtime())
        } catch (error: Exception) {
            Log.e(TAG, "Stored rings not tidied", error)
        }
        ScheduledNotificationBootReceiver().onReceive(context, intent)
        for (ring in late) {
            try {
                ScheduledNotificationReceiver().onReceive(
                    context,
                    Intent(context, ScheduledNotificationReceiver::class.java)
                        .putExtra(DETAILS, ring.toString()),
                )
            } catch (error: Exception) {
                Log.e(TAG, "Passed ring not shown", error)
            }
        }
    }

    // What to do with one stored ring after a restart.
    enum class Fate { BOOK, RING, QUIET, DROP }

    // A stored ring as [plan] sees it: [item] is its list and item (null when
    // unknown), [atMs] its time (null when unreadable).
    data class Stored(val item: String?, val atMs: Long?, val oneShot: Boolean)

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

        // The app's language (AppSettingsCubit.localeKey, through
        // shared_preferences).
        private const val FLUTTER_PREFERENCES = "FlutterSharedPreferences"
        private const val LOCALE_KEY = "flutter.settings.locale"

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

        // Rewrites the store with the rings still to book; returns the
        // passed rings to show now, quiet ones (and their summary) first.
        fun tidy(context: Context, nowMs: Long, bootMs: Long): List<JSONObject> {
            val preferences = context.getSharedPreferences(STORE, Context.MODE_PRIVATE)
            val json = preferences.getString(STORE, null) ?: return emptyList()
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
            val loud = ArrayList<JSONObject>()
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
                    Fate.RING -> loud.add(ring)
                    Fate.QUIET -> quiet.add(ring)
                    Fate.DROP -> {}
                }
            }
            preferences.edit().putString(STORE, kept.toString()).commit()
            if (quiet.isEmpty()) {
                return loud
            }
            val strings = strings(context)
            for (ring in quiet) {
                quieten(ring, strings)
            }
            if (quiet.size > 1) {
                quiet.add(summary(quiet.first(), quiet.size, strings))
            }
            return quiet + loud
        }

        private fun quieten(ring: JSONObject, strings: Resources) {
            ring.put("channelId", MISSED_CHANNEL)
            ring.put("channelName", strings.getString(R.string.ring_missed_channel))
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
        private fun summary(ring: JSONObject, count: Int, strings: Resources): JSONObject {
            val summary = JSONObject(ring.toString())
            summary.put("id", MISSED_SUMMARY_ID)
            summary.put("title", strings.getString(R.string.ring_missed_title))
            summary.put(
                "body",
                strings.getQuantityString(R.plurals.ring_missed_count, count, count),
            )
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
        private fun strings(context: Context): Resources {
            val code = context
                .getSharedPreferences(FLUTTER_PREFERENCES, Context.MODE_PRIVATE)
                .getString(LOCALE_KEY, null) ?: return context.resources
            val configuration = Configuration(context.resources.configuration)
            configuration.setLocale(Locale(code))
            return context.createConfigurationContext(configuration).resources
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
