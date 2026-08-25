package com.excellentcalendar.cloud.userdevice.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.Map;
import org.junit.jupiter.api.Test;

class UserSettingsValueTest {

    @Test
    void acceptsEmptySettings() {
        assertThat(UserSettingsValue.of(Map.of()).values()).isEmpty();
        assertThat(UserSettingsValue.of(null).values()).isEmpty();
    }

    @Test
    void acceptsScalarSnakeCaseKeys() {
        Map<String, Object> settings = Map.of(
                "theme", "system",
                "week_starts_on", 1,
                "show_completed", true);
        assertThat(UserSettingsValue.of(settings).values()).isEqualTo(settings);
    }

    @Test
    void rejectsForbiddenAndInvalidKeys() {
        assertThatThrownBy(() -> UserSettingsValue.of(Map.of("password", "x")))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> UserSettingsValue.of(Map.of("TokenHash", "x")))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> UserSettingsValue.of(Map.of("1leading_digit", "x")))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void rejectsNestedValues() {
        assertThatThrownBy(() -> UserSettingsValue.of(Map.of("nested", Map.of("a", 1))))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> UserSettingsValue.of(Map.of("list", java.util.List.of("a"))))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void rejectsMoreThan64Keys() {
        java.util.HashMap<String, Object> settings = new java.util.HashMap<>();
        for (int i = 0; i < 65; i++) {
            settings.put("key_" + i, i);
        }
        assertThatThrownBy(() -> UserSettingsValue.of(settings))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
