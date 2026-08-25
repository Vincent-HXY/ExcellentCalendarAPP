package com.excellentcalendar.cloud;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.HexFormat;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;

/**
 * Idempotency-key TTL semantics over HTTP: an expired completed record must not be replayed, and a
 * crashed claim (row with null status) must not wedge its key into permanent 500s.
 */
class IdempotencyEdgeIT extends ApiIntegrationTestSupport {

    @BeforeEach
    void clearMail() {
        mailSender.clear();
    }

    private String registerBody(String email, String username) {
        return """
                {"email":"%s","username":"%s","display_name":"Calendar User","password":"CorrectHorseBattery",
                 "locale":"zh-CN","timezone":"Asia/Shanghai",
                 "agreement_version":"terms-v1","agreement_accepted":true}
                """.formatted(email, username);
    }

    private void insertRecord(String scope, String key, Integer status, String body, Instant expiresAt) {
        jdbcTemplate.update("""
                INSERT INTO idempotency_records (id, scope, key_hash, request_digest, response_status,
                                                response_body, created_at, expires_at)
                VALUES (?, ?, ?, NULL, ?, ?::bytea, ?, ?)
                ON CONFLICT (scope, key_hash) DO NOTHING
                """,
                UUID.randomUUID(),
                scope,
                sha256Hex(key),
                status,
                body == null ? null : body.getBytes(StandardCharsets.UTF_8),
                OffsetDateTime.now(ZoneOffset.UTC),
                expiresAt.atOffset(ZoneOffset.UTC));
    }

    @Test
    void crashedClaimDoesNotWedgeTheKeyIntoPermanentFailures() {
        // Simulate a claim whose process died before complete/release, now past its TTL.
        String key = UUID.randomUUID().toString();
        insertRecord("auth.register:anonymous", key, null, null,
                Instant.now().minusSeconds(3600));
        String email = uniqueEmail();

        ApiResponse response = postJson("/auth/register", registerBody(email, uniqueUsername()),
                "Idempotency-Key", key);
        assertThat(response.status()).as("register body: %s", response.body())
                .isEqualTo(HttpStatus.OK.value());
        assertThat(response.body().path("data").path("challenge").path("challenge_id").asText())
                .isNotBlank();
    }

    @Test
    void expiredCompletedRecordIsNotReplayed() {
        String key = UUID.randomUUID().toString();
        // A stale success response from a different logical operation must never be replayed.
        insertRecord("auth.register:anonymous", key, 200,
                """
                        {"ok":true,"data":{"account_id":"00000000-0000-0000-0000-000000000000"},
                         "error":null,"contract_version":1,"request_id":"stale"}
                        """,
                Instant.now().minusSeconds(3600));
        String email = uniqueEmail();

        ApiResponse response = postJson("/auth/register", registerBody(email, uniqueUsername()),
                "Idempotency-Key", key);
        assertThat(response.status()).as("register body: %s", response.body())
                .isEqualTo(HttpStatus.OK.value());
        assertThat(response.body().path("data").path("account_id").asText())
                .isNotEqualTo("00000000-0000-0000-0000-000000000000");
        assertThat(response.body().path("data").path("challenge").path("challenge_id").asText())
                .isNotBlank();
    }

    @Test
    void freshCompletedRecordStillReplays() {
        String key = UUID.randomUUID().toString();
        String email = uniqueEmail();
        ApiResponse first = postJson("/auth/register", registerBody(email, uniqueUsername()),
                "Idempotency-Key", key);
        assertThat(first.status()).isEqualTo(HttpStatus.OK.value());

        ApiResponse second = postJson("/auth/register", registerBody(email, uniqueUsername()),
                "Idempotency-Key", key);
        assertThat(second.status()).isEqualTo(HttpStatus.OK.value());
        assertThat(second.body().path("data").path("account_id").asText())
                .isEqualTo(first.body().path("data").path("account_id").asText());
    }

    private static String sha256Hex(String value) {
        try {
            return HexFormat.of().formatHex(
                    MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception exception) {
            throw new IllegalStateException(exception);
        }
    }

    private static String uniqueEmail() {
        return "user-" + UUID.randomUUID() + "@example.com";
    }

    private static String uniqueUsername() {
        return "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12);
    }
}
