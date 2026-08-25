package com.excellentcalendar.cloud.identity.api;

import com.excellentcalendar.cloud.identity.application.AuthenticationResults;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

public record EmailChallengeResponseDto(
        UUID challengeId,
        UUID actionId,
        String purpose,
        String maskedEmail,
        List<String> credentialTypes,
        Instant expiresAt,
        Instant resendAvailableAt) {

    public static EmailChallengeResponseDto from(AuthenticationResults.Challenge challenge) {
        return new EmailChallengeResponseDto(
                challenge.challengeId(),
                challenge.actionId(),
                challenge.purpose().wireValue(),
                challenge.maskedEmail(),
                challenge.credentialTypes(),
                challenge.expiresAt(),
                challenge.resendAvailableAt());
    }
}
