package com.yonghao.hybridnote

import com.yonghao.hybridnote.RingBootReceiver.Fate
import com.yonghao.hybridnote.RingBootReceiver.Stored
import org.junit.Assert.assertEquals
import org.junit.Test

// RingBootReceiver.plan: what a restart does with each stored ring (T-13
// unit 12).
class RingBootPlanTest {
    private val minute = 60_000L
    private val boot = 1_000_000_000L
    private val now = boot + 3 * minute // the receiver runs late, after unlock

    private fun one(item: String?, at: Long?) = Stored(item, at, oneShot = true)

    @Test
    fun dueSinceBootRings() {
        val fates = RingBootReceiver.plan(
            listOf(one("l/a", boot + minute), one("l/b", now)),
            now,
            boot,
        )
        assertEquals(listOf(Fate.RING, Fate.RING), fates)
    }

    @Test
    fun dueInTheTenMinutesBeforeBootRings() {
        val fates = RingBootReceiver.plan(
            listOf(one("l/a", boot - 10 * minute), one("l/b", boot - 1)),
            now,
            boot,
        )
        assertEquals(listOf(Fate.RING, Fate.RING), fates)
    }

    @Test
    fun olderIsQuiet() {
        val fates = RingBootReceiver.plan(
            listOf(one("l/a", boot - 10 * minute - 1), one("l/b", boot - 3 * 24 * 60 * minute)),
            now,
            boot,
        )
        assertEquals(listOf(Fate.QUIET, Fate.QUIET), fates)
    }

    @Test
    fun futureAndUnreadableAreBooked() {
        val fates = RingBootReceiver.plan(
            listOf(one("l/a", now + 1), one("l/b", null)),
            now,
            boot,
        )
        assertEquals(listOf(Fate.BOOK, Fate.BOOK), fates)
    }

    @Test
    fun pluginRepeatsAreBookedAsBefore() {
        val fates = RingBootReceiver.plan(
            listOf(Stored("l/a", boot - 60 * minute, oneShot = false)),
            now,
            boot,
        )
        assertEquals(listOf(Fate.BOOK), fates)
    }

    @Test
    fun aRepeatsMissedTimesShowOnlyTheLatest() {
        // A daily item's rings on three days while off, then its next one.
        val day = 24 * 60 * minute
        val fates = RingBootReceiver.plan(
            listOf(
                one("l/daily", boot - 3 * day),
                one("l/daily", boot - day),
                one("l/daily", boot - 2 * day),
                one("l/daily", boot + day),
                one("l/other", boot - day),
            ),
            now,
            boot,
        )
        assertEquals(
            listOf(Fate.DROP, Fate.QUIET, Fate.DROP, Fate.BOOK, Fate.QUIET),
            fates,
        )
    }

    @Test
    fun anOccurrencesLeadsShowOnce() {
        // A lead 10 min ahead (missed long ago) and the due time (since boot).
        val fates = RingBootReceiver.plan(
            listOf(one("l/a", boot + minute), one("l/a", boot - 20 * minute)),
            now,
            boot,
        )
        assertEquals(listOf(Fate.RING, Fate.DROP), fates)
    }

    @Test
    fun ringsWithoutAnItemAreNotMerged() {
        val fates = RingBootReceiver.plan(
            listOf(one(null, boot - day()), one(null, boot - day())),
            now,
            boot,
        )
        assertEquals(listOf(Fate.QUIET, Fate.QUIET), fates)
    }

    private fun day() = 24 * 60 * minute
}
