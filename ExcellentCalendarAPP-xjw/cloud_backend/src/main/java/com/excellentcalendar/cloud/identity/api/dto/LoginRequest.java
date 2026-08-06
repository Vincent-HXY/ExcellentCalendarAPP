package com.excellentcalendar.cloud.identity.api.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * Maps to {@code contracts/auth/login_request.schema.json}.
 */
public record LoginRequest(
        @NotBlank @Email @Size(max = 254) String email,
        @NotBlank @Size(min = 1, max = 128) String password
) {}