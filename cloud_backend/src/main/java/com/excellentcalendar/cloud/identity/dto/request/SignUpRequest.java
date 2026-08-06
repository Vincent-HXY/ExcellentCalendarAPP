package com.excellentcalendar.cloud.identity.dto.request;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record SignUpRequest(
        @NotBlank @Email @Size(max = 255) String email,
        @NotBlank @Size(min = 3, max = 50) String username,
        @NotBlank @Size(min = 1, max = 100) String displayName,
        @NotBlank @Size(min = 8, max = 128) String password) {
}