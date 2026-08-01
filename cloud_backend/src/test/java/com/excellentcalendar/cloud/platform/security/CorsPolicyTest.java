package com.excellentcalendar.cloud.platform.security;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.web.cors.CorsConfiguration;

class CorsPolicyTest {

    @Test
    void browserOriginsAreDeniedByDefault() {
        CorsProperties properties = new CorsProperties();
        ApiSecurityConfiguration security = new ApiSecurityConfiguration();
        MockHttpServletRequest request = new MockHttpServletRequest("OPTIONS", "/api/v1/auth/login");

        CorsConfiguration configuration = security.corsConfigurationSource(properties)
                .getCorsConfiguration(request);

        assertThat(configuration).isNotNull();
        assertThat(configuration.getAllowedOrigins()).isEmpty();
        assertThat(configuration.getAllowCredentials()).isFalse();
    }

    @Test
    void configuredOriginsAreExplicitAndNeverWildcarded() {
        CorsProperties properties = new CorsProperties();
        properties.setAllowedOrigins(List.of("https://admin.example.com"));
        ApiSecurityConfiguration security = new ApiSecurityConfiguration();
        MockHttpServletRequest request = new MockHttpServletRequest("OPTIONS", "/api/v1/users/me");

        CorsConfiguration configuration = security.corsConfigurationSource(properties)
                .getCorsConfiguration(request);

        assertThat(configuration).isNotNull();
        assertThat(configuration.getAllowedOrigins()).containsExactly("https://admin.example.com");
        assertThat(configuration.getAllowedOrigins()).doesNotContain("*");
    }
}
