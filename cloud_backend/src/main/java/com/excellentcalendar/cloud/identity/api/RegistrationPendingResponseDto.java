package com.excellentcalendar.cloud.identity.api;

import com.excellentcalendar.cloud.identity.application.AuthenticationResults;
import java.util.UUID;

public record RegistrationPendingResponseDto(
        UUID accountId,
        EmailChallengeResponseDto challenge) {

    public static RegistrationPendingResponseDto from(AuthenticationResults.RegistrationPending result) {
        return new RegistrationPendingResponseDto(
                result.accountId(), EmailChallengeResponseDto.from(result.challenge()));
    }
}
