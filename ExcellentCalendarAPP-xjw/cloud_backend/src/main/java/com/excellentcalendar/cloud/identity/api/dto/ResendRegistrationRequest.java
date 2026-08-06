package com.excellentcalendar.cloud.identity.api.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.NotNull;
import java.util.UUID;

/**
 * Maps to {@code contracts/auth/resend_registration_request.schema.json}.
 */
public record ResendRegistrationRequest(
        @JsonProperty("challenge_id") @NotNull UUID challengeId
) {}