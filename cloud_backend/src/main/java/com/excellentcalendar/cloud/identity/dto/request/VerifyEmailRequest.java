package com.excellentcalendar.cloud.identity.dto.request;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record VerifyEmailRequest(
        @NotBlank @Size(min = 6, max = 6) String code) {
}