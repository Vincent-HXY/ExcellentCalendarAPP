package com.excellentcalendar.cloud.identity.api;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record ChangePasswordRequestDto(
        @NotBlank @Size(min = 1, max = 128) String currentPassword,
        @NotBlank @Size(min = 8, max = 128) String newPassword) {
}
