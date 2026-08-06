package com.excellentcalendar.cloud.identity.api.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * Maps to {@code contracts/auth/request_email_change_request.schema.json}.
 */
public record EmailChangeRequest(
        @JsonProperty("new_email") @NotBlank @Email @Size(max = 254) String newEmail,
        @JsonProperty("current_password") @NotBlank @Size(min = 1, max = 128) String currentPassword
) {}