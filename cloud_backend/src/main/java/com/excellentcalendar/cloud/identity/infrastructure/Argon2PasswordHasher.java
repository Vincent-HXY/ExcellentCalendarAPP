package com.excellentcalendar.cloud.identity.infrastructure;

import com.excellentcalendar.cloud.identity.domain.PasswordHasher;
import org.springframework.security.crypto.argon2.Argon2PasswordEncoder;
import org.springframework.stereotype.Component;

/**
 * Argon2id PHC-encoded password hashing (salt 16 B, hash 32 B, parallelism 1, 64 MiB memory,
 * 3 iterations). Parameters must be re-benchmarked on the target environment before production.
 */
@Component
public class Argon2PasswordHasher implements PasswordHasher {

    private final Argon2PasswordEncoder encoder = new Argon2PasswordEncoder(16, 32, 1, 65536, 3);

    @Override
    public String hash(String rawPassword) {
        return encoder.encode(rawPassword);
    }

    @Override
    public boolean matches(String rawPassword, String encodedHash) {
        return encoder.matches(rawPassword, encodedHash);
    }
}
