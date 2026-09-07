package com.excellentcalendar.excellent_calendar.bridge.sync

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

class WorkspaceRuntimeRegistryTest {
    private class Native : WorkspaceRuntimePort {
        val open = mutableSetOf<String>()
        val closed = mutableListOf<String>()
        var failOpen = false
        override fun open(workspace: String): String {
            if (failOpen) throw SyncLocalFailure("WORKSPACE_KEY_UNAVAILABLE")
            open.add(workspace); return "runtime-$workspace"
        }
        override fun close(workspace: String, runtime: String) { open.remove(workspace); closed.add(workspace) }
    }
    @Test fun accountActivationPreservesGuestAndOldRouteCannotBeUsed() {
        val native = Native()
        var durable = RouteSnapshot(null, null, 0)
        val registry = WorkspaceRuntimeRegistry(native, durable) { durable = it }
        val guest = registry.activate(GUEST, 0)
        val account = registry.activate(ACCOUNT, guest.revision)
        assertEquals(setOf(GUEST, ACCOUNT), native.open)
        assertEquals(account, durable)
        failure("WORKSPACE_SWITCH_CONFLICT") { registry.acquireRoute(guest) }
        failure("WORKSPACE_SWITCH_CONFLICT") { registry.activate(GUEST, 0) }
        registry.acquireWorkspace(GUEST).close()
        registry.closeWorkspace(ACCOUNT)
        assertEquals(setOf(GUEST), native.open)
        assertEquals(listOf(ACCOUNT), native.closed)
    }
    @Test fun openOrCommitFailurePreservesOldAtomicRoute() {
        val native = Native()
        var rejectCommit = false
        val registry = WorkspaceRuntimeRegistry(native, RouteSnapshot(null, null, 0)) {
            if (rejectCommit) throw SyncLocalFailure("STORAGE_WRITE_FAILED")
        }
        val guest = registry.activate(GUEST, 0)
        native.failOpen = true
        failure("WORKSPACE_KEY_UNAVAILABLE") { registry.activate(ACCOUNT, 1) }
        assertEquals(guest, registry.route())
        native.failOpen = false; rejectCommit = true
        failure("STORAGE_WRITE_FAILED") { registry.activate(ACCOUNT, 1) }
        assertEquals(guest, registry.route())
        assertFalse(native.open.contains(ACCOUNT))
    }
    @Test fun closeWaitsForLeaseAndRejectsNewCallsWithoutHoldingCallerLock() {
        val native = Native()
        val registry = WorkspaceRuntimeRegistry(native, RouteSnapshot(null, null, 0)) {}
        registry.activate(GUEST, 0)
        val lease = registry.acquireWorkspace(GUEST)
        val marked = CountDownLatch(1)
        val pool = Executors.newSingleThreadExecutor()
        try {
            val closing = pool.submit { registry.closeWorkspace(GUEST) { marked.countDown() } }
            assertTrue(marked.await(5, TimeUnit.SECONDS))
            assertFalse(closing.isDone)
            failure("WORKSPACE_RUNTIME_CLOSED") { registry.acquireWorkspace(GUEST) }
            lease.close(); lease.close()
            closing.get(5, TimeUnit.SECONDS)
            assertEquals(listOf(GUEST), native.closed)
        } finally { lease.close(); pool.shutdownNow() }
    }
    @Test fun persistedRuntimeIsNeverReusedAfterRestartAndRevisionCannotWrap() {
        val native = Native()
        val old = RouteSnapshot(GUEST, "dead-runtime", 17)
        val registry = WorkspaceRuntimeRegistry(native, old) {}
        failure("WORKSPACE_RUNTIME_CLOSED") { registry.acquireRoute(old) }
        assertEquals(18L, registry.activate(GUEST, 17).revision)
        val exhausted = WorkspaceRuntimeRegistry(native, RouteSnapshot(null, null, 9_007_199_254_740_991L)) {}
        failure("WORKSPACE_ROUTE_REVISION_EXHAUSTED") { exhausted.activate(ACCOUNT, 9_007_199_254_740_991L) }
        assertFalse(native.open.contains(ACCOUNT))
    }
}
