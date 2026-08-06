package com.excellentcalendar.cloud.userdevice.domain;

import java.time.Instant;
import java.util.UUID;

/**
 * Stable user preferences returned with the current-user aggregate.
 */
public class UserPreferences {

    private final UUID userId;
    private String locale;
    private String timezone;
    private String[] defaultReminderMethods;
    private String settings;
    private final Instant createdAt;
    private Instant updatedAt;

    public UserPreferences(
            UUID userId, String locale, String timezone,
            String[] defaultReminderMethods, String settings,
            Instant createdAt, Instant updatedAt) {
        this.userId = userId;
        this.locale = locale;
        this.timezone = timezone;
        this.defaultReminderMethods = defaultReminderMethods;
        this.settings = settings;
        this.createdAt = createdAt;
        this.updatedAt = updatedAt;
    }

    public void updatePreferences(
            String locale, String timezone,
            String[] defaultReminderMethods, String settings,
            java.time.Clock clock) {
        if (locale != null) this.locale = locale;
        if (timezone != null) this.timezone = timezone;
        if (defaultReminderMethods != null) this.defaultReminderMethods = defaultReminderMethods;
        if (settings != null) this.settings = settings;
        this.updatedAt = clock.instant();
    }

    // Getters

    public UUID getUserId() { return userId; }
    public String getLocale() { return locale; }
    public String getTimezone() { return timezone; }
    public String[] getDefaultReminderMethods() { return defaultReminderMethods; }
    public String getSettings() { return settings; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
}