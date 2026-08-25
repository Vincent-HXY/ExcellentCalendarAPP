package com.excellentcalendar.cloud.identity.api;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record RefreshSessionRequestDto(
        @NotBlank @Size(min = 32, max = 8192) String refreshToken) {
}
