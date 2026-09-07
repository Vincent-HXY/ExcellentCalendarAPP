package com.excellentcalendar.excellent_calendar.bridge.sync

import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

class SyncWakePumpTest {
    private class Journal : WakeJournal {
        var value = WakeRecord(emptyList(), null)
        override fun read() = value
        override fun write(record: WakeRecord) { value = record }
    }
    private class Work : WakeWorkPort {
        val nodes = linkedMapOf<String, WakeWorkState>()
        var failQuery = false; var failEnqueue = false; var enqueueThenFail = false
        var submissions = 0
        override fun unfinished(): Map<String, WakeWorkState> {
            if (failQuery) throw IllegalStateException()
            return nodes.filterValues { it in setOf(WakeWorkState.RUNNING, WakeWorkState.WAITING) }
        }
        override fun state(id: String): WakeWorkState? { if (failQuery) throw IllegalStateException(); return nodes[id] }
        override fun appendOrReplace(ticket: WakeTicket) {
            if (failEnqueue) throw IllegalStateException()
            check(!nodes.containsKey(ticket.workId)); nodes[ticket.workId] = WakeWorkState.WAITING; submissions++
            if (enqueueThenFail) throw IllegalStateException()
        }
    }
    @Test fun tenThousandConcurrentTriggersHaveAtMostOneSuccessor() {
        val store = Journal(); val work = Work(); val pump = SyncWakePump(store, work) { UUID.randomUUID().toString() }
        pump.request(); work.nodes[work.nodes.keys.single()] = WakeWorkState.RUNNING
        val pool = Executors.newFixedThreadPool(16)
        try {
            val results = (1..10_000).map { pool.submit { pump.request() } }
            results.forEach { it.get(15, TimeUnit.SECONDS) }
            assertEquals(2, work.unfinished().size); assertEquals(2, work.submissions)
            val current = store.value.tickets.first()
            pump.drained(current.token)
            assertEquals(current.token, store.value.drainedToken)
            assertEquals(2, store.value.tickets.size)
        } finally { pool.shutdownNow() }
    }
    @Test fun crashOnEitherSideOfEnqueueReplaysExactTicketOnce() {
        for (afterCommit in listOf(false, true)) {
            val journal = Journal(); val work = Work()
            work.failEnqueue = !afterCommit; work.enqueueThenFail = afterCommit
            val pump = SyncWakePump(journal, work) { UUID.randomUUID().toString() }
            failure("SYNC_WAKE_REPAIR_REQUIRED") { pump.request() }
            val ticket = journal.value.tickets.single()
            work.failEnqueue = false; work.enqueueThenFail = false
            val recovered = SyncWakePump(journal, work) { UUID.randomUUID().toString() }
            recovered.request()
            assertEquals(listOf(ticket), journal.value.tickets)
            assertEquals(setOf(ticket.workId), work.nodes.keys); assertEquals(1, work.submissions)
        }
    }
    @Test fun queryFailureDoesNotBlindlyAppendAndTerminalPredecessorIsReplaced() {
        val journal = Journal(); val work = Work(); val pump = SyncWakePump(journal, work) { UUID.randomUUID().toString() }
        work.failQuery = true
        failure("SYNC_WAKE_REPAIR_REQUIRED") { pump.request() }
        assertEquals(0, work.submissions); assertTrue(journal.value.tickets.isEmpty())
        work.failQuery = false; pump.request()
        for (terminal in listOf(WakeWorkState.FAILED, WakeWorkState.CANCELLED, WakeWorkState.SUCCEEDED)) {
            work.nodes[work.unfinished().keys.single()] = terminal
            pump.request(); assertEquals(1, work.unfinished().size)
        }
        assertEquals(4, work.submissions)
    }
    @Test fun unknownTokenCannotAcknowledgeNewWorkAndLocalWritesNeverWake() {
        val journal = Journal(); val work = Work(); val pump = SyncWakePump(journal, work) { UUID.randomUUID().toString() }
        val hook = SyncOpportunityHook(pump)
        hook.committed(false, true, true); hook.committed(true, false, true); hook.committed(true, true, false)
        assertEquals(0, work.submissions)
        hook.committed(true, true, true); assertEquals(1, work.submissions)
        failure("SYNC_WAKE_REPAIR_REQUIRED") { pump.drained("unknown") }
        assertNull(journal.value.drainedToken)
        work.failQuery = true
        hook.committed(true, true, true) // Scheduling failure cannot undo a committed domain write.
    }
}
