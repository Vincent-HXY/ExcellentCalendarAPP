package com.excellentcalendar.cloud.identity.application;

import com.excellentcalendar.cloud.identity.domain.EmailActionPurpose;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Wire-neutral results of the identity use cases; the api layer maps them onto contract DTOs.
 */
public final class AuthenticationResults {

    private AuthenticationResults() {
    }

    public record TokenPair(
            UUID sessionId,
            String accessToken,
            Instant accessTokenExpiresAt,
            String refreshToken,
            Instant refreshTokenExpiresAt) {
    }

    public record CurrentUser(
            UUID accountId,
            String email,
            String status,
            Instant emailVerifiedAt,
            Instant accountCreatedAt,
            Instant accountUpdatedAt,
            UUID profileUserId,
            String username,
            String displayName,
            UUID avatarAssetId,
            Instant profileCreatedAt,
            Instant profileUpdatedAt,
            UUID preferencesUserId,
            String locale,
            String timezone,
            List<String> defaultReminderMethods,
            Map<String, Object> settings,
            Instant preferencesCreatedAt,
            Instant preferencesUpdatedAt) {
    }

    public record Authentication(CurrentUser currentUser, TokenPair tokens) {
    }

    public record Challenge(
            UUID challengeId,
            UUID actionId,
            EmailActionPurpose purpose,
            String maskedEmail,
            List<String> credentialTypes,
            Instant expiresAt,
            Instant resendAvailableAt) {
    }

    public record RegistrationPending(UUID accountId, Challenge challenge) {
    }

    public record PasswordResetDispatch(Instant resendAvailableAt) {
    }
}
