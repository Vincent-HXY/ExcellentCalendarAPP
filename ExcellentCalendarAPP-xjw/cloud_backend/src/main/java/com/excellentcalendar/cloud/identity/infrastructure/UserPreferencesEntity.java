package com.excellentcalendar.cloud.identity.infrastructure;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

/**
 * JPA entity mapping the {@code user_preferences} table.
 */
@Entity
@Table(name = "user_preferences")
public class UserPreferencesEntity {

    @Id
    @Column(name = "user_id")
    private UUID userId;

    @Column(nullable = false)
    private String locale;

    @Column(nullable = false)
    private String timezone;

    @Column(name = "default_reminder_methods", columnDefinition = "TEXT[]")
    private String[] defaultReminderMethods;

    @Column(columnDefinition = "TEXT")
    private String settings;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    public UserPreferencesEntity() {}

    public UUID getUserId() { return userId; }
    public void setUserId(UUID userId) { this.userId = userId; }

    public String getLocale() { return locale; }
    public void setLocale(String locale) { this.locale = locale; }

    public String getTimezone() { return timezone; }
    public void setTimezone(String timezone) { this.timezone = timezone; }

    public String[] getDefaultReminderMethods() { return defaultReminderMethods; }
    public void setDefaultReminderMethods(String[] defaultReminderMethods) { this.defaultReminderMethods = defaultReminderMethods; }

    public String getSettings() { return settings; }
    public void setSettings(String settings) { this.settings = settings; }

    public Instant getCreatedAt() { return createdAt; }
    public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }

    public Instant getUpdatedAt() { return updatedAt; }
    public void setUpdatedAt(Instant updatedAt) { this.updatedAt = updatedAt; }
}