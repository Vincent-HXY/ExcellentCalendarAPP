package com.excellentcalendar.cloud.identity.api;

import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public record RegisterRequestDto(
        @NotBlank @Email @Size(max = 254) String email,
        @NotBlank @Pattern(regexp = "^[a-z0-9_]{3,24}$", message = "username must match [a-z0-9_]{3,24}")
        String username,
        @NotBlank @Size(min = 1, max = 40) String displayName,
        @NotBlank @Size(min = 8, max = 128) String password,
        @NotBlank @Pattern(regexp = "^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$", message = "locale is not a BCP 47 language tag")
        @Size(max = 35) String locale,
        @NotBlank @Size(min = 1, max = 64) String timezone,
        @NotBlank @Size(min = 1, max = 64) String agreementVersion,
        @AssertTrue(message = "agreement_accepted must be true") boolean agreementAccepted) {
}
