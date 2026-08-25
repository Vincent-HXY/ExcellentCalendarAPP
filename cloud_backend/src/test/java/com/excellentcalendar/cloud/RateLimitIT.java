package com.excellentcalendar.cloud;

import static org.assertj.core.api.Assertions.assertThat;

import tools.jackson.databind.JsonNode;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.test.context.TestPropertySource;

/**
 * Rate limiting uses its own context with strict limits; the rest of the suite runs with raised
 * limits (see src/test/resources/application-api.yml).
 */
@TestPropertySource(properties = {
        "excellent-calendar.security.rate-limit.login-max-per-window=2",
        "excellent-calendar.security.rate-limit.login-window-seconds=60",
        "excellent-calendar.security.rate-limit.register-max-per-window=1",
        "excellent-calendar.security.rate-limit.register-window-seconds=3600"
})
class RateLimitIT extends ApiIntegrationTestSupport {

    @Test
    void loginIsThrottledPerIpAndEmailWithRetryHint() {
        String email = "user-" + UUID.randomUUID() + "@example.com";
        // Wrong-password attempts still consume the bucket.
        ApiResponse first = postJson("/auth/login", """
                {"email":"%s","password":"whatever12345"}
                """.formatted(email));
        ApiResponse second = postJson("/auth/login", """
                {"email":"%s","password":"whatever12345"}
                """.formatted(email));
        ApiResponse third = postJson("/auth/login", """
                {"email":"%s","password":"whatever12345"}
                """.formatted(email));

        assertThat(first.status()).isEqualTo(HttpStatus.UNAUTHORIZED.value());
        assertThat(second.status()).isEqualTo(HttpStatus.UNAUTHORIZED.value());
        assertThat(third.status()).isEqualTo(HttpStatus.TOO_MANY_REQUESTS.value());
        assertThat(third.body().path("error").path("code").asText()).isEqualTo("API_RATE_LIMITED");
        assertThat(third.body().path("error").path("retry_after_seconds").asInt()).isPositive();
        assertThat(third.header("Retry-After")).isNotBlank();
    }

    @Test
    void registerIsThrottledPerIp() {
        String body = """
                {"email":"%s","username":"%s","display_name":"Calendar User","password":"CorrectHorseBattery",
                 "locale":"zh-CN","timezone":"Asia/Shanghai",
                 "agreement_version":"terms-v1","agreement_accepted":true}
                """.formatted("user-" + UUID.randomUUID() + "@example.com",
                "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12));

        ApiResponse first = postJson("/auth/register", body,
                "Idempotency-Key", UUID.randomUUID().toString());
        ApiResponse second = postJson("/auth/register", """
                {"email":"%s","username":"%s","display_name":"Calendar User","password":"CorrectHorseBattery",
                 "locale":"zh-CN","timezone":"Asia/Shanghai",
                 "agreement_version":"terms-v1","agreement_accepted":true}
                """.formatted("user-" + UUID.randomUUID() + "@example.com",
                "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12)),
                "Idempotency-Key", UUID.randomUUID().toString());

        assertThat(first.status()).isEqualTo(HttpStatus.OK.value());
        assertThat(second.status()).isEqualTo(HttpStatus.TOO_MANY_REQUESTS.value());
        assertThat(second.body().path("error").path("code").asText()).isEqualTo("API_RATE_LIMITED");
    }
}
