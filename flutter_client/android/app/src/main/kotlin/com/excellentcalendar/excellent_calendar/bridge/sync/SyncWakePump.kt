package com.excellentcalendar.excellent_calendar.bridge.sync

data class WakeTicket(val token: String, val workId: String)
data class WakeRecord(val tickets: List<WakeTicket>, val drainedToken: String?)
enum class WakeWorkState { WAITING, RUNNING, SUCCEEDED, FAILED, CANCELLED }

interface WakeJournal {
    fun read(): WakeRecord
    /** Must commit durably before returning. The production adapter must use an account AEAD AtomicFile. */
    fun write(record: WakeRecord)
}

interface WakeWorkPort {
    fun unfinished(): Map<String, WakeWorkState>
    fun state(id: String): WakeWorkState?
    /** Waits for WorkManager Operation completion; the request uses ticket.workId as its stable UUID. */
    fun appendOrReplace(ticket: WakeTicket)
}

/** One application-owned instance per workspace/device. Never call from the Android main thread. */
class SyncWakePump(private val journal: WakeJournal, private val work: WakeWorkPort, private val uuid: () -> String) {
    @Synchronized fun request() {
        try {
            var record = journal.read()
            checkRecord(record)
            var unfinished = work.unfinished()
            // A missing journal entry must be repaired, not converted to another node.
            if (unfinished.keys.any { id -> record.tickets.none { it.workId == id } }) failRepair()
            for (ticket in record.tickets) {
                if (work.state(ticket.workId) == null) {
                    if (unfinished.size >= 2) failRepair()
                    work.appendOrReplace(ticket)
                    unfinished = work.unfinished()
                }
            }
            unfinished = work.unfinished()
            if (unfinished.size > 2 || unfinished.values.count { it == WakeWorkState.RUNNING } > 1) failRepair()
            val retained = record.tickets.filter { it.workId in unfinished }
            if (unfinished.values.any { it == WakeWorkState.WAITING }) return
            if (unfinished.size >= 2) failRepair()
            val ticket = WakeTicket(uuid(), uuid())
            requireWorkspaceId(ticket.token); requireWorkspaceId(ticket.workId)
            if (record.tickets.any { it.token == ticket.token || it.workId == ticket.workId }) failRepair()
            record = record.copy(tickets = retained + ticket)
            journal.write(record)
            work.appendOrReplace(ticket)
        } catch (_: Exception) { failRepair() }
    }

    @Synchronized fun drained(token: String) {
        try {
            val record = journal.read(); checkRecord(record)
            if (record.tickets.none { it.token == token }) failRepair()
            journal.write(record.copy(drainedToken = token))
        } catch (_: Exception) { failRepair() }
    }

    private fun checkRecord(record: WakeRecord) {
        if (record.tickets.size > 2 || record.tickets.map { it.token }.toSet().size != record.tickets.size ||
            record.tickets.map { it.workId }.toSet().size != record.tickets.size) failRepair()
        record.tickets.forEach { requireWorkspaceId(it.token); requireWorkspaceId(it.workId) }
    }
    private fun failRepair(): Nothing = throw SyncLocalFailure("SYNC_WAKE_REPAIR_REQUIRED")
}

class SyncOpportunityHook(private val pump: SyncWakePump, private val repairNeeded: () -> Unit = {}) {
    fun committed(account: Boolean, syncEnabled: Boolean, outboxChanged: Boolean) {
        if (!account || !syncEnabled || !outboxChanged) return
        try { pump.request() } catch (_: SyncLocalFailure) { repairNeeded() }
    }
}
