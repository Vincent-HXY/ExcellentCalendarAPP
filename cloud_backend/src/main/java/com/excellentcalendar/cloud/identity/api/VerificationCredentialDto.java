package com.excellentcalendar.cloud.identity.api;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/**
 * One of {@code code} (6 digits) or {@code link_token} (not issued in this phase; the service
 * rejects it with AUTH_VERIFICATION_INVALID).
 */
public record VerificationCredentialDto(
        @NotBlank @Pattern(regexp = "^(code|link_token)$") String credentialType,
        @Pattern(regexp = "^[0-9]{6}$") String code,
        @Size(min = 32, max = 512) String linkToken) {
}
