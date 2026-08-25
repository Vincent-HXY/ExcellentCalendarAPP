package com.excellentcalendar.cloud.identity.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

class PasswordPolicyTest {

    @ParameterizedTest
    @ValueSource(strings = {"CorrectHorseBattery", "a1b2c3d4", "密码密码密码密码", "8\u4e2a\u5b57\u7b26\u5bc6\u7801\u53ef\u4ee5"})
    void acceptsValidPasswords(String password) {
        PasswordPolicy.validate(password);
    }

    @ParameterizedTest
    @ValueSource(strings = {"", "short7", "password", "PASSWORD", "12345678", "qwerty123", "password123", "iloveyou1"})
    void rejectsTooShortAndCommonPasswords(String password) {
        assertThatThrownBy(() -> PasswordPolicy.validate(password))
                .isInstanceOf(PasswordPolicy.PasswordPolicyViolationException.class);
    }

    @Test
    void rejectsOverlongPasswords() {
        String password = "a".repeat(129);
        assertThatThrownBy(() -> PasswordPolicy.validate(password))
                .isInstanceOf(PasswordPolicy.PasswordPolicyViolationException.class);
    }

    @Test
    void acceptsBoundaryLengths() {
        PasswordPolicy.validate("x".repeat(8));
        PasswordPolicy.validate("y".repeat(128));
    }
}
