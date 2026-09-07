package com.excellentcalendar.excellent_calendar.bridge.sync

import java.net.URI
import java.security.MessageDigest

/** Shared identity primitive; existing v2 receivers must not infer a workspace from the active UI. */
object WorkspacePlatformIdentity {
    fun alarm(workspace: String, reminder: String): String {
        requireWorkspaceId(workspace); requireWorkspaceId(reminder)
        return "calendar://alarm/$workspace/$reminder"
    }

    fun parseAlarm(value: String): Pair<String, String> {
        val uri = try { URI(value) } catch (_: Exception) { throw SyncLocalFailure("WORKSPACE_IDENTITY_INVALID") }
        val pieces = uri.rawPath?.split('/') ?: emptyList()
        if (uri.scheme != "calendar" || uri.rawAuthority != "alarm" || uri.rawQuery != null || uri.rawFragment != null || pieces.size != 3) {
            throw SyncLocalFailure("WORKSPACE_IDENTITY_INVALID")
        }
        requireWorkspaceId(pieces[1]); requireWorkspaceId(pieces[2])
        return pieces[1] to pieces[2]
    }

    fun work(workspace: String, device: String): String {
        requireWorkspaceId(workspace); requireWorkspaceId(device)
        val hash = MessageDigest.getInstance("SHA-256").digest("$workspace/$device".toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it.toInt() and 255) }
        return "calendar-sync-v1-$hash"
    }
}
