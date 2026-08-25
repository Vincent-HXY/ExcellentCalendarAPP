package com.excellentcalendar.cloud.identity.domain;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class TokenHashTest {

    @Test
    void hashesDeterministically() {
        assertThat(TokenHash.of("secret").hex())
                .isEqualTo(TokenHash.of("secret").hex())
                .hasSize(64);
    }

    @Test
    void distinguishesDifferentInputs() {
        assertThat(TokenHash.of("a").hex())
                .isNotEqualTo(TokenHash.of("b").hex());
    }

    @Test
    void comparesHexConstantTime() {
        String hash = TokenHash.of("candidate").hex();
        assertThat(TokenHash.constantTimeEquals(hash, hash)).isTrue();
        assertThat(TokenHash.constantTimeEquals(hash, TokenHash.of("other").hex())).isFalse();
        assertThat(TokenHash.constantTimeEquals(hash, null)).isFalse();
        assertThat(TokenHash.constantTimeEquals(null, null)).isFalse();
    }
}
