package com.excellentcalendar.cloud.identity.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.excellentcalendar.cloud.identity.config.IdentityProperties;
import java.time.Duration;
import java.time.Instant;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class JwtTokenProviderTest {

    private IdentityProperties properties;
    private JwtTokenProvider tokenProvider;
    private UUID userId;

    @BeforeEach
    void setUp() {
        properties = new IdentityProperties();
        properties.setJwtSecret("this-is-a-secret-key-that-is-at-least-32-characters!");
        tokenProvider = new JwtTokenProvider(properties);
        userId = UUID.randomUUID();
    }

    @Test
    @DisplayName("createAccessToken should return a non-empty string")
    void createAccessToken_shouldReturnNonEmptyString() {
        properties.setAccessTokenExpiration(Duration.ofMinutes(15));

        String token = tokenProvider.createAccessToken(userId);

        assertThat(token).isNotBlank();
    }

    @Test
    @DisplayName("createRefreshToken should return a non-empty string")
    void createRefreshToken_shouldReturnNonEmptyString() {
        properties.setRefreshTokenExpiration(Duration.ofDays(30));

        String token = tokenProvider.createRefreshToken(userId);

        assertThat(token).isNotBlank();
    }

    @Test
    @DisplayName("createAccessToken should contain the userId as subject")
    void createAccessToken_shouldContainUserIdAsSubject() {
        properties.setAccessTokenExpiration(Duration.ofMinutes(15));

        String token = tokenProvider.createAccessToken(userId);

        UUID extractedId = tokenProvider.getUserIdFromToken(token);
        assertThat(extractedId).isEqualTo(userId);
    }

    @Test
    @DisplayName("validateToken should return true for a valid token")
    void validateToken_shouldReturnTrue_forValidToken() {
        properties.setAccessTokenExpiration(Duration.ofMinutes(15));

        String token = tokenProvider.createAccessToken(userId);

        assertThat(tokenProvider.validateToken(token)).isTrue();
    }

    @Test
    @DisplayName("validateToken should return false for an expired token")
    void validateToken_shouldReturnFalse_forExpiredToken() {
        properties.setAccessTokenExpiration(Duration.ofSeconds(-1));

        String token = tokenProvider.createAccessToken(userId);

        assertThat(tokenProvider.validateToken(token)).isFalse();
    }

    @Test
    @DisplayName("validateToken should return false for a tampered token")
    void validateToken_shouldReturnFalse_forTamperedToken() {
        properties.setAccessTokenExpiration(Duration.ofMinutes(15));

        String token = tokenProvider.createAccessToken(userId) + "tampered";

        assertThat(tokenProvider.validateToken(token)).isFalse();
    }

    @Test
    @DisplayName("validateToken should return false for a random string")
    void validateToken_shouldReturnFalse_forRandomString() {
        assertThat(tokenProvider.validateToken("not-a-jwt-token")).isFalse();
    }

    @Test
    @DisplayName("getUserIdFromToken should return the correct UUID")
    void getUserIdFromToken_shouldReturnCorrectUuid() {
        properties.setAccessTokenExpiration(Duration.ofMinutes(15));

        String token = tokenProvider.createAccessToken(userId);

        UUID extractedId = tokenProvider.getUserIdFromToken(token);
        assertThat(extractedId).isEqualTo(userId);
    }

    @Test
    @DisplayName("getExpirationFromToken should return a future time for access token")
    void getExpirationFromToken_shouldReturnFutureTime_forAccessToken() {
        properties.setAccessTokenExpiration(Duration.ofMinutes(15));

        String token = tokenProvider.createAccessToken(userId);

        Instant expiration = tokenProvider.getExpirationFromToken(token);
        assertThat(expiration).isAfter(Instant.now());
    }

    @Test
    @DisplayName("getExpirationFromToken should return a future time for refresh token")
    void getExpirationFromToken_shouldReturnFutureTime_forRefreshToken() {
        properties.setRefreshTokenExpiration(Duration.ofDays(30));

        String token = tokenProvider.createRefreshToken(userId);

        Instant expiration = tokenProvider.getExpirationFromToken(token);
        assertThat(expiration).isAfter(Instant.now().plus(Duration.ofDays(29)));
    }
}