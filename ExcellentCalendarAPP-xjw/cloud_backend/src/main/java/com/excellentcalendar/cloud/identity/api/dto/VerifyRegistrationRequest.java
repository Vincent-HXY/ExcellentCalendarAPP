package com.excellentcalendar.cloud.identity.api.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.util.UUID;

/**
 * Maps to {@code contracts/auth/verify_registration_request.schema.json}.
 */
public record VerifyRegistrationRequest(
        @JsonProperty("challenge_id") @NotNull UUID challengeId,
        @NotNull @Valid Credential credential
) {
    public record Credential(
            @JsonProperty("credential_type") @NotBlank String credentialType,
            String code,
            @JsonProperty("link_token") String linkToken
    ) {
        public String getCode() {
            return "code".equals(credentialType) ? code : linkToken;
        }
    }
}