package com.excellentcalendar.cloud.identity.api;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record RequestEmailChangeRequestDto(
        @NotBlank @Email @Size(max = 254) String newEmail,
        @NotBlank @Size(min = 1, max = 128) String currentPassword) {
}
