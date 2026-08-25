package com.excellentcalendar.cloud.userdevice.domain;

import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;

/**
 * Validated user settings payload: at most 64 snake_case keys with string/number/boolean scalar
 * values; sensitive key names are rejected. Stored as jsonb, never reinterpreted server-side.
 */
public final class UserSettingsValue {

    private static final Pattern KEY_PATTERN = Pattern.compile("^[a-z][a-z0-9_]{0,63}$");
    private static final Set<String> FORBIDDEN_KEYS = Set.of(
            "password", "password_hash", "access_token", "refresh_token", "token_hash",
            "verification_code", "link_token", "storage_key");

    private final Map<String, Object> values;

    private UserSettingsValue(Map<String, Object> values) {
        this.values = Map.copyOf(values);
    }

    public static UserSettingsValue of(Map<String, Object> settings) {
        if (settings == null || settings.isEmpty()) {
            return new UserSettingsValue(Map.of());
        }
        if (settings.size() > 64) {
            throw new IllegalArgumentException("settings exceeds 64 keys");
        }
        for (Map.Entry<String, Object> entry : settings.entrySet()) {
            String key = entry.getKey();
            if (key == null || !KEY_PATTERN.matcher(key).matches() || FORBIDDEN_KEYS.contains(key)) {
                throw new IllegalArgumentException("invalid settings key");
            }
            Object value = entry.getValue();
            if (!(value instanceof String || value instanceof Number || value instanceof Boolean)) {
                throw new IllegalArgumentException("settings values must be scalar");
            }
        }
        return new UserSettingsValue(settings);
    }

    public Map<String, Object> values() {
        return values;
    }
}
