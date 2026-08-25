package com.excellentcalendar.cloud.identity.infrastructure;

import static org.assertj.core.api.Assertions.assertThat;

import com.excellentcalendar.cloud.identity.domain.RateLimiter;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneId;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.Test;

/**
 * Lazy eviction: expired fixed-window entries are swept on a sampling cadence / size threshold so
 * rotating attacker keys cannot grow the map without bound.
 */
class InMemoryRateLimiterEvictionTest {

    private static final class MutableClock extends Clock {

        private final AtomicReference<Instant> instant = new AtomicReference<>();

        MutableClock(Instant start) {
            instant.set(start);
        }

        void advanceTo(Instant next) {
            instant.set(next);
        }

        @Override
        public ZoneId getZone() {
            return ZoneId.of("UTC");
        }

        @Override
        public Clock withZone(ZoneId zone) {
            return this;
        }

        @Override
        public Instant instant() {
            return instant.get();
        }
    }

    @Test
    void expiredWindowsAreSweptLazily() {
        Instant start = Instant.parse("2026-08-17T12:00:00Z");
        MutableClock clock = new MutableClock(start);
        InMemoryRateLimiter limiter = new InMemoryRateLimiter(clock);
        RateLimiter.Rule rule = new RateLimiter.Rule(1, 60);

        // Grow beyond the size threshold; nothing is expired yet, so nothing is removed.
        for (int i = 0; i < 4200; i++) {
            limiter.tryAcquire("key-" + i, rule);
        }
        assertThat(limiter.activeKeys()).isEqualTo(4200);

        // One hour later all windows are expired; the next acquisition triggers the sweep.
        clock.advanceTo(start.plusSeconds(3601));
        limiter.tryAcquire("fresh-key", rule);

        assertThat(limiter.activeKeys()).isEqualTo(1);
        assertThat(limiter.tryAcquire("fresh-key", rule).allowed()).isFalse();
    }
}
