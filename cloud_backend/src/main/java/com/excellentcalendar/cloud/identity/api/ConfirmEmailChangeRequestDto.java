package com.excellentcalendar.cloud.identity.api;

import jakarta.validation.constraints.NotNull;
import java.util.UUID;

public record ConfirmEmailChangeRequestDto(
        @NotNull UUID emailChangeRequestId,
        @NotNull VerificationCredentialDto credential) {
}
