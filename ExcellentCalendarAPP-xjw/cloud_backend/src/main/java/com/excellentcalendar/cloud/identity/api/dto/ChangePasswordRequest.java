package com.excellentcalendar.cloud.identity.api.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * Maps to {@code contracts/auth/change_password_request.schema.json}.
 */
public record ChangePasswordRequest(
        @JsonProperty("current_password") @NotBlank @Size(min = 1, max = 128) String currentPassword,
        @JsonProperty("new_password") @NotBlank @Size(min = 8, max = 128) String newPassword
) {}