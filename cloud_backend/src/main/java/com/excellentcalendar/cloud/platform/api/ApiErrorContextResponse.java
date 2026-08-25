package com.excellentcalendar.cloud.platform.api;

import java.time.Instant;
import java.util.List;

/**
 * Error context carried by {@link ApiErrorResponse}. Matches
 * {@code contracts/common/api_error_context.schema.json}: only
 * {@code verification_challenge} is defined, and its {@code purpose} is fixed to
 * {@code registration_verification} for the login flow.
 */
public record ApiErrorContextResponse(
        VerificationChallengeContextResponse verificationChallenge) {

    public record VerificationChallengeContextResponse(
            String challengeId,
            String purpose,
            String maskedEmail,
            List<String> credentialTypes,
            Instant expiresAt,
            Instant resendAvailableAt) {
    }
}
