package com.excellentcalendar.cloud.identity.domain;

/**
 * Port for per-key fixed-window rate limiting (single-instance in-memory implementation in this
 * phase). Keys are chosen by the application layer; the port never decides policy.
 */
public interface RateLimiter {

    record Rule(int maxPerWindow, int windowSeconds) {
    }

    record Result(boolean allowed, int retryAfterSeconds) {
    }

    Result tryAcquire(String key, Rule rule);
}
