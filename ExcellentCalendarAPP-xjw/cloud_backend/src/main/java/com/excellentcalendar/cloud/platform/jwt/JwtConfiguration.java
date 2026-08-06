package com.excellentcalendar.cloud.platform.jwt;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;

/**
 * Wires the JWT utility bean for the API profile.
 */
@Profile("api")
@Configuration(proxyBeanMethods = false)
@EnableConfigurationProperties(JwtProperties.class)
public class JwtConfiguration {

    @Bean
    JwtTokenService jwtTokenService(JwtProperties properties) {
        return new JwtTokenService(properties);
    }
}