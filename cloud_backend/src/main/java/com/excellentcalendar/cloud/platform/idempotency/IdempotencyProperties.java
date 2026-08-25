package com.excellentcalendar.cloud.platform.idempotency;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties("excellent-calendar.idempotency")
public class IdempotencyProperties {

    private long ttlHours = 24;

    public long getTtlHours() {
        return ttlHours;
    }

    public void setTtlHours(long ttlHours) {
        this.ttlHours = ttlHours;
    }
}
