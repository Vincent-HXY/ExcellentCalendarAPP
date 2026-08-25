package com.excellentcalendar.cloud.identity.infrastructure;

import com.excellentcalendar.cloud.identity.domain.RateLimiter;
import java.time.Clock;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import org.springframework.stereotype.Component;

/**
 * Single-instance fixed-window rate limiter with lazy eviction of expired windows: every 128
 * acquisitions (or whenever the map exceeds 4096 keys) expired entries are swept, so rotating
 * attacker keys cannot grow the map without bound. Redis is not required for this phase; the port
 * keeps the boundary so a shared implementation can replace it without touching application logic.
 */
@Component
public class InMemoryRateLimiter implements RateLimiter {

    private static final int SWEEP_INTERVAL = 128;
    private static final int SWEEP_SIZE_THRESHOLD = 4096;

    private final Clock clock;
    private final Map<String, Window> windows = new ConcurrentHashMap<>();
    private final AtomicInteger operations = new AtomicInteger();

    public InMemoryRateLimiter(Clock clock) {
        this.clock = clock;
    }

    @Override
    public Result tryAcquire(String key, Rule rule) {
        long now = clock.millis();
        long windowStart = now - (now % (rule.windowSeconds() * 1000L));
        Window window = windows.compute(key, (ignored, current) ->
                current == null || current.start() != windowStart
                        ? new Window(windowStart, now + rule.windowSeconds() * 1000L, 1)
                        : new Window(windowStart, current.expiresAt(), current.count() + 1));
        if (operations.incrementAndGet() % SWEEP_INTERVAL == 0 || windows.size() > SWEEP_SIZE_THRESHOLD) {
            sweep(now);
        }
        if (window.count() <= rule.maxPerWindow()) {
            return new Result(true, 0);
        }
        long retryAfterSeconds = Math.max(1, (windowStart + rule.windowSeconds() * 1000L - now + 999) / 1000);
        return new Result(false, (int) retryAfterSeconds);
    }

    private void sweep(long now) {
        windows.entrySet().removeIf(entry -> entry.getValue().expiresAt() <= now);
    }

    /**
     * Test/introspection only: number of live windows.
     */
    int activeKeys() {
        return windows.size();
    }

    private record Window(long start, long expiresAt, int count) {
    }
}
