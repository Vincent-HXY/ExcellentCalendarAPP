package com.excellentcalendar.excellent_calendar.bridge.sync

/** Internal failure only. A v3 adapter must map through the frozen error schema before publishing. */
class SyncLocalFailure(val code: String) : RuntimeException(code)

internal const val MAX_SYNC_COUNTER = 9_007_199_254_740_991L
internal fun nextCounter(value: Long, error: String): Long {
    if (value < 0 || value >= MAX_SYNC_COUNTER) throw SyncLocalFailure(error)
    return value + 1
}

internal fun requireWorkspaceId(value: String) {
    if (!Regex("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$").matches(value)) {
        throw SyncLocalFailure("WORKSPACE_IDENTITY_INVALID")
    }
}
