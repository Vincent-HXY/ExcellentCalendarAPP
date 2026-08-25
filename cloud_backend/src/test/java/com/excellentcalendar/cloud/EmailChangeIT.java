package com.excellentcalendar.cloud;

import static org.assertj.core.api.Assertions.assertThat;

import tools.jackson.databind.JsonNode;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

class EmailChangeIT extends ApiIntegrationTestSupport {

    @BeforeEach
    void clearMail() {
        mailSender.clear();
    }

    private JsonNode registerAndVerify(String email) {
        ApiResponse register = postJson("/auth/register", """
                {"email":"%s","username":"%s","display_name":"Calendar User","password":"CorrectHorseBattery",
                 "locale":"zh-CN","timezone":"Asia/Shanghai",
                 "agreement_version":"terms-v1","agreement_accepted":true}
                """.formatted(email, "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12)),
                "Idempotency-Key", UUID.randomUUID().toString());
        assertThat(register.status()).as("register body: %s", register.body())
                .isEqualTo(HttpStatus.OK.value());
        String challengeId = register.body().path("data").path("challenge").path("challenge_id").asText();
        ApiResponse verify = postJson("/auth/registration/verify", """
                {"challenge_id":"%s","credential":{"credential_type":"code","code":"%s"}}
                """.formatted(challengeId, mailSender.latestCode(email)));
        assertThat(verify.status()).isEqualTo(HttpStatus.OK.value());
        return verify.body();
    }

    @Test
    void emailChangeRequestAndConfirmSwapTheLoginEmailAndRotateSessions() {
        String oldEmail = uniqueEmail();
        String newEmail = uniqueEmail();
        JsonNode verified = registerAndVerify(oldEmail);
        String firstRefresh = verified.path("data").path("tokens").path("refresh_token").asText();

        ApiResponse login = postJson("/auth/login", """
                {"email":"%s","password":"CorrectHorseBattery"}
                """.formatted(oldEmail));
        String access = login.body().path("data").path("tokens").path("access_token").asText();
        String currentRefresh = login.body().path("data").path("tokens").path("refresh_token").asText();

        // Wrong current password is rejected.
        ApiResponse wrongPassword = postJson("/auth/email-change/request", """
                {"new_email":"%s","current_password":"NotThePassword"}
                """.formatted(newEmail), "Authorization", auth(access),
                "Idempotency-Key", UUID.randomUUID().toString());
        assertThat(wrongPassword.body().path("error").path("code").asText())
                .isEqualTo("AUTH_CURRENT_PASSWORD_INVALID");

        ApiResponse requested = postJson("/auth/email-change/request", """
                {"new_email":"%s","current_password":"CorrectHorseBattery"}
                """.formatted(newEmail), "Authorization", auth(access),
                "Idempotency-Key", UUID.randomUUID().toString());
        assertThat(requested.status()).isEqualTo(HttpStatus.OK.value());
        JsonNode challenge = requested.body().path("data");
        assertThat(challenge.path("purpose").asText()).isEqualTo("email_change");
        assertThat(challenge.path("action_id").asText()).isNotBlank();
        assertThat(challenge.path("masked_email").asText()).isEqualTo(mask(newEmail));
        String requestId = challenge.path("action_id").asText();
        String code = mailSender.latestCode(newEmail);

        // While pending, the original email remains the only valid login email.
        assertThat(postJson("/auth/login", "{\"email\":\"%s\",\"password\":\"CorrectHorseBattery\"}".formatted(oldEmail))
                .status()).isEqualTo(HttpStatus.OK.value());
        assertThat(postJson("/auth/login", "{\"email\":\"%s\",\"password\":\"CorrectHorseBattery\"}".formatted(newEmail))
                .body().path("error").path("code").asText())
                .isEqualTo("AUTH_INVALID_CREDENTIALS");

        // Wrong code is rejected without consuming the challenge.
        ApiResponse wrongCode = postJson("/auth/email-change/confirm", """
                {"email_change_request_id":"%s","credential":{"credential_type":"code","code":"000000"}}
                """.formatted(requestId), "Authorization", auth(access));
        assertThat(wrongCode.body().path("error").path("code").asText())
                .isEqualTo("AUTH_VERIFICATION_INVALID");

        ApiResponse confirmed = postJson("/auth/email-change/confirm", """
                {"email_change_request_id":"%s","credential":{"credential_type":"code","code":"%s"}}
                """.formatted(requestId, code), "Authorization", auth(access));
        assertThat(confirmed.status()).isEqualTo(HttpStatus.OK.value());
        assertThat(confirmed.body().path("data").path("current_user").path("account").path("email").asText())
                .isEqualTo(newEmail);
        String newAccess = confirmed.body().path("data").path("tokens").path("access_token").asText();
        String newRefresh = confirmed.body().path("data").path("tokens").path("refresh_token").asText();
        assertThat(newRefresh).isNotEqualTo(currentRefresh);

        // The swap took effect and the other device was revoked.
        assertThat(postJson("/auth/login", "{\"email\":\"%s\",\"password\":\"CorrectHorseBattery\"}".formatted(newEmail))
                .status()).isEqualTo(HttpStatus.OK.value());
        assertThat(postJson("/auth/token/refresh", "{\"refresh_token\":\"%s\"}".formatted(firstRefresh))
                .body().path("error").path("code").asText())
                .isEqualTo("AUTH_REFRESH_TOKEN_INVALID");
        assertThat(getJson("/users/me", "Authorization", auth(newAccess)).status())
                .isEqualTo(HttpStatus.OK.value());
    }

    @Test
    void requestingForAnAlreadyTakenEmailIsRejected() {
        String email = uniqueEmail();
        String taken = uniqueEmail();
        registerAndVerify(email);
        registerAndVerify(taken);
        ApiResponse login = postJson("/auth/login", """
                {"email":"%s","password":"CorrectHorseBattery"}
                """.formatted(email));
        String access = login.body().path("data").path("tokens").path("access_token").asText();

        ApiResponse response = postJson("/auth/email-change/request", """
                {"new_email":"%s","current_password":"CorrectHorseBattery"}
                """.formatted(taken), "Authorization", auth(access),
                "Idempotency-Key", UUID.randomUUID().toString());
        assertThat(response.body().path("error").path("code").asText())
                .isEqualTo("AUTH_EMAIL_ALREADY_EXISTS");
    }

    @Test
    void requestingTheCurrentEmailIsAValidationErrorNotAlreadyExists() {
        String email = uniqueEmail();
        registerAndVerify(email);
        ApiResponse login = postJson("/auth/login", """
                {"email":"%s","password":"CorrectHorseBattery"}
                """.formatted(email));
        String access = login.body().path("data").path("tokens").path("access_token").asText();

        ApiResponse response = postJson("/auth/email-change/request", """
                {"new_email":"%s","current_password":"CorrectHorseBattery"}
                """.formatted(email), "Authorization", auth(access),
                "Idempotency-Key", UUID.randomUUID().toString());
        assertThat(response.status()).isEqualTo(HttpStatus.BAD_REQUEST.value());
        assertThat(response.body().path("error").path("code").asText())
                .isEqualTo("API_VALIDATION_FAILED");
        assertThat(response.body().path("error").path("field_errors").get(0).path("field").asText())
                .isEqualTo("new_email");
    }

    @Test
    void inboxTakenAtConfirmTimeDoesNotBurnTheCode() {
        String email = uniqueEmail();
        String newEmail = uniqueEmail();
        registerAndVerify(email);
        ApiResponse login = postJson("/auth/login", """
                {"email":"%s","password":"CorrectHorseBattery"}
                """.formatted(email));
        String access = login.body().path("data").path("tokens").path("access_token").asText();

        ApiResponse requested = postJson("/auth/email-change/request", """
                {"new_email":"%s","current_password":"CorrectHorseBattery"}
                """.formatted(newEmail), "Authorization", auth(access),
                "Idempotency-Key", UUID.randomUUID().toString());
        String requestId = requested.body().path("data").path("action_id").asText();
        String challengeId = requested.body().path("data").path("challenge_id").asText();
        String code = mailSender.latestCode(newEmail);

        // Someone registers the new inbox while the challenge is pending.
        registerAndVerify(newEmail);

        ApiResponse taken = postJson("/auth/email-change/confirm", """
                {"email_change_request_id":"%s","credential":{"credential_type":"code","code":"%s"}}
                """.formatted(requestId, code), "Authorization", auth(access));
        assertThat(taken.body().path("error").path("code").asText())
                .isEqualTo("AUTH_EMAIL_ALREADY_EXISTS");

        // The one-time code was NOT consumed by the failed confirm (noRollbackFor would have
        // persisted a burn if the check ran after verifyCode).
        java.sql.Timestamp consumedAt = jdbcTemplate.queryForObject("""
                SELECT consumed_at FROM email_action_challenges WHERE id = ?
                """, java.sql.Timestamp.class, UUID.fromString(challengeId));
        assertThat(consumedAt).isNull();
    }

    @Test
    void newRequestSupersedesThePendingOne() {
        String email = uniqueEmail();
        String firstNew = uniqueEmail();
        String secondNew = uniqueEmail();
        registerAndVerify(email);
        ApiResponse login = postJson("/auth/login", """
                {"email":"%s","password":"CorrectHorseBattery"}
                """.formatted(email));
        String access = login.body().path("data").path("tokens").path("access_token").asText();

        ApiResponse first = postJson("/auth/email-change/request", """
                {"new_email":"%s","current_password":"CorrectHorseBattery"}
                """.formatted(firstNew), "Authorization", auth(access),
                "Idempotency-Key", UUID.randomUUID().toString());
        String firstRequestId = first.body().path("data").path("action_id").asText();
        String firstCode = mailSender.latestCode(firstNew);
        mailSender.clear();

        ApiResponse second = postJson("/auth/email-change/request", """
                {"new_email":"%s","current_password":"CorrectHorseBattery"}
                """.formatted(secondNew), "Authorization", auth(access),
                "Idempotency-Key", UUID.randomUUID().toString());
        assertThat(second.status()).isEqualTo(HttpStatus.OK.value());
        String secondRequestId = second.body().path("data").path("action_id").asText();
        String secondCode = mailSender.latestCode(secondNew);

        // The superseded challenge is dead: its request is cancelled, so the code is invalid.
        ApiResponse superseded = postJson("/auth/email-change/confirm", """
                {"email_change_request_id":"%s","credential":{"credential_type":"code","code":"%s"}}
                """.formatted(firstRequestId, firstCode), "Authorization", auth(access));
        assertThat(superseded.body().path("error").path("code").asText())
                .isEqualTo("AUTH_VERIFICATION_INVALID");

        ApiResponse confirmed = postJson("/auth/email-change/confirm", """
                {"email_change_request_id":"%s","credential":{"credential_type":"code","code":"%s"}}
                """.formatted(secondRequestId, secondCode), "Authorization", auth(access));
        assertThat(confirmed.status()).isEqualTo(HttpStatus.OK.value());
        assertThat(confirmed.body().path("data").path("current_user").path("account").path("email").asText())
                .isEqualTo(secondNew);
    }

    private static String uniqueEmail() {
        return "user-" + UUID.randomUUID() + "@example.com";
    }

    private static String mask(String email) {
        String local = email.substring(0, email.indexOf('@'));
        return local.charAt(0) + "***" + local.charAt(local.length() - 1) + email.substring(email.indexOf('@'));
    }
}
