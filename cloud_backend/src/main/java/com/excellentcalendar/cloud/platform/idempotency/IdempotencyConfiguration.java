package com.excellentcalendar.cloud.platform.idempotency;

import tools.jackson.databind.ObjectMapper;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;

@Profile("api")
@Configuration(proxyBeanMethods = false)
@EnableConfigurationProperties(IdempotencyProperties.class)
public class IdempotencyConfiguration {

    @Bean
    IdempotencyFilter idempotencyFilter(IdempotencyStore store, ObjectMapper objectMapper) {
        return new IdempotencyFilter(store, objectMapper);
    }
}
