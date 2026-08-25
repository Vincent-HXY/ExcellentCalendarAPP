package com.excellentcalendar.cloud.identity.infrastructure;

import static org.assertj.core.api.Assertions.assertThat;

import com.excellentcalendar.cloud.identity.domain.RateLimiter;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.concurrent.atomic.AtomicLong;
import org.junit.jupiter.api.Test;

class InMemoryRateLimiterTest {

    @Test
    void allowsUpToTheWindowCapacityAndThenRejectsWithRetryHint() {
        Clock clock = Clock.fixed(Instant.parse("2026-08-16T00:00:00Z"), ZoneId.of("UTC"));
        InMemoryRateLimiter limiter = new InMemoryRateLimiter(clock);
        RateLimiter.Rule rule = new RateLimiter.Rule(2, 60);

        assertThat(limiter.tryAcquire("key", rule).allowed()).isTrue();
        assertThat(limiter.tryAcquire("key", rule).allowed()).isTrue();
        RateLimiter.Result rejected = limiter.tryAcquire("key", rule);
        assertThat(rejected.allowed()).isFalse();
        assertThat(rejected.retryAfterSeconds()).isEqualTo(60);
    }

    @Test
    void rejectsIndependentlyPerKey() {
        Clock clock = Clock.fixed(Instant.parse("2026-08-16T00:00:00Z"), ZoneId.of("UTC"));
        InMemoryRateLimiter limiter = new InMemoryRateLimiter(clock);
        RateLimiter.Rule rule = new RateLimiter.Rule(1, 60);

        assertThat(limiter.tryAcquire("a", rule).allowed()).isTrue();
        assertThat(limiter.tryAcquire("b", rule).allowed()).isTrue();
        assertThat(limiter.tryAcquire("a", rule).allowed()).isFalse();
    }

    @Test
    void windowResetsAfterTheIntervalOnTheSameInstance() {
        // A mutable clock: the SAME limiter instance must observe the window reset, not a fresh
        // instance with a shifted fixed clock (which would prove nothing).
        AtomicLong millis = new AtomicLong(Instant.parse("2026-08-16T00:00:00Z").toEpochMilli());
        Clock clock = mutableClock(millis);
        InMemoryRateLimiter limiter = new InMemoryRateLimiter(clock);
        RateLimiter.Rule rule = new RateLimiter.Rule(1, 60);

        assertThat(limiter.tryAcquire("key", rule).allowed()).isTrue();
        assertThat(limiter.tryAcquire("key", rule).allowed()).isFalse();

        millis.addAndGet(61_000);
        assertThat(limiter.tryAcquire("key", rule).allowed()).isTrue();
        // The old window was replaced, not merely bypassed: one live window remains.
        assertThat(limiter.activeKeys()).isEqualTo(1);
    }

    private static Clock mutableClock(AtomicLong epochMillis) {
        return new Clock() {
            @Override
            public ZoneId getZone() {
                return ZoneOffset.UTC;
            }

            @Override
            public Clock withZone(ZoneId zone) {
                return this;
            }

            @Override
            public Instant instant() {
                return Instant.ofEpochMilli(epochMillis.get());
            }
        };
    }
}
