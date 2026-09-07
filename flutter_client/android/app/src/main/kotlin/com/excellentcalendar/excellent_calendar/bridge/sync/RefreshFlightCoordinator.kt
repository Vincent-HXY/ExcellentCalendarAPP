package com.excellentcalendar.excellent_calendar.bridge.sync

import java.time.Instant
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ExecutionException
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

class RotatedCredentials(val accessToken: String, val refreshToken: String, val expiresAt: Instant) {
    override fun toString() = "RotatedCredentials(redacted)"
}

class AccessSnapshot(val token: String, val expiresAt: Instant, val sessionGeneration: Long, val generation: Long) {
    override fun toString() = "AccessSnapshot(redacted)"
}

/** Only use when transport proves no request bytes were sent; response loss must never use this type. */
class RefreshNotSent : RuntimeException()

/** Single-flight primitive for the future Broker. Does not adopt a session or own legacy credentials. */
class RefreshFlightCoordinator(
    private var sessionGeneration: Long,
    private var tokenGeneration: Long,
    private var refreshToken: String?,
    initialAccess: AccessSnapshot?,
    private val refresh: (String) -> RotatedCredentials,
    private val persistRotation: (RotatedCredentials) -> Unit,
    private val eraseCredentials: () -> Unit,
    private val now: () -> Instant,
) {
    private val lock = ReentrantLock()
    // Storage operations are serialized with termination; this lock never surrounds HTTP.
    private val storage = ReentrantLock()
    private var current = initialAccess
    private var flight: CompletableFuture<AccessSnapshot>? = null

    fun access(minimumValiditySeconds: Int, rejectedGeneration: Long?): AccessSnapshot {
        if (minimumValiditySeconds !in 0..900) throw SyncLocalFailure("AUTH_TOKEN_GENERATION_INVALID")
        var owner = false
        var token = ""
        var capturedSession = 0L
        val future = lock.withLock {
            val rt = refreshToken ?: throw SyncLocalFailure("AUTH_SESSION_EXPIRED")
            if (rejectedGeneration != null && (rejectedGeneration < 0 || rejectedGeneration > tokenGeneration)) {
                throw SyncLocalFailure("AUTH_TOKEN_GENERATION_INVALID")
            }
            current?.let { value ->
                if (value.expiresAt.isAfter(now().plusSeconds(minimumValiditySeconds.toLong())) &&
                    (rejectedGeneration == null || rejectedGeneration < value.generation)) return value
            }
            flight ?: CompletableFuture<AccessSnapshot>().also {
                flight = it; owner = true; token = rt; capturedSession = sessionGeneration
            }
        }
        if (owner) performRefresh(future, token, capturedSession)
        try { return future.get() }
        catch (error: ExecutionException) { throw error.cause as? SyncLocalFailure ?: SyncLocalFailure("AUTH_SESSION_EXPIRED") }
        catch (_: InterruptedException) { Thread.currentThread().interrupt(); throw SyncLocalFailure("REQUEST_CANCELLED") }
    }

    private fun performRefresh(future: CompletableFuture<AccessSnapshot>, rt: String, captured: Long) {
        try {
            val result = refresh(rt)
            if (result.accessToken.isBlank() || result.refreshToken.isBlank() || !result.expiresAt.isAfter(now())) {
                throw SyncLocalFailure("AUTH_SESSION_EXPIRED")
            }
            val snapshot = storage.withLock {
                val next = lock.withLock {
                    if (sessionGeneration != captured || refreshToken == null) throw SyncLocalFailure("AUTH_SESSION_EXPIRED")
                    nextCounter(tokenGeneration, "AUTH_TOKEN_GENERATION_EXHAUSTED")
                }
                persistRotation(result)
                lock.withLock {
                    val value = AccessSnapshot(result.accessToken, result.expiresAt, captured, next)
                    refreshToken = result.refreshToken; tokenGeneration = next; current = value; value
                }
            }
            future.complete(snapshot)
        } catch (_: RefreshNotSent) {
            future.completeExceptionally(SyncLocalFailure("TRANSPORT_UNAVAILABLE"))
        } catch (_: Exception) {
            try { invalidateIfCurrent(captured) } catch (_: Exception) { /* Remains unusable even if secure erase needs repair. */ }
            future.completeExceptionally(SyncLocalFailure("AUTH_SESSION_EXPIRED"))
        } finally { lock.withLock { if (flight === future) flight = null } }
    }

    fun invalidate() { invalidateIfCurrent(null) }

    private fun invalidateIfCurrent(expected: Long?) = storage.withLock {
        val invalidated = lock.withLock {
            if (expected != null && sessionGeneration != expected) return@withLock false
            refreshToken = null; current = null
            if (sessionGeneration < MAX_SYNC_COUNTER) sessionGeneration++
            flight?.completeExceptionally(SyncLocalFailure("AUTH_SESSION_EXPIRED"))
            true
        }
        if (invalidated) eraseCredentials()
    }
}
