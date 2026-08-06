package com.excellentcalendar.cloud.identity.api.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * Maps to {@code contracts/auth/refresh_session_request.schema.json}.
 */
public record RefreshSessionRequest(
        @JsonProperty("refresh_token") @NotBlank @Size(min = 32, max = 8192) String refreshToken
) {}