package com.excellentcalendar.excellent_calendar.bridge.sync

import java.time.Instant

data class BootRecord(val bootCount: Int?, val id: String, val elapsedMillis: Long)
data class BootObservation(val id: String, val elapsedMillis: Long)
interface BootRecordStore {
    /** Implementations must authenticate installation/schema AAD and exact BootEpochRecord shape. */
    fun read(): BootRecord?
    fun write(value: BootRecord)
}

/** Unique application owner; Android adapter supplies BOOT_COUNT and elapsedRealtime, never wall time. */
class BootEpochProvider(private val store: BootRecordStore, private val uuid: () -> String) {
    private var process: BootRecord? = null
    private var poisoned = false

    @Synchronized fun observe(api: Int, bootCount: Int?, elapsedMillis: Long): BootObservation {
        try {
            if (poisoned || elapsedMillis !in 0..MAX_SYNC_COUNTER || bootCount != null && bootCount < 0) untrusted()
            val count = if (api >= 24) bootCount else null
            val previous = if (count == null) process else process ?: store.read()
            if (previous != null) {
                requireWorkspaceId(previous.id)
                if (previous.elapsedMillis !in 0..MAX_SYNC_COUNTER || previous.bootCount != null && previous.bootCount < 0) untrusted()
                if (count != null && previous.bootCount != null && count < previous.bootCount) untrusted()
                if (count == previous.bootCount && elapsedMillis < previous.elapsedMillis) untrusted()
            }
            val same = previous != null && count == previous.bootCount
            val id = if (same) previous!!.id else uuid().also {
                requireWorkspaceId(it)
                if (it == previous?.id) untrusted()
            }
            val record = BootRecord(count, id, elapsedMillis)
            if (count != null) store.write(record)
            process = record
            return BootObservation(id, elapsedMillis)
        } catch (_: Exception) {
            poisoned = true
            untrusted()
        }
    }
    private fun untrusted(): Nothing = throw SyncLocalFailure("RETENTION_TRUSTED_TIME_REQUIRED")
}

data class TrustedTimeAnchor(val serverTime: Instant, val bootId: String, val elapsedMillis: Long)
data class RetentionDeadline(val startedAt: Instant, val until: Instant, val anchor: TrustedTimeAnchor)

object RetentionClock {
    fun retain(anchor: TrustedTimeAnchor?, observation: BootObservation): RetentionDeadline {
        val trusted = anchor ?: throw SyncLocalFailure("RETENTION_TRUSTED_TIME_REQUIRED")
        val now = fromAnchor(trusted, observation) ?: throw SyncLocalFailure("RETENTION_TRUSTED_TIME_REQUIRED")
        // Persisted contract has second precision. Dropping subsecond elapsed cannot extend retention.
        val start = now.truncatedTo(java.time.temporal.ChronoUnit.SECONDS)
        return RetentionDeadline(start, start.plusSeconds(30L * 24 * 60 * 60), trusted)
    }

    /** httpsServerTime is accepted only after strict no-store system.time verification by its HTTP adapter. */
    fun expired(record: RetentionDeadline, observation: BootObservation, httpsServerTime: Instant? = null): Boolean {
        val now = fromAnchor(record.anchor, observation) ?: httpsServerTime ?: return false
        return !now.isBefore(record.until)
    }

    private fun fromAnchor(anchor: TrustedTimeAnchor, observation: BootObservation): Instant? {
        if (anchor.bootId != observation.id || anchor.elapsedMillis !in 0..MAX_SYNC_COUNTER ||
            observation.elapsedMillis !in anchor.elapsedMillis..MAX_SYNC_COUNTER) return null
        return try { anchor.serverTime.plusMillis(observation.elapsedMillis - anchor.elapsedMillis) }
        catch (_: Exception) { null }
    }
}
