package com.yonghao.hybridnote

import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.ZoneOffset

// RingBootReceiver.sort: the store's JSON as a restart or an update leaves it,
// and the passed rings it shows (T-13 unit 14, G1 and G4).
class RingBootSortTest {
    private val minute = 60_000L
    private val boot = 1_800_000_000_000L
    private val now = boot + 3 * minute

    private val words = object : RingBootReceiver.Words {
        override fun channel() = "Missed"
        override fun title() = "Missed while your phone was off"
        override fun count(count: Int) = "$count reminders"
    }

    // A ring as the plugin stores it (Gson NotificationDetails, the fields
    // the receiver reads).
    private fun ring(id: Int, item: String, atMs: Long, channel: String = "reminders_chime") =
        JSONObject()
            .put("id", id)
            .put("title", "Item $item")
            .put("channelId", channel)
            .put("playSound", true)
            .put("sound", "reminder_chime")
            .put("soundSource", "RawResource")
            .put("enableVibration", true)
            .put("payload", JSONObject().put("l", "tasks").put("i", item).toString())
            .put(
                "scheduledDateTime",
                Instant.ofEpochMilli(atMs).atOffset(ZoneOffset.UTC).toLocalDateTime().toString(),
            )
            .put("timeZoneName", "UTC")
            .put("repeatInterval", JSONObject.NULL)
            .put("repeatIntervalMilliseconds", JSONObject.NULL)
            .put("scheduledNotificationRepeatFrequency", JSONObject.NULL)
            .put("matchDateTimeComponents", JSONObject.NULL)

    private fun store(vararg rings: JSONObject) = JSONArray(rings.toList()).toString()

    private fun ids(json: String) = JSONArray(json).let { array ->
        (0 until array.length()).map { array.getJSONObject(it).getInt("id") }
    }

    @Test
    fun keepsFutureShowsQuietGroupedThenLoud() {
        val sorted = RingBootReceiver.sort(
            store(
                ring(1, "a", now + minute),
                ring(2, "b", boot - 3 * 24 * 60 * minute),
                ring(3, "c", boot - 60 * minute),
                ring(4, "d", boot + minute),
            ),
            now,
            boot,
        ) { words }
        assertEquals(listOf(1), ids(sorted.kept))
        val shown = sorted.shown.map { it.ring.getInt("id") }
        assertEquals(listOf(2, 3, RingBootReceiver.MISSED_SUMMARY_ID, 4), shown)
        val quiet = sorted.shown[0]
        assertEquals(RingBootReceiver.MISSED_CHANNEL, quiet.ring.getString("channelId"))
        assertEquals("Missed", quiet.ring.getString("channelName"))
        assertFalse(quiet.ring.getBoolean("playSound"))
        assertFalse(quiet.ring.getBoolean("enableVibration"))
        assertEquals(2, quiet.ring.getInt("importance"))
        // Shown as booked if the quiet copy cannot be shown.
        assertEquals("reminders_chime", quiet.plain!!.getString("channelId"))
        assertTrue(quiet.plain!!.getBoolean("playSound"))
        val summary = sorted.shown[2]
        assertTrue(summary.ring.getBoolean("setAsGroupSummary"))
        assertEquals("2 reminders", summary.ring.getString("body"))
        assertTrue(summary.ring.isNull("payload"))
        assertNull(summary.plain)
        // Loud: on the ring's own channel, as booked.
        assertEquals("reminders_chime", sorted.shown[3].ring.getString("channelId"))
        assertNull(sorted.shown[3].plain)
    }

    @Test
    fun oneQuietRingHasNoSummaryAndOldChannelsMove() {
        val sorted = RingBootReceiver.sort(
            store(ring(1, "a", now + minute, "reminders"), ring(2, "b", boot - 60 * minute, "reminders")),
            now,
            boot,
        ) { words }
        assertEquals("reminders_chime", JSONArray(sorted.kept).getJSONObject(0).getString("channelId"))
        assertEquals(1, sorted.shown.size)
        assertEquals("reminders_chime", sorted.shown[0].plain!!.getString("channelId"))
    }

    @Test
    fun nothingPassedNeverAsksForWords() {
        val sorted = RingBootReceiver.sort(
            store(ring(1, "a", now + minute), ring(2, "b", boot + minute)),
            now,
            boot,
        ) { throw IllegalStateException("no strings") }
        assertEquals(listOf(1), ids(sorted.kept))
        assertEquals(listOf(2), sorted.shown.map { it.ring.getInt("id") })
    }

    // G1: a failure while working out the quiet rings comes before anything
    // is written, so tidy leaves the store as it was.
    @Test(expected = IllegalStateException::class)
    fun aWordsFailureThrowsBeforeTheStoreIsWritten() {
        RingBootReceiver.sort(store(ring(2, "b", boot - 60 * minute)), now, boot) {
            throw IllegalStateException("missing plural")
        }
    }

    @Test(expected = JSONException::class)
    fun aBrokenStoreThrows() {
        RingBootReceiver.sort("[{", now, boot) { words }
    }

    // G4: after an app update the "boot" is now: only the last ten minutes
    // ring, older passed rings show quietly.
    @Test
    fun anUpdateRingsOnlyTheLastTenMinutes() {
        val sorted = RingBootReceiver.sort(
            store(ring(1, "a", now - 5 * minute), ring(2, "b", now - 2 * 24 * 60 * minute)),
            now,
            now,
        ) { words }
        val quiet = sorted.shown.first { it.ring.getInt("id") == 2 }
        val loud = sorted.shown.first { it.ring.getInt("id") == 1 }
        assertEquals(RingBootReceiver.MISSED_CHANNEL, quiet.ring.getString("channelId"))
        assertEquals("reminders_chime", loud.ring.getString("channelId"))
    }
}
