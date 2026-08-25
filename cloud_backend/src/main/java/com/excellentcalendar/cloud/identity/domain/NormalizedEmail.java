package com.excellentcalendar.cloud.identity.domain;

import java.util.Locale;

/**
 * Trimmed, locale-independent lowercase email used for login matching and the partial unique
 * index. The original spelling stays on the account row and is the only value returned to clients.
 */
public record NormalizedEmail(String value) {

    public static NormalizedEmail of(String email) {
        if (email == null || email.isBlank()) {
            throw new IllegalArgumentException("email must not be blank");
        }
        String normalized = email.trim().toLowerCase(Locale.ROOT);
        if (normalized.length() > 254) {
            throw new IllegalArgumentException("email exceeds 254 characters");
        }
        return new NormalizedEmail(normalized);
    }

    /**
     * Masks the local part for public responses: first char, then {@code ***}, then the last char
     * when the local part has at least two characters.
     */
    public String masked() {
        int at = value.indexOf('@');
        String local = at > 0 ? value.substring(0, at) : value;
        String domain = at >= 0 ? value.substring(at) : "";
        if (local.length() <= 1) {
            return local + "***" + domain;
        }
        return local.charAt(0) + "***" + local.charAt(local.length() - 1) + domain;
    }
}
