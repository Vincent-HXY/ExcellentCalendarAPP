package com.excellentcalendar.cloud.platform.password;

import org.springframework.security.crypto.argon2.Argon2PasswordEncoder;
import org.springframework.stereotype.Component;

/**
 * Password hashing using Argon2id.
 * <p>
 * The default parameters are safe for development. In production, benchmark
 * against the target hardware to tune the salt length, hash length, parallelism,
 * memory, and iterations.
 */
@Component
public class PasswordEncoder {

    private static final int SALT_LENGTH = 16;
    private static final int HASH_LENGTH = 32;
    private static final int PARALLELISM = 1;
    private static final int MEMORY_IN_KIB = 19456;   // 19 MiB
    private static final int ITERATIONS = 2;

    private final Argon2PasswordEncoder delegate;

    public PasswordEncoder() {
        this.delegate = new Argon2PasswordEncoder(
                SALT_LENGTH, HASH_LENGTH, PARALLELISM, MEMORY_IN_KIB, ITERATIONS);
    }

    /**
     * Encodes a raw password.
     */
    public String encode(CharSequence rawPassword) {
        return delegate.encode(rawPassword);
    }

    /**
     * Verifies a raw password against an encoded hash.
     */
    public boolean matches(CharSequence rawPassword, String encodedHash) {
        return delegate.matches(rawPassword, encodedHash);
    }
}