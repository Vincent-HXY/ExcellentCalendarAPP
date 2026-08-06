package com.excellentcalendar.cloud.identity.dto.request;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record ResetPasswordRequest(
        @NotBlank @Size(min = 6, max = 6) String code,
        @NotBlank @Size(min = 8, max = 128) String newPassword) {
}