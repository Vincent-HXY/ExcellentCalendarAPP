package com.excellentcalendar.cloud.identity.api;

import jakarta.validation.constraints.NotNull;
import java.util.UUID;

public record ResendRegistrationRequestDto(@NotNull UUID challengeId) {
}
