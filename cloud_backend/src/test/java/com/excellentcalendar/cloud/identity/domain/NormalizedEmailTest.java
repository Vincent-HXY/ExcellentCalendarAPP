package com.excellentcalendar.cloud.identity.domain;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class NormalizedEmailTest {

    @Test
    void normalizesToTrimmedLowercase() {
        assertThat(NormalizedEmail.of("  User@Example.COM ").value())
                .isEqualTo("user@example.com");
    }

    @Test
    void masksLocalPart() {
        assertThat(NormalizedEmail.of("user@example.com").masked())
                .isEqualTo("u***r@example.com");
        assertThat(NormalizedEmail.of("ab@example.com").masked())
                .isEqualTo("a***b@example.com");
        assertThat(NormalizedEmail.of("a@example.com").masked())
                .isEqualTo("a***@example.com");
    }

    @Test
    void masksUnicodeLocalPart() {
        assertThat(NormalizedEmail.of("张三@example.com").masked())
                .isEqualTo("张***三@example.com");
    }
}
