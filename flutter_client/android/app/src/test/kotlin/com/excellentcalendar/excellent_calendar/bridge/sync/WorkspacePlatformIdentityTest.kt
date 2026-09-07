package com.excellentcalendar.excellent_calendar.bridge.sync

import org.junit.Assert.*
import org.junit.Test

class WorkspacePlatformIdentityTest {
    @Test fun sameReminderIdCannotCollideAcrossWorkspaces() {
        assertNotEquals(WorkspacePlatformIdentity.alarm(GUEST, DEVICE), WorkspacePlatformIdentity.alarm(ACCOUNT, DEVICE))
        assertNotEquals(WorkspacePlatformIdentity.work(GUEST, DEVICE), WorkspacePlatformIdentity.work(ACCOUNT, DEVICE))
        assertFalse(WorkspacePlatformIdentity.work(ACCOUNT, DEVICE).contains(ACCOUNT))
        assertEquals(GUEST, WorkspacePlatformIdentity.parseAlarm(WorkspacePlatformIdentity.alarm(GUEST, DEVICE)).first)
        failure("WORKSPACE_IDENTITY_INVALID") { WorkspacePlatformIdentity.alarm("../account", DEVICE) }
        failure("WORKSPACE_IDENTITY_INVALID") { WorkspacePlatformIdentity.parseAlarm("calendar://alarm/$GUEST/$DEVICE?override=1") }
    }
}
