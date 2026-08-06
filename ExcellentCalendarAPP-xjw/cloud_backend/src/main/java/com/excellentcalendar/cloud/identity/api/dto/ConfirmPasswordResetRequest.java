package com.excellentcalendar.cloud.identity.api.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/**
 * Maps to {@code contracts/auth/confirm_password_reset_request.schema.json}.
 */
public record ConfirmPasswordResetRequest(
        @NotBlank @Email @Size(max = 254) String email,
        @NotNull @Valid Credential credential,
        @JsonProperty("new_password") @NotBlank @Size(min = 8, max = 128) String newPassword
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