package com.yonghao.hybridnote

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZonedDateTime

// After a reboot or an app update, books the reminders again (T-13 unit 10,
// F6). It runs in place of flutter_local_notifications' own boot receiver,
// which books every stored ring again as it was: first it drops one-shot
// rings whose time passed while the phone was off (no catch-up: they would
// all ring at once on boot), and moves rings booked on an old channel to the
// current one, with its chime, so Android never makes the old channel again.
// Then the plugin's receiver books what is left.
class RingBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            tidy(context, System.currentTimeMillis())
        } catch (error: Exception) {
            Log.e(TAG, "Stored rings not tidied", error)
        }
        ScheduledNotificationBootReceiver().onReceive(context, intent)
    }

    companion object {
        private const val TAG = "RingBootReceiver"

        // The plugin's store of booked rings (a Gson list of its
        // NotificationDetails), file and key alike.
        private const val STORE = "scheduled_notifications"

        // As in lib/reminders/local_ring_platform.dart.
        private const val CHANNEL = "reminders_chime"
        private val OLD_CHANNELS = setOf("reminders")
        private const val SOUND = "reminder_chime"

        private val REPEATS = listOf(
            "repeatInterval",
            "repeatIntervalMilliseconds",
            "scheduledNotificationRepeatFrequency",
            "matchDateTimeComponents",
        )

        fun tidy(context: Context, nowMs: Long) {
            val preferences = context.getSharedPreferences(STORE, Context.MODE_PRIVATE)
            val json = preferences.getString(STORE, null) ?: return
            val stored = JSONArray(json)
            val kept = JSONArray()
            for (i in 0 until stored.length()) {
                val ring = stored.getJSONObject(i)
                val at = timeOf(ring)
                val oneShot = REPEATS.all { ring.isNull(it) }
                if (oneShot && at != null && at <= nowMs) {
                    continue
                }
                if (ring.optString("channelId") in OLD_CHANNELS) {
                    ring.put("channelId", CHANNEL)
                    ring.put("playSound", true)
                    ring.put("sound", SOUND)
                    ring.put("soundSource", "RawResource")
                }
                kept.put(ring)
            }
            preferences.edit().putString(STORE, kept.toString()).commit()
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
