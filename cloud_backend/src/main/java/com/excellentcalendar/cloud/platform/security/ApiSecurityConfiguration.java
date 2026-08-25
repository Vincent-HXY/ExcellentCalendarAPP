package com.excellentcalendar.cloud.platform.security;

import com.excellentcalendar.cloud.platform.idempotency.IdempotencyFilter;
import tools.jackson.databind.ObjectMapper;
import java.time.Duration;
import java.util.List;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.access.intercept.AuthorizationFilter;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

/**
 * Stateless API security: health and the declared public endpoints are open, protected routes
 * require the verified bearer token, everything else is denied. Avatar bytes are served under
 * the documented internal static path (GET /api/v1/media/avatars/**), see
 * docs/decisions/0004-identity-tech-selection.md.
 */
@Profile("api")
@Configuration(proxyBeanMethods = false)
@EnableConfigurationProperties({CorsProperties.class, JwtProperties.class})
public class ApiSecurityConfiguration {

    private static final String[] PUBLIC_AUTH_POST_PATHS = {
            "/api/v1/auth/register",
            "/api/v1/auth/registration/verify",
            "/api/v1/auth/registration/resend",
            "/api/v1/auth/login",
            "/api/v1/auth/token/refresh",
            "/api/v1/auth/logout",
            "/api/v1/auth/password-reset/request",
            "/api/v1/auth/password-reset/confirm"
    };

    @Bean
    SecurityFilterChain apiSecurityFilterChain(
            HttpSecurity http,
            AccessTokenVerifier accessTokenVerifier,
            AuthenticatedPrincipalResolver principalResolver,
            IdempotencyFilter idempotencyFilter,
            ObjectMapper objectMapper) throws Exception {
        BearerTokenAuthenticationFilter bearerFilter =
                new BearerTokenAuthenticationFilter(accessTokenVerifier, principalResolver, objectMapper);
        return http
                .csrf(AbstractHttpConfigurer::disable)
                .cors(Customizer.withDefaults())
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .formLogin(AbstractHttpConfigurer::disable)
                .httpBasic(AbstractHttpConfigurer::disable)
                .exceptionHandling(exceptionHandling -> exceptionHandling
                        .authenticationEntryPoint(new ApiSecurityErrorHandlers.EntryPoint(objectMapper))
                        .accessDeniedHandler(new ApiSecurityErrorHandlers.DeniedHandler(objectMapper)))
                .authorizeHttpRequests(authorize -> authorize
                        .requestMatchers("/actuator/health", "/actuator/health/**").permitAll()
                        .requestMatchers(HttpMethod.POST, PUBLIC_AUTH_POST_PATHS).permitAll()
                        .requestMatchers(HttpMethod.GET, "/api/v1/media/avatars", "/api/v1/media/avatars/**")
                        .permitAll()
                        .requestMatchers("/api/**").authenticated()
                        .anyRequest().denyAll())
                .addFilterBefore(bearerFilter, AuthorizationFilter.class)
                .addFilterAfter(idempotencyFilter, BearerTokenAuthenticationFilter.class)
                .build();
    }

    @Bean
    CorsConfigurationSource corsConfigurationSource(CorsProperties properties) {
        CorsConfiguration configuration = new CorsConfiguration();
        configuration.setAllowedOrigins(properties.getAllowedOrigins());
        configuration.setAllowedMethods(List.of("GET", "POST", "PATCH", "DELETE", "OPTIONS"));
        configuration.setAllowedHeaders(List.of("Accept", "Authorization", "Content-Type", "Idempotency-Key"));
        configuration.setAllowCredentials(false);
        configuration.setMaxAge(Duration.ofHours(1));

        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/api/**", configuration);
        return source;
    }
}
