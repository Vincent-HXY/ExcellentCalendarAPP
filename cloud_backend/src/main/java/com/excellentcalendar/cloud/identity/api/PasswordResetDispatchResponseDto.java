package com.excellentcalendar.cloud.identity.api;

import com.excellentcalendar.cloud.identity.application.AuthenticationResults;
import java.time.Instant;

public record PasswordResetDispatchResponseDto(
        boolean accepted,
        Instant resendAvailableAt) {

    public static PasswordResetDispatchResponseDto from(AuthenticationResults.PasswordResetDispatch result) {
        return new PasswordResetDispatchResponseDto(true, result.resendAvailableAt());
    }
}
