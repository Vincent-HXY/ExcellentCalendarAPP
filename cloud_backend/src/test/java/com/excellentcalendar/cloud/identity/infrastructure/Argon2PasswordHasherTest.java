package com.excellentcalendar.cloud.identity.infrastructure;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class Argon2PasswordHasherTest {

    private final Argon2PasswordHasher hasher = new Argon2PasswordHasher();

    @Test
    void producesPhcEncodedHashesThatVerify() {
        String hash = hasher.hash("CorrectHorseBattery");
        assertThat(hash).startsWith("$argon2id$v=19$");
        assertThat(hasher.matches("CorrectHorseBattery", hash)).isTrue();
        assertThat(hasher.matches("WrongPassword", hash)).isFalse();
    }

    @Test
    void saltsDifferBetweenHashes() {
        assertThat(hasher.hash("same-password"))
                .isNotEqualTo(hasher.hash("same-password"));
    }

    @Test
    void usesTheAdrPinnedArgon2Parameters() {
        // ADR-0004 §4: Argon2id, salt 16B, hash 32B, parallelism 1, memory 65536 KiB, iterations 3.
        String hash = hasher.hash("CorrectHorseBattery");
        String[] parts = hash.split("\\$");
        assertThat(parts).hasSize(6);
        assertThat(parts[1]).isEqualTo("argon2id");
        assertThat(parts[2]).isEqualTo("v=19");
        assertThat(parts[3]).isEqualTo("m=65536,t=3,p=1");
        assertThat(java.util.Base64.getDecoder().decode(parts[4])).hasSize(16);
        assertThat(java.util.Base64.getDecoder().decode(parts[5])).hasSize(32);
    }
}
