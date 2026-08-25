package com.excellentcalendar.cloud.identity.domain;

/**
 * Port for password hashing and verification (Argon2id PHC strings in production).
 */
public interface PasswordHasher {

    String hash(String rawPassword);

    boolean matches(String rawPassword, String encodedHash);
}
