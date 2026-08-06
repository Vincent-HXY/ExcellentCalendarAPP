package com.excellentcalendar.cloud.identity.api.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/**
 * Maps to {@code contracts/auth/registration_request.schema.json}.
 */
public record RegistrationRequest(
        @NotBlank @Email @Size(max = 254) String email,
        @NotBlank @Pattern(regexp = "^[a-z0-9_]{3,24}$") String username,
        @JsonProperty("display_name") @NotBlank @Size(min = 1, max = 40) String displayName,
        @NotBlank @Size(min = 8, max = 128) String password,
        @NotBlank @Pattern(regexp = "^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$") @Size(max = 35) String locale,
        @NotBlank @Size(min = 1, max = 64) String timezone,
        @JsonProperty("agreement_version") @NotBlank @Size(min = 1, max = 64) String agreementVersion,
        @JsonProperty("agreement_accepted") @AssertTrue boolean agreementAccepted
) {}