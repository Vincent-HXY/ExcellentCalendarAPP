package com.excellentcalendar.cloud;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import tools.jackson.databind.JsonNode;

/**
 * End-to-end registration/verification/login/session flows over HTTP against a real PostgreSQL.
 */
class AuthFlowIT extends ApiIntegrationTestSupport {

    @BeforeEach
    void clearMail() {
        mailSender.clear();
    }

    private String register(String email, String username, String password) {
        ApiResponse response = postJson("/auth/register", """
                {"email":"%s","username":"%s","display_name":"Calendar User","password":"%s",
                 "locale":"zh-CN","timezone":"Asia/Shanghai",
                 "agreement_version":"terms-v1","agreement_accepted":true}
                """.formatted(email, username, password),
                "Idempotency-Key", UUID.randomUUID().toString());
        assertThat(response.status()).as("register body: %s", response.body())
                .isEqualTo(HttpStatus.OK.value());
        JsonNode envelope = response.body();
        assertThat(envelope.path("ok").asBoolean()).isTrue();
        assertThat(envelope.path("data").path("account_id").asText()).isNotBlank();
        assertThat(envelope.path("data").path("challenge").path("challenge_id").asText()).isNotBlank();
        assertThat(envelope.path("data").path("challenge").path("masked_email").asText())
                .isEqualTo(mask(email));
        return envelope.path("data").path("challenge").path("challenge_id").asText();
    }

    private String verify(String challengeId, String code) {
        ApiResponse response = postJson("/auth/registration/verify", """
                {"challenge_id":"%s","credential":{"credential_type":"code","code":"%s"}}
                """.formatted(challengeId, code));
        assertThat(response.status()).isEqualTo(HttpStatus.OK.value());
        return response.body().path("data").path("tokens").path("refresh_token").asText();
    }

    @Test
    void registerVerifyLoginRefreshReplayLogoutFlow() {
        String email = uniqueEmail();
        String challengeId = register(email, "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12), "CorrectHorseBattery");
        String code = mailSender.latestCode(email);
        assertThat(mailSender.last().purpose()).isEqualTo("registration_verification");

        String refreshToken = verify(challengeId, code);
        assertThat(refreshToken).hasSize(43);

        // Login issues a second, independent session.
        ApiResponse login = postJson("/auth/login", """
                {"email":"%s","password":"CorrectHorseBattery"}
                """.formatted(email));
        assertThat(login.status()).isEqualTo(HttpStatus.OK.value());
        String loginRefreshToken = login.body().path("data").path("tokens").path("refresh_token").asText();
        assertThat(loginRefreshToken).isNotEqualTo(refreshToken);

        // Refresh rotates atomically.
        ApiResponse refreshed = postJson("/auth/token/refresh", """
                {"refresh_token":"%s"}
                """.formatted(refreshToken));
        assertThat(refreshed.status()).isEqualTo(HttpStatus.OK.value());
        String rotatedToken = refreshed.body().path("data").path("refresh_token").asText();
        assertThat(rotatedToken).isNotEqualTo(refreshToken);

        // Replaying the consumed token revokes the family.
        ApiResponse replay = postJson("/auth/token/refresh", """
                {"refresh_token":"%s"}
                """.formatted(refreshToken));
        assertThat(replay.status()).isEqualTo(HttpStatus.UNAUTHORIZED.value());
        assertThat(replay.body().path("error").path("code").asText())
                .isEqualTo("AUTH_REFRESH_TOKEN_REUSED");

        // Family is revoked: the rotated token no longer works either.
        ApiResponse afterReplay = postJson("/auth/token/refresh", """
                {"refresh_token":"%s"}
                """.formatted(rotatedToken));
        assertThat(afterReplay.body().path("error").path("code").asText())
                .isEqualTo("AUTH_REFRESH_TOKEN_INVALID");

        // Logout is naturally idempotent and never errors for invalid tokens.
        ApiResponse logout = postJson("/auth/logout", """
                {"refresh_token":"%s"}
                """.formatted(loginRefreshToken));
        assertThat(logout.status()).isEqualTo(HttpStatus.OK.value());
        assertThat(logout.body().path("data").path("performed").asBoolean()).isTrue();

        // The revoked token is dead and the second logout performs nothing.
        assertThat(postJson("/auth/token/refresh", """
                {"refresh_token":"%s"}
                """.formatted(loginRefreshToken)).body().path("error").path("code").asText())
                .isEqualTo("AUTH_REFRESH_TOKEN_INVALID");
        ApiResponse logoutAgain = postJson("/auth/logout", """
                {"refresh_token":"%s"}
                """.formatted(loginRefreshToken));
        assertThat(logoutAgain.status()).isEqualTo(HttpStatus.OK.value());
        assertThat(logoutAgain.body().path("data").path("performed").asBoolean()).isFalse();
    }

    @Test
    void duplicateEmailAndUsernameAreRejectedWithDeclaredCodes() {
        String email = uniqueEmail();
        String username = "dup_" + UUID.randomUUID().toString().replace("-", "").substring(0, 10);
        register(email, username, "CorrectHorseBattery");

        ApiResponse duplicateEmail = postJson("/auth/register", """
                {"email":"%s","username":"%s","display_name":"Other","password":"CorrectHorseBattery",
                 "locale":"zh-CN","timezone":"Asia/Shanghai",
                 "agreement_version":"terms-v1","agreement_accepted":true}
                """.formatted(email, "other_" + UUID.randomUUID().toString().replace("-", "").substring(0, 10)),
                "Idempotency-Key", UUID.randomUUID().toString());
        assertThat(duplicateEmail.status()).isEqualTo(HttpStatus.CONFLICT.value());
        assertThat(duplicateEmail.body().path("error").path("code").asText())
                .isEqualTo("AUTH_EMAIL_ALREADY_EXISTS");

        ApiResponse duplicateUsername = postJson("/auth/register", """
                {"email":"%s","username":"%s","display_name":"Other","password":"CorrectHorseBattery",
                 "locale":"zh-CN","timezone":"Asia/Shanghai",
                 "agreement_version":"terms-v1","agreement_accepted":true}
                """.formatted(uniqueEmail(), username),
                "Idempotency-Key", UUID.randomUUID().toString());
        assertThat(duplicateUsername.status()).isEqualTo(HttpStatus.CONFLICT.value());
        assertThat(duplicateUsername.body().path("error").path("code").asText())
                .isEqualTo("AUTH_USERNAME_ALREADY_EXISTS");
    }

    @Test
    void weakPasswordIsRejectedWithPolicyViolation() {
        ApiResponse response = postJson("/auth/register", """
                {"email":"%s","username":"%s","display_name":"Calendar User","password":"password",
                 "locale":"zh-CN","timezone":"Asia/Shanghai",
                 "agreement_version":"terms-v1","agreement_accepted":true}
                """.formatted(uniqueEmail(), "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12)),
                "Idempotency-Key", UUID.randomUUID().toString());
        assertThat(response.status()).isEqualTo(HttpStatus.BAD_REQUEST.value());
        assertThat(response.body().path("error").path("code").asText())
                .isEqualTo("AUTH_PASSWORD_POLICY_VIOLATION");
    }

    @Test
    void registerRequiresIdempotencyKey() {
        ApiResponse response = postJson("/auth/register", """
                {"email":"%s","username":"%s","display_name":"Calendar User","password":"CorrectHorseBattery",
                 "locale":"zh-CN","timezone":"Asia/Shanghai",
                 "agreement_version":"terms-v1","agreement_accepted":true}
                """.formatted(uniqueEmail(), "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12)));
        assertThat(response.status()).isEqualTo(HttpStatus.BAD_REQUEST.value());
        assertThat(response.body().path("error").path("code").asText())
                .isEqualTo("API_VALIDATION_FAILED");
    }

    @Test
    void registerReplayWithSameIdempotencyKeyReturnsIdenticalResult() {
        String email = uniqueEmail();
        String key = UUID.randomUUID().toString();
        String body = """
                {"email":"%s","username":"%s","display_name":"Calendar User","password":"CorrectHorseBattery",
                 "locale":"zh-CN","timezone":"Asia/Shanghai",
                 "agreement_version":"terms-v1","agreement_accepted":true}
                """.formatted(email, "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12));

        ApiResponse first = postJson("/auth/register", body, "Idempotency-Key", key);
        ApiResponse second = postJson("/auth/register", body, "Idempotency-Key", key);
        assertThat(first.status()).isEqualTo(HttpStatus.OK.value());
        assertThat(second.status()).isEqualTo(HttpStatus.OK.value());
        assertThat(second.body().path("data").path("account_id").asText())
                .isEqualTo(first.body().path("data").path("account_id").asText());
        assertThat(second.body().path("data").path("challenge").path("challenge_id").asText())
                .isEqualTo(first.body().path("data").path("challenge").path("challenge_id").asText());
        // Byte-level replay: the stored response (including its original request_id) is returned
        // verbatim.
        assertThat(second.body().toString()).isEqualTo(first.body().toString());
    }

    @Test
    void sameIdempotencyKeyWithADifferentPayloadReplaysTheStoredResponse() {
        // The key identifies the logical operation: a different payload under the same key does
        // not execute a second operation, the stored response wins (documented semantics).
        String email = uniqueEmail();
        String key = UUID.randomUUID().toString();
        String firstBody = """
                {"email":"%s","username":"%s","display_name":"Calendar User","password":"CorrectHorseBattery",
                 "locale":"zh-CN","timezone":"Asia/Shanghai",
                 "agreement_version":"terms-v1","agreement_accepted":true}
                """.formatted(email, "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12));
        String differentBody = """
                {"email":"%s","username":"%s","display_name":"Different Name","password":"CorrectHorseBattery",
                 "locale":"zh-CN","timezone":"Asia/Shanghai",
                 "agreement_version":"terms-v1","agreement_accepted":true}
                """.formatted(uniqueEmail(), "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12));

        ApiResponse first = postJson("/auth/register", firstBody, "Idempotency-Key", key);
        ApiResponse second = postJson("/auth/register", differentBody, "Idempotency-Key", key);

        assertThat(first.status()).isEqualTo(HttpStatus.OK.value());
        assertThat(second.status()).isEqualTo(HttpStatus.OK.value());
        assertThat(second.body().toString()).isEqualTo(first.body().toString());
    }

    @Test
    void resendWithinIntervalIsRateLimited() {
        String email = uniqueEmail();
        String challengeId = register(email, "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12), "CorrectHorseBattery");
        ApiResponse response = postJson("/auth/registration/resend", """
                {"challenge_id":"%s"}
                """.formatted(challengeId),
                "Idempotency-Key", UUID.randomUUID().toString());
        assertThat(response.status()).isEqualTo(HttpStatus.TOO_MANY_REQUESTS.value());
        assertThat(response.body().path("error").path("code").asText()).isEqualTo("API_RATE_LIMITED");
        assertThat(response.body().path("error").path("retry_after_seconds").asInt()).isPositive();
    }

    @Test
    void resendAfterTheIntervalIssuesAFreshChallengeAndCode() {
        String email = uniqueEmail();
        String challengeId = register(email, "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12), "CorrectHorseBattery");
        String firstCode = mailSender.latestCode(email);
        // The resend interval is enforced by the clock; backdate the stored window so the
        // positive path is testable without waiting or fake clocks.
        jdbcTemplate.update("""
                UPDATE email_action_challenges SET resend_available_at = now() - interval '1 second'
                WHERE id = ?
                """, UUID.fromString(challengeId));

        ApiResponse response = postJson("/auth/registration/resend", """
                {"challenge_id":"%s"}
                """.formatted(challengeId),
                "Idempotency-Key", UUID.randomUUID().toString());
        assertThat(response.status()).as("resend body: %s", response.body())
                .isEqualTo(HttpStatus.OK.value());
        String newChallengeId = response.body().path("data").path("challenge_id").asText();
        assertThat(newChallengeId).isNotBlank().isNotEqualTo(challengeId);
        String newCode = mailSender.latestCode(email);
        assertThat(newCode).isNotEqualTo(firstCode);

        // The old challenge is dead, the fresh code verifies.
        ApiResponse oldChallenge = postJson("/auth/registration/verify", """
                {"challenge_id":"%s","credential":{"credential_type":"code","code":"%s"}}
                """.formatted(challengeId, firstCode));
        assertThat(oldChallenge.body().path("error").path("code").asText())
                .isEqualTo("AUTH_VERIFICATION_INVALID");
        ApiResponse verified = postJson("/auth/registration/verify", """
                {"challenge_id":"%s","credential":{"credential_type":"code","code":"%s"}}
                """.formatted(newChallengeId, newCode));
        assertThat(verified.status()).isEqualTo(HttpStatus.OK.value());
    }

    @Test
    void resendOfExpiredChallengeIssuesFreshChallengeAndCode() {
        String email = uniqueEmail();
        String challengeId = register(email,
                "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12),
                "CorrectHorseBattery");
        String firstCode = mailSender.latestCode(email);
        jdbcTemplate.update("""
                UPDATE email_action_challenges
                SET expires_at = now() - interval '1 second',
                    resend_available_at = now() - interval '1 second'
                WHERE id = ?
                """, UUID.fromString(challengeId));

        ApiResponse response = postJson("/auth/registration/resend", """
                {"challenge_id":"%s"}
                """.formatted(challengeId),
                "Idempotency-Key", UUID.randomUUID().toString());

        assertThat(response.status()).as("resend body: %s", response.body())
                .isEqualTo(HttpStatus.OK.value());
        String newChallengeId = response.body().path("data").path("challenge_id").asText();
        assertThat(newChallengeId).isNotBlank().isNotEqualTo(challengeId);
        assertThat(mailSender.latestCode(email)).isNotEqualTo(firstCode);
    }

    @Test
    void expiredChallengeIsRejectedAsExpired() {
        String email = uniqueEmail();
        String challengeId = register(email, "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12), "CorrectHorseBattery");
        jdbcTemplate.update("""
                UPDATE email_action_challenges SET expires_at = now() - interval '1 second'
                WHERE id = ?
                """, UUID.fromString(challengeId));

        ApiResponse response = postJson("/auth/registration/verify", """
                {"challenge_id":"%s","credential":{"credential_type":"code","code":"%s"}}
                """.formatted(challengeId, mailSender.latestCode(email)));
        assertThat(response.body().path("error").path("code").asText())
                .isEqualTo("AUTH_VERIFICATION_EXPIRED");
    }

    @Test
    void wrongCodeExhaustsAttemptsAndInvalidatesTheChallenge() {
        String email = uniqueEmail();
        String challengeId = register(email, "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12), "CorrectHorseBattery");
        for (int attempt = 0; attempt < 5; attempt++) {
            ApiResponse response = postJson("/auth/registration/verify", """
                    {"challenge_id":"%s","credential":{"credential_type":"code","code":"000000"}}
                    """.formatted(challengeId));
            assertThat(response.body().path("error").path("code").asText())
                    .isEqualTo("AUTH_VERIFICATION_INVALID");
        }
        // Exceeding max attempts invalidated the challenge: even the correct code now fails.
        String correctCode = mailSender.latestCode(email);
        ApiResponse afterExhaustion = postJson("/auth/registration/verify", """
                {"challenge_id":"%s","credential":{"credential_type":"code","code":"%s"}}
                """.formatted(challengeId, correctCode));
        assertThat(afterExhaustion.body().path("error").path("code").asText())
                .isEqualTo("AUTH_VERIFICATION_INVALID");
    }

    @Test
    void verifyIsOneTime() {
        String email = uniqueEmail();
        String challengeId = register(email, "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12), "CorrectHorseBattery");
        verify(challengeId, mailSender.latestCode(email));

        ApiResponse second = postJson("/auth/registration/verify", """
                {"challenge_id":"%s","credential":{"credential_type":"code","code":"%s"}}
                """.formatted(challengeId, mailSender.latestCode(email)));
        assertThat(second.body().path("error").path("code").asText()).isEqualTo("AUTH_VERIFICATION_USED");
    }

    @Test
    void loginErrorsDoNotLeakAccountExistence() {
        String email = uniqueEmail();
        register(email, "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12), "CorrectHorseBattery");
        mailSender.clear();

        ApiResponse unknown = postJson("/auth/login", """
                {"email":"%s","password":"whatever12345"}
                """.formatted(uniqueEmail()));
        ApiResponse wrongPassword = postJson("/auth/login", """
                {"email":"%s","password":"WrongPassword123"}
                """.formatted(email));
        assertThat(unknown.status()).isEqualTo(HttpStatus.UNAUTHORIZED.value());
        assertThat(wrongPassword.status()).isEqualTo(HttpStatus.UNAUTHORIZED.value());
        assertThat(unknown.body().path("error").path("code").asText())
                .isEqualTo("AUTH_INVALID_CREDENTIALS");
        assertThat(wrongPassword.body().path("error").path("code").asText())
                .isEqualTo("AUTH_INVALID_CREDENTIALS");
        assertThat(mailSender.hasMailFor(email)).isFalse();
    }

    @Test
    void loginOnUnverifiedAccountCarriesVerificationChallengeContext() {
        String email = uniqueEmail();
        String registerChallengeId =
                register(email, "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12), "CorrectHorseBattery");
        mailSender.clear();

        ApiResponse login = postJson("/auth/login", """
                {"email":"%s","password":"CorrectHorseBattery"}
                """.formatted(email));
        assertThat(login.status()).isEqualTo(HttpStatus.FORBIDDEN.value());
        JsonNode error = login.body().path("error");
        assertThat(error.path("code").asText()).isEqualTo("AUTH_EMAIL_UNVERIFIED");
        JsonNode challenge = error.path("context").path("verification_challenge");
        assertThat(challenge.path("challenge_id").asText()).isNotBlank();
        assertThat(challenge.path("purpose").asText()).isEqualTo("registration_verification");
        assertThat(challenge.path("masked_email").asText()).isEqualTo(mask(email));
        assertThat(challenge.path("credential_types").get(0).asText()).isEqualTo("code");
        assertThat(challenge.path("expires_at").asText()).endsWith("Z");
        assertThat(challenge.path("resend_available_at").asText()).endsWith("Z");
        // The existing active registration challenge is reused; no duplicate mail is sent.
        assertThat(challenge.path("challenge_id").asText()).isEqualTo(registerChallengeId);
        assertThat(mailSender.hasMailFor(email)).isFalse();
    }

    @Test
    void loginOnUnverifiedAccountReplacesExpiredChallenge() {
        String email = uniqueEmail();
        String registerChallengeId =
                register(email, "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12), "CorrectHorseBattery");
        jdbcTemplate.update("""
                UPDATE email_action_challenges SET expires_at = now() - interval '1 second'
                WHERE id = ?
                """, UUID.fromString(registerChallengeId));
        mailSender.clear();

        ApiResponse login = postJson("/auth/login", """
                {"email":"%s","password":"CorrectHorseBattery"}
                """.formatted(email));

        assertThat(login.status()).isEqualTo(HttpStatus.FORBIDDEN.value());
        JsonNode challenge = login.body().path("error").path("context").path("verification_challenge");
        assertThat(challenge.path("challenge_id").asText())
                .isNotBlank()
                .isNotEqualTo(registerChallengeId);
        assertThat(mailSender.hasMailFor(email)).isTrue();
    }

    @Test
    void concurrentRefreshOfTheSameTokenHasExactlyOneWinner() throws Exception {
        String email = uniqueEmail();
        String challengeId = register(email, "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12), "CorrectHorseBattery");
        String refreshToken = verify(challengeId, mailSender.latestCode(email));

        ExecutorService executor = Executors.newFixedThreadPool(2);
        CountDownLatch start = new CountDownLatch(1);
        try {
            Future<ApiResponse> first = executor.submit(() -> {
                start.await();
                return postJson("/auth/token/refresh", "{\"refresh_token\":\"%s\"}".formatted(refreshToken));
            });
            Future<ApiResponse> second = executor.submit(() -> {
                start.await();
                return postJson("/auth/token/refresh", "{\"refresh_token\":\"%s\"}".formatted(refreshToken));
            });
            start.countDown();

            List<ApiResponse> results = List.of(
                    first.get(30, TimeUnit.SECONDS), second.get(30, TimeUnit.SECONDS));
            long winners = results.stream().filter(response -> response.status() == HttpStatus.OK.value()).count();
            long reused = results.stream()
                    .filter(response -> response.body() != null
                            && "AUTH_REFRESH_TOKEN_REUSED"
                                    .equals(response.body().path("error").path("code").asText()))
                    .count();
            assertThat(winners).isEqualTo(1);
            assertThat(reused).isEqualTo(1);
        } finally {
            executor.shutdownNow();
        }
    }

    @Test
    void logoutAllRevokesEverySessionOfTheAccount() {
        String email = uniqueEmail();
        String challengeId = register(email, "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12), "CorrectHorseBattery");
        String firstSessionToken = verify(challengeId, mailSender.latestCode(email));

        ApiResponse login = postJson("/auth/login", """
                {"email":"%s","password":"CorrectHorseBattery"}
                """.formatted(email));
        String secondSessionToken = login.body().path("data").path("tokens").path("refresh_token").asText();
        String secondAccessToken = login.body().path("data").path("tokens").path("access_token").asText();

        ApiResponse logoutAll = postJson("/auth/logout-all", "{}", "Authorization", auth(secondAccessToken));
        assertThat(logoutAll.status()).as("logoutAll body: %s", logoutAll.body())
                .isEqualTo(HttpStatus.OK.value());
        assertThat(logoutAll.body().path("data").path("performed").asBoolean()).isTrue();

        ApiResponse firstAfter = postJson("/auth/token/refresh", """
                {"refresh_token":"%s"}
                """.formatted(firstSessionToken));
        ApiResponse secondAfter = postJson("/auth/token/refresh", """
                {"refresh_token":"%s"}
                """.formatted(secondSessionToken));
        assertThat(firstAfter.body().path("error").path("code").asText())
                .isEqualTo("AUTH_REFRESH_TOKEN_INVALID");
        assertThat(secondAfter.body().path("error").path("code").asText())
                .isEqualTo("AUTH_REFRESH_TOKEN_INVALID");
    }

    @Test
    void getCurrentReturnsTheAggregateWithoutSensitiveFields() {
        String email = uniqueEmail();
        String username = "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12);
        String challengeId = register(email, username, "CorrectHorseBattery");
        verify(challengeId, mailSender.latestCode(email));

        ApiResponse login = postJson("/auth/login", """
                {"email":"%s","password":"CorrectHorseBattery"}
                """.formatted(email));
        String accessToken = login.body().path("data").path("tokens").path("access_token").asText();

        ApiResponse me = getJson("/users/me", "Authorization", auth(accessToken));
        assertThat(me.status()).as("me body: %s", me.body()).isEqualTo(HttpStatus.OK.value());
        JsonNode data = me.body().path("data");
        assertThat(data.path("account").path("email").asText()).isEqualTo(email);
        assertThat(data.path("account").path("status").asText()).isEqualTo("active");
        assertThat(data.path("account").path("email_verified_at").asText()).endsWith("Z");
        assertThat(data.path("profile").path("username").asText()).isEqualTo(username);
        assertThat(data.path("profile").path("avatar").isNull()).isTrue();
        assertThat(data.path("preferences").path("locale").asText()).isEqualTo("zh-CN");
        assertThat(data.path("preferences").path("timezone").asText()).isEqualTo("Asia/Shanghai");
        assertThat(me.body().toString()).doesNotContain("password", "refresh_token", "token_hash", "storage_key");

        // Bearer endpoints reject missing/invalid tokens with the declared envelope.
        ApiResponse unauthenticated = getJson("/users/me");
        assertThat(unauthenticated.status()).isEqualTo(HttpStatus.UNAUTHORIZED.value());
        assertThat(unauthenticated.body().path("error").path("code").asText())
                .isEqualTo("API_UNAUTHENTICATED");
    }

    private static String uniqueEmail() {
        return "user-" + UUID.randomUUID() + "@example.com";
    }

    private static String mask(String email) {
        String local = email.substring(0, email.indexOf('@'));
        return local.charAt(0) + "***" + local.charAt(local.length() - 1) + email.substring(email.indexOf('@'));
    }
}
