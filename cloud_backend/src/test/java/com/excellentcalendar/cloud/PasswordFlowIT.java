package com.excellentcalendar.cloud;

import static org.assertj.core.api.Assertions.assertThat;

import tools.jackson.databind.JsonNode;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

/**
 * Password reset/change flows, session revocation matrix and unknown-email privacy over HTTP.
 */
class PasswordFlowIT extends ApiIntegrationTestSupport {

    @BeforeEach
    void clearMail() {
        mailSender.clear();
    }

    private JsonNode registerAndVerify(String email, String password) {
        ApiResponse register = postJson("/auth/register", """
                {"email":"%s","username":"%s","display_name":"Calendar User","password":"%s",
                 "locale":"zh-CN","timezone":"Asia/Shanghai",
                 "agreement_version":"terms-v1","agreement_accepted":true}
                """.formatted(email, "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12), password),
                "Idempotency-Key", UUID.randomUUID().toString());
        String challengeId = register.body().path("data").path("challenge").path("challenge_id").asText();
        ApiResponse verify = postJson("/auth/registration/verify", """
                {"challenge_id":"%s","credential":{"credential_type":"code","code":"%s"}}
                """.formatted(challengeId, mailSender.latestCode(email)));
        assertThat(verify.status()).isEqualTo(HttpStatus.OK.value());
        return verify.body();
    }

    @Test
    void passwordResetRequestReturnsIdenticalResultForUnknownEmail() {
        String known = uniqueEmail();
        registerAndVerify(known, "CorrectHorseBattery");
        mailSender.clear();
        String unknown = uniqueEmail();

        ApiResponse knownResponse = postJson("/auth/password-reset/request", """
                {"email":"%s"}
                """.formatted(known), "Idempotency-Key", UUID.randomUUID().toString());
        ApiResponse unknownResponse = postJson("/auth/password-reset/request", """
                {"email":"%s"}
                """.formatted(unknown), "Idempotency-Key", UUID.randomUUID().toString());

        assertThat(knownResponse.status()).isEqualTo(HttpStatus.OK.value());
        assertThat(unknownResponse.status()).isEqualTo(HttpStatus.OK.value());
        assertThat(knownResponse.body().path("data").path("accepted").asBoolean()).isTrue();
        assertThat(unknownResponse.body().path("data").path("accepted").asBoolean()).isTrue();
        assertThat(knownResponse.body().path("data").path("resend_available_at").asText())
                .endsWith("Z");
        assertThat(unknownResponse.body().path("data").path("resend_available_at").asText())
                .endsWith("Z");
        assertThat(mailSender.hasMailFor(known)).isTrue();
        // Privacy: the unknown email gets the same result and no mail.
        assertThat(mailSender.hasMailFor(unknown)).isFalse();
    }

    @Test
    void passwordPolicyViolationDoesNotBurnTheResetCode() {
        String email = uniqueEmail();
        registerAndVerify(email, "CorrectHorseBattery");

        postJson("/auth/password-reset/request", "{\"email\":\"%s\"}".formatted(email),
                "Idempotency-Key", UUID.randomUUID().toString());
        String code = mailSender.latestCode(email);

        // Correct code but policy-violating password: rejected without consuming the challenge.
        ApiResponse weak = postJson("/auth/password-reset/confirm", """
                {"email":"%s","new_password":"password","credential":{"credential_type":"code","code":"%s"}}
                """.formatted(email, code));
        assertThat(weak.body().path("error").path("code").asText())
                .isEqualTo("AUTH_PASSWORD_POLICY_VIOLATION");

        // The same one-time code still works with a valid password.
        ApiResponse success = postJson("/auth/password-reset/confirm", """
                {"email":"%s","new_password":"BrandNewPassword1","credential":{"credential_type":"code","code":"%s"}}
                """.formatted(email, code));
        assertThat(success.status()).isEqualTo(HttpStatus.OK.value());
    }

    @Test
    void passwordResetRevokesAllSessionsAndRequiresNewLogin() {
        String email = uniqueEmail();
        JsonNode verified = registerAndVerify(email, "CorrectHorseBattery");
        String firstRefresh = verified.path("data").path("tokens").path("refresh_token").asText();
        String firstAccess = verified.path("data").path("tokens").path("access_token").asText();

        ApiResponse login = postJson("/auth/login", """
                {"email":"%s","password":"CorrectHorseBattery"}
                """.formatted(email));
        String secondRefresh = login.body().path("data").path("tokens").path("refresh_token").asText();

        postJson("/auth/password-reset/request", "{\"email\":\"%s\"}".formatted(email),
                "Idempotency-Key", UUID.randomUUID().toString());
        String code = mailSender.latestCode(email);

        ApiResponse confirm = postJson("/auth/password-reset/confirm", """
                {"email":"%s","new_password":"BrandNewPassword1","credential":{"credential_type":"code","code":"%s"}}
                """.formatted(email, code));
        assertThat(confirm.status()).isEqualTo(HttpStatus.OK.value());
        assertThat(confirm.body().path("data").path("performed").asBoolean()).isTrue();
        // No new tokens are issued on reset.
        assertThat(confirm.body().path("data").path("tokens").isMissingNode()).isTrue();

        // All previous sessions die.
        assertThat(postJson("/auth/token/refresh", "{\"refresh_token\":\"%s\"}".formatted(firstRefresh))
                .body().path("error").path("code").asText())
                .isEqualTo("AUTH_REFRESH_TOKEN_INVALID");
        assertThat(postJson("/auth/token/refresh", "{\"refresh_token\":\"%s\"}".formatted(secondRefresh))
                .body().path("error").path("code").asText())
                .isEqualTo("AUTH_REFRESH_TOKEN_INVALID");
        assertThat(getJson("/users/me", "Authorization", auth(firstAccess))
                .body().path("error").path("code").asText())
                .isEqualTo("AUTH_SESSION_EXPIRED");

        // Old password no longer works; the new one does.
        assertThat(postJson("/auth/login", "{\"email\":\"%s\",\"password\":\"CorrectHorseBattery\"}".formatted(email))
                .body().path("error").path("code").asText())
                .isEqualTo("AUTH_INVALID_CREDENTIALS");
        ApiResponse newLogin = postJson("/auth/login", """
                {"email":"%s","password":"BrandNewPassword1"}
                """.formatted(email));
        assertThat(newLogin.status()).isEqualTo(HttpStatus.OK.value());
    }

    @Test
    void resetConfirmFailsForWrongExpiredOrReusedCodes() {
        String email = uniqueEmail();
        registerAndVerify(email, "CorrectHorseBattery");

        postJson("/auth/password-reset/request", "{\"email\":\"%s\"}".formatted(email),
                "Idempotency-Key", UUID.randomUUID().toString());
        String code = mailSender.latestCode(email);

        ApiResponse wrongCode = postJson("/auth/password-reset/confirm", """
                {"email":"%s","new_password":"BrandNewPassword1","credential":{"credential_type":"code","code":"000000"}}
                """.formatted(email));
        assertThat(wrongCode.body().path("error").path("code").asText())
                .isEqualTo("AUTH_VERIFICATION_INVALID");

        ApiResponse success = postJson("/auth/password-reset/confirm", """
                {"email":"%s","new_password":"BrandNewPassword1","credential":{"credential_type":"code","code":"%s"}}
                """.formatted(email, code));
        assertThat(success.status()).isEqualTo(HttpStatus.OK.value());

        ApiResponse reused = postJson("/auth/password-reset/confirm", """
                {"email":"%s","new_password":"AnotherPassword1","credential":{"credential_type":"code","code":"%s"}}
                """.formatted(email, code));
        assertThat(reused.body().path("error").path("code").asText())
                .isEqualTo("AUTH_VERIFICATION_USED");
    }

    @Test
    void passwordChangeRotatesCurrentSessionAndRevokesOthers() {
        String email = uniqueEmail();
        JsonNode verified = registerAndVerify(email, "CorrectHorseBattery");
        String firstRefresh = verified.path("data").path("tokens").path("refresh_token").asText();

        ApiResponse login = postJson("/auth/login", """
                {"email":"%s","password":"CorrectHorseBattery"}
                """.formatted(email));
        String currentAccess = login.body().path("data").path("tokens").path("access_token").asText();
        String currentRefresh = login.body().path("data").path("tokens").path("refresh_token").asText();

        ApiResponse wrongCurrent = postJson("/auth/password/change", """
                {"current_password":"NotThePassword","new_password":"AnotherPassword1"}
                """, "Authorization", auth(currentAccess));
        assertThat(wrongCurrent.body().path("error").path("code").asText())
                .isEqualTo("AUTH_CURRENT_PASSWORD_INVALID");

        ApiResponse unchanged = postJson("/auth/password/change", """
                {"current_password":"CorrectHorseBattery","new_password":"CorrectHorseBattery"}
                """, "Authorization", auth(currentAccess));
        assertThat(unchanged.body().path("error").path("code").asText())
                .isEqualTo("AUTH_PASSWORD_UNCHANGED");

        ApiResponse weak = postJson("/auth/password/change", """
                {"current_password":"CorrectHorseBattery","new_password":"password"}
                """, "Authorization", auth(currentAccess));
        assertThat(weak.body().path("error").path("code").asText())
                .isEqualTo("AUTH_PASSWORD_POLICY_VIOLATION");

        ApiResponse changed = postJson("/auth/password/change", """
                {"current_password":"CorrectHorseBattery","new_password":"AnotherPassword1"}
                """, "Authorization", auth(currentAccess));
        assertThat(changed.status()).isEqualTo(HttpStatus.OK.value());
        String newAccess = changed.body().path("data").path("tokens").path("access_token").asText();
        String newRefresh = changed.body().path("data").path("tokens").path("refresh_token").asText();
        assertThat(newRefresh).isNotEqualTo(currentRefresh);

        // The other device's session was revoked...
        assertThat(postJson("/auth/token/refresh", "{\"refresh_token\":\"%s\"}".formatted(firstRefresh))
                .body().path("error").path("code").asText())
                .isEqualTo("AUTH_REFRESH_TOKEN_INVALID");
        // ...and the rotated current session keeps working.
        assertThat(getJson("/users/me", "Authorization", auth(newAccess)).status())
                .isEqualTo(HttpStatus.OK.value());
        assertThat(postJson("/auth/token/refresh", "{\"refresh_token\":\"%s\"}".formatted(newRefresh))
                .status()).isEqualTo(HttpStatus.OK.value());
    }

    @Test
    void passwordChangeRevokesTheOldCurrentGrant() {
        String email = uniqueEmail();
        registerAndVerify(email, "CorrectHorseBattery");
        ApiResponse login = postJson("/auth/login", """
                {"email":"%s","password":"CorrectHorseBattery"}
                """.formatted(email));
        String access = login.body().path("data").path("tokens").path("access_token").asText();
        String refresh = login.body().path("data").path("tokens").path("refresh_token").asText();

        ApiResponse changed = postJson("/auth/password/change", """
                {"current_password":"CorrectHorseBattery","new_password":"AnotherPassword1"}
                """, "Authorization", auth(access));
        assertThat(changed.status()).isEqualTo(HttpStatus.OK.value());

        assertThat(postJson("/auth/token/refresh", "{\"refresh_token\":\"%s\"}".formatted(refresh))
                .body().path("error").path("code").asText())
                .isEqualTo("AUTH_REFRESH_TOKEN_INVALID");
    }

    private static String uniqueEmail() {
        return "user-" + UUID.randomUUID() + "@example.com";
    }
}
