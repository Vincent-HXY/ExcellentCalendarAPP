package com.excellentcalendar.cloud.platform.api;

import org.springframework.boot.jackson.autoconfigure.JsonMapperBuilderCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import tools.jackson.databind.PropertyNamingStrategies;

/**
 * Wire format is the Contract's snake_case: Spring Boot 4 (Jackson 3) no longer supports the
 * {@code spring.jackson.property-naming-strategy} property, so the mapper is configured here.
 */
@Configuration(proxyBeanMethods = false)
public class JacksonConfiguration {

    @Bean
    JsonMapperBuilderCustomizer contractSnakeCaseNaming() {
        return builder -> builder.propertyNamingStrategy(PropertyNamingStrategies.SNAKE_CASE);
    }
}
