package com.excellentcalendar.cloud.userdevice.api;

import java.time.Instant;
import java.util.UUID;

public record UserAccountResponseDto(
        UUID id,
        String email,
        String status,
        Instant emailVerifiedAt,
        Instant createdAt,
        Instant updatedAt) {
}
