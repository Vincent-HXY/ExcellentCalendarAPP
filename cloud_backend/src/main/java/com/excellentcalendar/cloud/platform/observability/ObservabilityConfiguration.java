package com.excellentcalendar.cloud.platform.observability;

import java.util.UUID;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration(proxyBeanMethods = false)
class ObservabilityConfiguration {

    @Bean
    RequestIdGenerator requestIdGenerator() {
        return () -> UUID.randomUUID().toString();
    }
}
