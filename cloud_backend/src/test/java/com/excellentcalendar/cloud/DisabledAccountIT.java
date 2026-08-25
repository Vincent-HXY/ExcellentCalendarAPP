package com.excellentcalendar.cloud;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;

/**
 * Disabled-account behaviour: every bearer endpoint must stay inside its declared error list.
 * The shared principal resolver maps a disabled account to AUTH_SESSION_EXPIRED (declared by all
 * bearer endpoints), while auth.token.refresh emits AUTH_ACCOUNT_DISABLED (declared there).
 */
class DisabledAccountIT extends ApiIntegrationTestSupport {

    @BeforeEach
    void clearMail() {
        mailSender.clear();
    }

    @Test
    void disabledAccountBearerEndpointsReturnDeclaredCodesOnly() {
        String email = "user-" + UUID.randomUUID() + "@example.com";
        ApiResponse register = postJson("/auth/register", """
                {"email":"%s","username":"%s","display_name":"Calendar User","password":"CorrectHorseBattery",
                 "locale":"zh-CN","timezone":"Asia/Shanghai",
                 "agreement_version":"terms-v1","agreement_accepted":true}
                """.formatted(email, "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12)),
                "Idempotency-Key", UUID.randomUUID().toString());
        String challengeId = register.body().path("data").path("challenge").path("challenge_id").asText();
        ApiResponse verify = postJson("/auth/registration/verify", """
                {"challenge_id":"%s","credential":{"credential_type":"code","code":"%s"}}
                """.formatted(challengeId, mailSender.latestCode(email)));
        String refreshToken = verify.body().path("data").path("tokens").path("refresh_token").asText();

        ApiResponse login = postJson("/auth/login", """
                {"email":"%s","password":"CorrectHorseBattery"}
                """.formatted(email));
        String accessToken = login.body().path("data").path("tokens").path("access_token").asText();

        // Disable the account out-of-band (no admin endpoint exists in this phase).
        jdbcTemplate.update("""
                UPDATE user_accounts
                SET status = 'disabled', disabled_at = now(), updated_at = now()
                WHERE normalized_email = ?
                """, email);

        // auth.logout_all does NOT declare AUTH_ACCOUNT_DISABLED: it must receive one of its
        // declared codes (AUTH_SESSION_EXPIRED), never an undeclared one.
        ApiResponse logoutAll = postJson("/auth/logout-all", "{}", "Authorization", auth(accessToken));
        assertThat(logoutAll.status()).isEqualTo(HttpStatus.UNAUTHORIZED.value());
        assertThat(logoutAll.body().path("error").path("code").asText())
                .isEqualTo("AUTH_SESSION_EXPIRED");

        // Other bearer endpoints stay inside their declared lists too.
        ApiResponse me = getJson("/users/me", "Authorization", auth(accessToken));
        assertThat(me.status()).isEqualTo(HttpStatus.UNAUTHORIZED.value());
        assertThat(me.body().path("error").path("code").asText())
                .isEqualTo("AUTH_SESSION_EXPIRED");

        // Refresh declares AUTH_ACCOUNT_DISABLED and keeps emitting it.
        ApiResponse refresh = postJson("/auth/token/refresh", """
                {"refresh_token":"%s"}
                """.formatted(refreshToken));
        assertThat(refresh.status()).isEqualTo(HttpStatus.FORBIDDEN.value());
        assertThat(refresh.body().path("error").path("code").asText())
                .isEqualTo("AUTH_ACCOUNT_DISABLED");
    }

    @Test
    void resendToADisabledAccountIsRejectedWithoutMail() {
        String email = "user-" + UUID.randomUUID() + "@example.com";
        ApiResponse register = postJson("/auth/register", """
                {"email":"%s","username":"%s","display_name":"Calendar User","password":"CorrectHorseBattery",
                 "locale":"zh-CN","timezone":"Asia/Shanghai",
                 "agreement_version":"terms-v1","agreement_accepted":true}
                """.formatted(email, "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12)),
                "Idempotency-Key", UUID.randomUUID().toString());
        String challengeId = register.body().path("data").path("challenge").path("challenge_id").asText();
        mailSender.clear();

        jdbcTemplate.update("""
                UPDATE user_accounts
                SET status = 'disabled', disabled_at = now(), updated_at = now()
                WHERE normalized_email = ?
                """, email);

        // The contract declares AUTH_ACCOUNT_DISABLED for resend; disabled accounts must not
        // receive verification mail.
        ApiResponse resend = postJson("/auth/registration/resend", """
                {"challenge_id":"%s"}
                """.formatted(challengeId),
                "Idempotency-Key", UUID.randomUUID().toString());
        assertThat(resend.status()).isEqualTo(HttpStatus.FORBIDDEN.value());
        assertThat(resend.body().path("error").path("code").asText())
                .isEqualTo("AUTH_ACCOUNT_DISABLED");
        assertThat(mailSender.hasMailFor(email)).isFalse();
    }

    @Test
    void deletedAccountRefreshMapsToAccountDisabledPerAdr() {
        String email = "user-" + UUID.randomUUID() + "@example.com";
        ApiResponse register = postJson("/auth/register", """
                {"email":"%s","username":"%s","display_name":"Calendar User","password":"CorrectHorseBattery",
                 "locale":"zh-CN","timezone":"Asia/Shanghai",
                 "agreement_version":"terms-v1","agreement_accepted":true}
                """.formatted(email, "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12)),
                "Idempotency-Key", UUID.randomUUID().toString());
        String challengeId = register.body().path("data").path("challenge").path("challenge_id").asText();
        String refreshToken = postJson("/auth/registration/verify", """
                {"challenge_id":"%s","credential":{"credential_type":"code","code":"%s"}}
                """.formatted(challengeId, mailSender.latestCode(email)))
                .body().path("data").path("tokens").path("refresh_token").asText();

        jdbcTemplate.update("""
                UPDATE user_accounts
                SET status = 'deleted', deleted_at = now(), updated_at = now()
                WHERE normalized_email = ?
                """, email);

        // ADR-0004 §3: disabled AND deleted accounts map to AUTH_ACCOUNT_DISABLED on refresh.
        ApiResponse refresh = postJson("/auth/token/refresh", """
                {"refresh_token":"%s"}
                """.formatted(refreshToken));
        assertThat(refresh.status()).isEqualTo(HttpStatus.FORBIDDEN.value());
        assertThat(refresh.body().path("error").path("code").asText())
                .isEqualTo("AUTH_ACCOUNT_DISABLED");
    }
}
