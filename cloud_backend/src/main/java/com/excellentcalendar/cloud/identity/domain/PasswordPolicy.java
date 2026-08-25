package com.excellentcalendar.cloud.identity.domain;

import java.util.Set;

/**
 * Password rules shared by register, change and reset: 8-128 Unicode characters without forced
 * composition classes, plus a small deny list of common or leaked passwords.
 */
public final class PasswordPolicy {

    private static final int MIN_CODE_POINTS = 8;
    private static final int MAX_CODE_POINTS = 128;

    private static final Set<String> COMMON_PASSWORDS = Set.of(
            "password", "password1", "password123", "passw0rd", "12345678", "123456789",
            "1234567890", "11111111", "00000000", "88888888", "qwertyui", "qwerty123",
            "abc12345", "iloveyou1", "letmein12", "welcome12", "admin1234", "sunshine1",
            "monkey123", "dragon123", "football1", "baseball1", "superman1", "trustno11",
            "zaq12wsx", "1qaz2wsx", "aaaaaaaa", "changeme1");

    private PasswordPolicy() {
    }

    public static void validate(String password) {
        if (password == null) {
            throw new PasswordPolicyViolationException();
        }
        int codePoints = password.codePointCount(0, password.length());
        if (codePoints < MIN_CODE_POINTS || codePoints > MAX_CODE_POINTS) {
            throw new PasswordPolicyViolationException();
        }
        if (COMMON_PASSWORDS.contains(password.toLowerCase(java.util.Locale.ROOT))) {
            throw new PasswordPolicyViolationException();
        }
    }

    public static final class PasswordPolicyViolationException extends RuntimeException {
    }
}
