package com.excellentcalendar.cloud.identity.api;

import jakarta.validation.constraints.NotNull;
import java.util.UUID;

public record VerifyRegistrationRequestDto(
        @NotNull UUID challengeId,
        @NotNull VerificationCredentialDto credential) {
}
