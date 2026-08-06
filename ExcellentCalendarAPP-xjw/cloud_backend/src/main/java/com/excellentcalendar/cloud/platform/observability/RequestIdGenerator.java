package com.excellentcalendar.cloud.platform.observability;

@FunctionalInterface
public interface RequestIdGenerator {

    String nextRequestId();
}
