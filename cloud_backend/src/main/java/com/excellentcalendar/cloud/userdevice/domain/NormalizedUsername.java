package com.excellentcalendar.cloud.userdevice.domain;

import java.util.Locale;

/**
 * Case-insensitive unique username index value; the contract already restricts usernames to
 * {@code [a-z0-9_]{3,24}}.
 */
public record NormalizedUsername(String value) {

    public static NormalizedUsername of(String username) {
        if (username == null || username.isBlank()) {
            throw new IllegalArgumentException("username must not be blank");
        }
        return new NormalizedUsername(username.trim().toLowerCase(Locale.ROOT));
    }
}
