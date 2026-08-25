package com.excellentcalendar.cloud.userdevice.api;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

public record UserPreferencesResponseDto(
        UUID userId,
        String locale,
        String timezone,
        List<String> defaultReminderMethods,
        Map<String, Object> settings,
        Instant createdAt,
        Instant updatedAt) {
}
