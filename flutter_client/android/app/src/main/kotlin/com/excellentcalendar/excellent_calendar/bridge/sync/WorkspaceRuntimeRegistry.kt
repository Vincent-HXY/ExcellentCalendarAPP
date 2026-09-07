package com.excellentcalendar.excellent_calendar.bridge.sync

import java.io.Closeable
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

interface WorkspaceRuntimePort {
    fun open(workspace: String): String
    fun close(workspace: String, runtime: String)
}

data class RouteSnapshot(val workspace: String?, val runtime: String?, val revision: Long)

/** Reusable routing primitive. Session authorization and encrypted open metadata belong to its caller. */
class WorkspaceRuntimeRegistry(
    private val native: WorkspaceRuntimePort,
    initialRoute: RouteSnapshot,
    private val persistRoute: (RouteSnapshot) -> Unit,
) {
    private class Runtime(val id: String, var leases: Int = 0, var closing: Boolean = false)
    private val lock = ReentrantLock()
    private val drained = lock.newCondition()
    // Serializes open/commit/close, but not ongoing leased calls or lease release.
    private val lifecycle = ReentrantLock()
    private val runtimes = mutableMapOf<String, Runtime>()
    private var active = initialRoute
    private var switching = false

    fun route(): RouteSnapshot = lock.withLock { active }

    fun activate(workspace: String, expectedRevision: Long): RouteSnapshot = lifecycle.withLock {
        requireWorkspaceId(workspace)
        val revision = lock.withLock {
            if (active.revision != expectedRevision || switching) throw SyncLocalFailure("WORKSPACE_SWITCH_CONFLICT")
            val next = nextCounter(active.revision, "WORKSPACE_ROUTE_REVISION_EXHAUSTED")
            switching = true; next
        }
        var opened: Runtime? = null
        try {
            val runtime = lock.withLock { runtimes[workspace] } ?: Runtime(native.open(workspace)).also { opened = it }
            if (runtime.id.isBlank() || runtime.closing) throw SyncLocalFailure("WORKSPACE_RUNTIME_CLOSED")
            val result = RouteSnapshot(workspace, runtime.id, revision)
            // No JNI/network under the registry lock. Persistence commits the complete tuple once.
            persistRoute(result)
            lock.withLock { runtimes[workspace] = runtime; active = result }
            result
        } catch (error: Exception) {
            opened?.let { candidate ->
                try { native.close(workspace, candidate.id) }
                catch (_: Exception) { lock.withLock { candidate.closing = true; runtimes[workspace] = candidate } }
            }
            throw error
        } finally { lock.withLock { switching = false } }
    }

    fun acquireRoute(expected: RouteSnapshot): Lease = lock.withLock {
        if (switching || expected != active) throw SyncLocalFailure("WORKSPACE_SWITCH_CONFLICT")
        val workspace = expected.workspace ?: throw SyncLocalFailure("WORKSPACE_RUNTIME_CLOSED")
        acquireLocked(workspace, expected.runtime)
    }

    fun acquireWorkspace(workspace: String): Lease = lock.withLock { acquireLocked(workspace, null) }

    private fun acquireLocked(workspace: String, expectedRuntime: String?): Lease {
        val runtime = runtimes[workspace] ?: throw SyncLocalFailure("WORKSPACE_RUNTIME_CLOSED")
        if (runtime.closing || expectedRuntime != null && expectedRuntime != runtime.id) throw SyncLocalFailure("WORKSPACE_RUNTIME_CLOSED")
        runtime.leases++
        return Lease(workspace, runtime.id) {
            lock.withLock { runtime.leases--; if (runtime.leases == 0) drained.signalAll() }
        }
    }

    fun closeWorkspace(workspace: String, afterBlocked: () -> Unit = {}) = lifecycle.withLock {
        val runtime = lock.withLock {
            val found = runtimes[workspace] ?: return@withLock null
            found.closing = true; found
        } ?: return@withLock
        afterBlocked()
        lock.withLock { while (runtime.leases != 0) drained.await() }
        native.close(workspace, runtime.id)
        lock.withLock { runtimes.remove(workspace) }
        // Lifecycle coordinator commits the subsequent locked/local route; no guest fallback here.
    }

    class Lease internal constructor(val workspace: String, val runtime: String, private val release: () -> Unit) : Closeable {
        private val closed = java.util.concurrent.atomic.AtomicBoolean()
        override fun close() { if (closed.compareAndSet(false, true)) release() }
    }
}
