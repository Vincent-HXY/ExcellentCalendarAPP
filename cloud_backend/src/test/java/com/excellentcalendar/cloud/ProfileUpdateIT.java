package com.excellentcalendar.cloud;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import tools.jackson.databind.JsonNode;

class ProfileUpdateIT extends ApiIntegrationTestSupport {

    @BeforeEach
    void clearMail() {
        mailSender.clear();
    }

    private String registerVerifyAndLogin(String email, String username) {
        ApiResponse register = postJson("/auth/register", """
                {"email":"%s","username":"%s","display_name":"Calendar User","password":"CorrectHorseBattery",
                 "locale":"zh-CN","timezone":"Asia/Shanghai",
                 "agreement_version":"terms-v1","agreement_accepted":true}
                """.formatted(email, username), "Idempotency-Key", UUID.randomUUID().toString());
        String challengeId = register.body().path("data").path("challenge").path("challenge_id").asText();
        postJson("/auth/registration/verify", """
                {"challenge_id":"%s","credential":{"credential_type":"code","code":"%s"}}
                """.formatted(challengeId, mailSender.latestCode(email)));
        ApiResponse login = postJson("/auth/login", """
                {"email":"%s","password":"CorrectHorseBattery"}
                """.formatted(email));
        return login.body().path("data").path("tokens").path("access_token").asText();
    }

    @Test
    void patchUpdatesOnlyProvidedFields() {
        String email = uniqueEmail();
        String access = registerVerifyAndLogin(email, "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12));

        ApiResponse response = patchJson("/users/me", """
                {"display_name":"\u65b0\u6635\u79f0","timezone":"Asia/Tokyo"}
                """, "Authorization", auth(access));
        assertThat(response.status()).isEqualTo(HttpStatus.OK.value());
        JsonNode data = response.body().path("data");
        assertThat(data.path("profile").path("display_name").asText()).isEqualTo("\u65b0\u6635\u79f0");
        assertThat(data.path("preferences").path("timezone").asText()).isEqualTo("Asia/Tokyo");
        assertThat(data.path("preferences").path("locale").asText()).isEqualTo("zh-CN");

        ApiResponse me = getJson("/users/me", "Authorization", auth(access));
        assertThat(me.body().path("data").path("profile").path("display_name").asText())
                .isEqualTo("\u65b0\u6635\u79f0");
    }

    @Test
    void usernameConflictIsRejected() {
        String firstEmail = uniqueEmail();
        String secondEmail = uniqueEmail();
        String taken = "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12);
        registerVerifyAndLogin(firstEmail, taken);
        String access = registerVerifyAndLogin(secondEmail, "other_" + UUID.randomUUID().toString().replace("-", "").substring(0, 10));

        ApiResponse response = patchJson("/users/me", """
                {"username":"%s"}
                """.formatted(taken), "Authorization", auth(access));
        assertThat(response.status()).isEqualTo(HttpStatus.CONFLICT.value());
        assertThat(response.body().path("error").path("code").asText())
                .isEqualTo("AUTH_USERNAME_ALREADY_EXISTS");
    }

    @Test
    void invalidTimezoneAndSettingsAreRejectedAsProfileInvalid() {
        String email = uniqueEmail();
        String access = registerVerifyAndLogin(email, "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12));

        ApiResponse badTimezone = patchJson("/users/me", """
                {"timezone":"Not/AZone"}
                """, "Authorization", auth(access));
        assertThat(badTimezone.status()).isEqualTo(HttpStatus.BAD_REQUEST.value());
        assertThat(badTimezone.body().path("error").path("code").asText())
                .isEqualTo("USER_PROFILE_INVALID");

        ApiResponse badSettings = patchJson("/users/me", """
                {"settings":{"password":"leak"}}
                """, "Authorization", auth(access));
        assertThat(badSettings.status()).isEqualTo(HttpStatus.BAD_REQUEST.value());
        assertThat(badSettings.body().path("error").path("code").asText())
                .isEqualTo("USER_PROFILE_INVALID");
    }

    @Test
    void schemaViolationsBecomeApiValidationFailedWithFieldErrors() {
        String email = uniqueEmail();
        String access = registerVerifyAndLogin(email, "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12));

        ApiResponse badUsername = patchJson("/users/me", """
                {"username":"NO"}
                """, "Authorization", auth(access));
        assertThat(badUsername.status()).isEqualTo(HttpStatus.BAD_REQUEST.value());
        assertThat(badUsername.body().path("error").path("code").asText())
                .isEqualTo("API_VALIDATION_FAILED");
        assertThat(badUsername.body().path("error").path("field_errors").get(0).path("field").asText())
                .isEqualTo("username");

        ApiResponse badLocale = patchJson("/users/me", """
                {"locale":"not_a_locale"}
                """, "Authorization", auth(access));
        assertThat(badLocale.body().path("error").path("code").asText())
                .isEqualTo("API_VALIDATION_FAILED");
    }

    @Test
    void patchRequiresAuthentication() {
        ApiResponse response = patchJson("/users/me", "{\"display_name\":\"x\"}");
        assertThat(response.status()).isEqualTo(HttpStatus.UNAUTHORIZED.value());
        assertThat(response.body().path("error").path("code").asText())
                .isEqualTo("API_UNAUTHENTICATED");
    }

    @Test
    void emptyObjectAndExplicitNullsViolateTheSchema() {
        String email = uniqueEmail();
        String access = registerVerifyAndLogin(email, "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12));

        // Schema minProperties: 1 — an empty patch object is rejected.
        ApiResponse empty = patchJson("/users/me", "{}", "Authorization", auth(access));
        assertThat(empty.status()).isEqualTo(HttpStatus.BAD_REQUEST.value());
        assertThat(empty.body().path("error").path("code").asText())
                .isEqualTo("API_VALIDATION_FAILED");

        // The schema has no nullable branches: explicit null must fail instead of being
        // silently treated as "no change".
        ApiResponse explicitNull = patchJson("/users/me", """
                {"display_name":null}
                """, "Authorization", auth(access));
        assertThat(explicitNull.status()).isEqualTo(HttpStatus.BAD_REQUEST.value());
        assertThat(explicitNull.body().path("error").path("code").asText())
                .isEqualTo("API_VALIDATION_FAILED");
    }

    @Test
    void emptyReminderMethodsArrayClearsTheSetting() {
        String email = uniqueEmail();
        String access = registerVerifyAndLogin(email, "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12));

        // The schema has no minItems: an empty array is valid and clears the methods.
        ApiResponse cleared = patchJson("/users/me", """
                {"default_reminder_methods":[]}
                """, "Authorization", auth(access));
        assertThat(cleared.status()).isEqualTo(HttpStatus.OK.value());
        assertThat(cleared.body().path("data").path("preferences").path("default_reminder_methods").toString())
                .isEqualTo("[]");
    }

    @Test
    void fixedOffsetsAreNotIanaTimezones() {
        String email = uniqueEmail();
        String access = registerVerifyAndLogin(email, "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12));

        ApiResponse offset = patchJson("/users/me", """
                {"timezone":"+08:00"}
                """, "Authorization", auth(access));
        assertThat(offset.status()).isEqualTo(HttpStatus.BAD_REQUEST.value());
        assertThat(offset.body().path("error").path("code").asText())
                .isEqualTo("USER_PROFILE_INVALID");
    }

    @Test
    void displayNameLengthCountsUnicodeCodePoints() {
        String email = uniqueEmail();
        String access = registerVerifyAndLogin(email, "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12));

        // 25 emoji = 50 UTF-16 units but 25 code points: valid under maxLength 40.
        String emojiName = "\uD83D\uDE00".repeat(25);
        ApiResponse emoji = patchJson("/users/me", """
                {"display_name":"%s"}
                """.formatted(emojiName), "Authorization", auth(access));
        assertThat(emoji.status()).isEqualTo(HttpStatus.OK.value());
        assertThat(emoji.body().path("data").path("profile").path("display_name").asText())
                .isEqualTo(emojiName);

        // 41 ASCII characters exceed the schema's 40 code points.
        ApiResponse tooLong = patchJson("/users/me", """
                {"display_name":"%s"}
                """.formatted("a".repeat(41)), "Authorization", auth(access));
        assertThat(tooLong.status()).isEqualTo(HttpStatus.BAD_REQUEST.value());
        assertThat(tooLong.body().path("error").path("code").asText())
                .isEqualTo("API_VALIDATION_FAILED");
    }

    @Test
    void defaultReminderMethodsAreValidatedAndDeduplicated() {
        String email = uniqueEmail();
        String access = registerVerifyAndLogin(email, "user_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12));

        ApiResponse badMethod = patchJson("/users/me", """
                {"default_reminder_methods":["pigeon"]}
                """, "Authorization", auth(access));
        assertThat(badMethod.body().path("error").path("code").asText())
                .isEqualTo("API_VALIDATION_FAILED");

        ApiResponse good = patchJson("/users/me", """
                {"default_reminder_methods":["popup","ring","popup"]}
                """, "Authorization", auth(access));
        assertThat(good.status()).isEqualTo(HttpStatus.OK.value());
        assertThat(good.body().path("data").path("preferences").path("default_reminder_methods").toString())
                .isEqualTo("[\"popup\",\"ring\"]");
    }

    private static String uniqueEmail() {
        return "user-" + UUID.randomUUID() + "@example.com";
    }
}