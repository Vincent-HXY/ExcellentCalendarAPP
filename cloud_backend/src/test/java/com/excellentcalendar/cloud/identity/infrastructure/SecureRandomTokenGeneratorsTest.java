package com.excellentcalendar.cloud.identity.infrastructure;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class SecureRandomTokenGeneratorsTest {

    @Test
    void refreshTokensAre43CharacterBase64UrlStrings() {
        SecureRandomRefreshTokenGenerator generator = new SecureRandomRefreshTokenGenerator();
        for (int i = 0; i < 32; i++) {
            String token = generator.generate();
            assertThat(token).hasSize(43).matches("^[A-Za-z0-9_-]+$");
        }
    }

    @Test
    void verificationCodesAreSixDigits() {
        SecureRandomVerificationCodeGenerator generator = new SecureRandomVerificationCodeGenerator();
        for (int i = 0; i < 64; i++) {
            assertThat(generator.generate()).matches("^[0-9]{6}$");
        }
    }

    @Test
    void refreshTokensDoNotRepeatInPractice() {
        SecureRandomRefreshTokenGenerator generator = new SecureRandomRefreshTokenGenerator();
        assertThat(generator.generate()).isNotEqualTo(generator.generate());
    }
}
