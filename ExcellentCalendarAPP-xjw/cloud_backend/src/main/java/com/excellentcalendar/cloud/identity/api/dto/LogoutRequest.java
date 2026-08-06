package com.excellentcalendar.cloud.identity.api.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * Maps to {@code contracts/auth/logout_request.schema.json}.
 */
public record LogoutRequest(
        @JsonProperty("refresh_token") @NotBlank @Size(min = 32, max = 8192) String refreshToken
) {}