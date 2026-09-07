package com.excellentcalendar.excellent_calendar.bridge.sync

import java.time.Instant
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.*
import org.junit.Test

class RefreshFlightCoordinatorTest {
    private val now = Instant.parse("2026-09-07T00:00:00Z")
    private fun tokens(number: Int = 0) = RotatedCredentials("synthetic-at-$number", "synthetic-rt-$number", now.plusSeconds(3600))
    @Test fun validityRequestUsesFrozenNineHundredSecondMaximum() {
        var calls = 0
        val broker = RefreshFlightCoordinator(1, 0, "synthetic", null, { calls++; tokens() }, {}, {}, { now })
        failure("AUTH_TOKEN_GENERATION_INVALID") { broker.access(901, null) }
        assertEquals(0, calls)
        assertEquals(1L, broker.access(900, null).generation)
    }
    @Test fun hundredConcurrentRequestsPerformOneRefreshAndPublishAfterPersistence() {
        val calls = AtomicInteger()
        val entered = CountDownLatch(1); val release = CountDownLatch(1)
        val durable = mutableListOf<String>()
        val broker = RefreshFlightCoordinator(7, 0, "synthetic-rt-0", null,
            { calls.incrementAndGet(); entered.countDown(); check(release.await(5, TimeUnit.SECONDS)); tokens(1) },
            { durable.add(it.refreshToken) }, {}, { now })
        val pool = Executors.newFixedThreadPool(100)
        try {
            val results = (1..100).map { pool.submit<AccessSnapshot> { broker.access(60, null) } }
            assertTrue(entered.await(5, TimeUnit.SECONDS)); assertTrue(durable.isEmpty())
            release.countDown()
            results.forEach { assertEquals(1L, it.get(10, TimeUnit.SECONDS).generation) }
            assertEquals(1, calls.get()); assertEquals(listOf("synthetic-rt-1"), durable)
            assertEquals(7L, broker.access(0, 0).sessionGeneration)
            assertEquals(1, calls.get())
            assertEquals(2L, broker.access(0, 1).generation)
            assertEquals(2, calls.get())
        } finally { release.countDown(); pool.shutdownNow() }
    }
    @Test fun logoutInvalidatesFlightAndNeverPublishesLateResponse() {
        val entered = CountDownLatch(1); val release = CountDownLatch(1)
        var persisted = false
        val broker = RefreshFlightCoordinator(1, 0, "synthetic", null,
            { entered.countDown(); check(release.await(5, TimeUnit.SECONDS)); tokens() }, { persisted = true }, {}, { now })
        val pool = Executors.newSingleThreadExecutor()
        try {
            val result = pool.submit { failure("AUTH_SESSION_EXPIRED") { broker.access(60, null) } }
            assertTrue(entered.await(5, TimeUnit.SECONDS)); broker.invalidate()
            release.countDown(); result.get(5, TimeUnit.SECONDS)
            assertFalse(persisted)
            failure("AUTH_SESSION_EXPIRED") { broker.access(0, null) }
        } finally { release.countDown(); pool.shutdownNow() }
    }
    @Test fun uncertainRotationOrPersistenceFailureRetiresOldRefreshToken() {
        for (networkFailure in listOf(false, true)) {
            var calls = 0; var erased = false
            val broker = RefreshFlightCoordinator(1, 0, "synthetic", null,
                { calls++; if (networkFailure) throw IllegalStateException("uncertain"); tokens() },
                { throw IllegalStateException("disk-full") }, { erased = true }, { now })
            failure("AUTH_SESSION_EXPIRED") { broker.access(0, null) }
            failure("AUTH_SESSION_EXPIRED") { broker.access(0, null) }
            assertTrue(erased); assertEquals(1, calls)
        }
    }
    @Test fun knownUnsentTransportFailureMayRetryAndFutureGenerationIsRejected() {
        var calls = 0
        val broker = RefreshFlightCoordinator(1, 0, "synthetic", null,
            { calls++; if (calls == 1) throw RefreshNotSent(); tokens() }, {}, {}, { now })
        failure("TRANSPORT_UNAVAILABLE") { broker.access(0, null) }
        assertEquals(1L, broker.access(0, null).generation)
        failure("AUTH_TOKEN_GENERATION_INVALID") { broker.access(0, 100) }
        assertFalse(broker.access(0, null).toString().contains("synthetic"))
    }
}
