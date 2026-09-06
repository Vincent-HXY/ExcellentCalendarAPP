package com.excellentcalendar.cloud;

import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import javax.imageio.ImageIO;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.test.context.TestContextManager;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.node.ObjectNode;

/** Isolated Contract audit. Calls the real HTTP server and disposable PostgreSQL, never production. */
public final class BackendCalibrationProbe extends ApiIntegrationTestSupport {
    private final List<Map<String, Object>> cases = new ArrayList<>();

    private static String key() { return UUID.randomUUID().toString(); }
    private static String email() { return "contract-" + key() + "@example.com"; }
    private static String username() { return "ct_" + key().replace("-", "").substring(0, 12); }
    private String json(Object value) { return objectMapper.writeValueAsString(value); }

    private static void require(boolean value, String label) {
        if (!value) throw new AssertionError(label);
    }

    // Preserve actual types, lengths and nonsecret constraints for independent Python Schema checks.
    // No access/refresh token, credential, password or verification code is written to a report/log.
    private JsonNode redact(JsonNode input) {
        JsonNode result = input.deepCopy();
        if (result.isObject()) {
            ObjectNode object = (ObjectNode) result;
            for (String name : new ArrayList<>(object.propertyNames())) {
                JsonNode child = object.get(name);
                boolean secret = List.of("access_token", "refresh_token", "password", "verification_token")
                        .contains(name) || name.equals("code") && !object.has("message");
                if (secret) {
                    if (child.isString()) object.put(name, "x".repeat(child.stringValue().length()));
                } else {
                    object.set(name, redact(child));
                }
            }
        } else if (result.isArray()) {
            var array = (tools.jackson.databind.node.ArrayNode) result;
            for (int i = 0; i < array.size(); ++i) array.set(i, redact(array.get(i)));
        }
        return result;
    }

    private ApiResponse record(String id, String operation, ApiResponse response) {
        require(response.body() != null && response.body().has("ok"), id + ": missing envelope");
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("id", id);
        row.put("operation", operation);
        row.put("http_status", response.status());
        row.put("retry_after_header", response.header("Retry-After"));
        row.put("response", redact(response.body()));
        cases.add(row);
        return response;
    }

    private ApiResponse ok(String id, String operation, ApiResponse response) {
        record(id, operation, response);
        require(response.status() == 200 && response.body().path("ok").asBoolean(), id + ": expected success");
        return response;
    }

    private String registration(String address, String name) {
        return json(Map.of("email", address, "username", name, "display_name", "Contract Audit",
                "password", "CorrectHorseBattery", "locale", "zh-CN", "timezone", "Asia/Shanghai",
                "agreement_version", "terms-v1", "agreement_accepted", true));
    }

    private ApiResponse login(String address, String password) {
        return postJson("/auth/login", json(Map.of("email", address, "password", password)));
    }

    private void runAudit() throws Exception {
        String address = email();
        String body = registration(address, username());
        String idempotency = key();
        ApiResponse registered = ok("register.valid", "auth.register",
                postJson("/auth/register", body, "Idempotency-Key", idempotency));
        ApiResponse replay = record("register.same_key_different_payload", "auth.register",
                postJson("/auth/register", registration(email(), username()), "Idempotency-Key", idempotency));
        require(replay.body().path("data").equals(registered.body().path("data")),
                "Baseline changed: digest mismatch no longer replays prior registration");
        String challenge = registered.body().path("data").path("challenge").path("challenge_id").asText();
        record("resend.too_early", "auth.registration.resend", postJson("/auth/registration/resend",
                json(Map.of("challenge_id", challenge)), "Idempotency-Key", key()));
        jdbcTemplate.update("UPDATE email_action_challenges SET resend_available_at = now() - interval '1 second' WHERE id = ?",
                UUID.fromString(challenge));
        ApiResponse resent = ok("resend.valid", "auth.registration.resend", postJson("/auth/registration/resend",
                json(Map.of("challenge_id", challenge)), "Idempotency-Key", key()));
        challenge = resent.body().path("data").path("challenge_id").asText();
        ApiResponse verified = ok("verify.valid", "auth.registration.verify",
                postJson("/auth/registration/verify", json(Map.of("challenge_id", challenge,
                        "credential", Map.of("credential_type", "code", "code", mailSender.latestCode(address))))));
        String access = tokenOf(verified.body());
        String refresh = refreshTokenOf(verified.body());
        ok("login.valid", "auth.login", login(address, "CorrectHorseBattery"));
        record("login.invalid_password", "auth.login", login(address, "NotThePassword"));
        record("login.unknown_key", "auth.login", postJson("/auth/login", json(Map.of(
                "email", address, "password", "CorrectHorseBattery", "extra", true))));
        record("login.scalar_coercion", "auth.login", postJson("/auth/login", json(Map.of(
                "email", address, "password", 12345))));
        record("verify.credential_extra_key", "auth.registration.verify", postJson("/auth/registration/verify",
                json(Map.of("challenge_id", challenge, "credential", Map.of(
                        "credential_type", "code", "code", "123456", "extra", true)))));
        record("verify.credential_wrong_union", "auth.registration.verify", postJson("/auth/registration/verify",
                json(Map.of("challenge_id", challenge, "credential", Map.of(
                        "credential_type", "code", "token", "x".repeat(40))))));
        record("get_current.unauthenticated", "user.get_current", getJson("/users/me"));
        ok("get_current.valid", "user.get_current", getJson("/users/me", "Authorization", auth(access)));
        ok("update_current.valid", "user.update_current", patchJson("/users/me",
                "{\"display_name\":\"Contract audit 2\"}", "Authorization", auth(access)));
        String[][] patches = {
            {"empty", "{}"}, {"null", "{\"display_name\":null}"},
            {"extra", "{\"unknown\":true}"}, {"invalid_timezone", "{\"timezone\":\"Not/AZone\"}"},
            {"fixed_offset", "{\"timezone\":\"+08:00\"}"},
            {"arbitrary_settings", "{\"settings\":{\"audit_only\":true}}"},
            {"locale", "{\"locale\":\"en-US\"}"},
            {"wechat", "{\"default_reminder_methods\":[\"wechat\"]}"},
            {"method_order", "{\"default_reminder_methods\":[\"popup\",\"ring\"]}"},
            {"method_duplicates", "{\"default_reminder_methods\":[\"popup\",\"popup\"]}"},
            {"method_empty", "{\"default_reminder_methods\":[]}"},
            {"nested_setting", "{\"settings\":{\"audit_only\":{\"x\":1}}}"}
        };
        for (String[] patch : patches) record("update_current." + patch[0], "user.update_current",
                patchJson("/users/me", patch[1], "Authorization", auth(access)));

        var png = new ByteArrayOutputStream();
        ImageIO.write(new BufferedImage(200, 200, BufferedImage.TYPE_INT_RGB), "png", png);
        String avatarKey = key();
        ApiResponse avatar = ok("avatar.upload", "user.avatar.upload", postMultipart("/users/me/avatar", Map.of("file", png.toByteArray()),
                Map.of("file", "image/png"), "Authorization", auth(access), "Idempotency-Key", avatarKey));
        var changedImage = new BufferedImage(200, 200, BufferedImage.TYPE_INT_RGB);
        changedImage.setRGB(100, 100, 0xFFFFFF);
        var changedPng = new ByteArrayOutputStream();
        ImageIO.write(changedImage, "png", changedPng);
        ApiResponse avatarReplay = record("avatar.same_key_different_content", "user.avatar.upload",
                postMultipart("/users/me/avatar", Map.of("file", changedPng.toByteArray()), Map.of("file", "image/png"),
                        "Authorization", auth(access), "Idempotency-Key", avatarKey));
        require(avatar.body().path("data").equals(avatarReplay.body().path("data")),
                "Baseline changed: multipart digest mismatch no longer replays prior avatar");
        ok("avatar.delete", "user.avatar.delete", deleteJson("/users/me/avatar", "Authorization", auth(access)));

        ApiResponse rotated = ok("refresh.valid", "auth.token.refresh", postJson("/auth/token/refresh",
                json(Map.of("refresh_token", refresh))));
        access = rotated.body().path("data").path("access_token").asText();
        String newAddress = email();
        ApiResponse emailRequest = ok("email_change.request", "auth.email_change.request",
                postJson("/auth/email-change/request", json(Map.of("new_email", newAddress,
                        "current_password", "CorrectHorseBattery")), "Authorization", auth(access), "Idempotency-Key", key()));
        ApiResponse emailConfirmed = ok("email_change.confirm", "auth.email_change.confirm",
                postJson("/auth/email-change/confirm", json(Map.of("email_change_request_id",
                        emailRequest.body().path("data").path("action_id").asText(), "credential", Map.of(
                        "credential_type", "code", "code", mailSender.latestCode(newAddress)))), "Authorization", auth(access)));
        access = tokenOf(emailConfirmed.body());
        ApiResponse changed = ok("password.change", "auth.password.change", postJson("/auth/password/change",
                json(Map.of("current_password", "CorrectHorseBattery", "new_password", "BrandNewPassword1")),
                "Authorization", auth(access)));
        access = tokenOf(changed.body());
        ok("logout_all.valid", "auth.logout_all", postJson("/auth/logout-all", "{}", "Authorization", auth(access)));
        ApiResponse relogin = ok("login.after_logout_all", "auth.login", login(newAddress, "BrandNewPassword1"));
        ok("logout.valid", "auth.logout", postJson("/auth/logout",
                json(Map.of("refresh_token", refreshTokenOf(relogin.body())))));
        ok("password_reset.request", "auth.password_reset.request", postJson("/auth/password-reset/request",
                json(Map.of("email", newAddress)), "Idempotency-Key", key()));
        ok("password_reset.confirm", "auth.password_reset.confirm", postJson("/auth/password-reset/confirm",
                json(Map.of("email", newAddress, "new_password", "AnotherPassword2", "credential", Map.of(
                        "credential_type", "code", "code", mailSender.latestCode(newAddress))))));
        record("registration_email.absent_route", "auth.registration.email.update",
                patchJson("/auth/registration/email", "{}", "Idempotency-Key", key()));
    }

    public static void main(String[] args) throws Exception {
        require(args.length == 1, "report path required");
        var manager = new TestContextManager(BackendCalibrationProbe.class);
        var probe = new BackendCalibrationProbe();
        var report = new LinkedHashMap<String, Object>();
        report.put("passed", false);
        report.put("scope", "Observed current Backend HTTP behavior; planned sync requirements are not runtime implemented");
        report.put("secret_values_redacted_preserving_type_and_length", true);
        report.put("cases", probe.cases);
        Throwable failure = null;
        try {
            manager.beforeTestClass();
            manager.prepareTestInstance(probe);
            probe.runAudit();
            report.put("passed", true);
        } catch (Throwable error) {
            failure = error;
            report.put("error", error.getClass().getSimpleName() + ": " + error.getMessage());
        } finally {
            if (probe.objectMapper != null) {
                Files.writeString(Path.of(args[0]), probe.objectMapper.writerWithDefaultPrettyPrinter().writeValueAsString(report));
            }
            if (manager.getTestContext().hasApplicationContext()) {
                ((ConfigurableApplicationContext) manager.getTestContext().getApplicationContext()).close();
            }
            POSTGRESQL.stop();
        }
        if (failure != null) throw new AssertionError("HTTP calibration incomplete", failure);
    }
}
