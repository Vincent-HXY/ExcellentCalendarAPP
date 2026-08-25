package com.excellentcalendar.cloud.userdevice.infrastructure.persistence;

import com.excellentcalendar.cloud.userdevice.domain.ReminderMethod;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Entity
@Table(name = "user_preferences")
public class UserPreferencesEntity {

    @Id
    @Column(name = "user_id")
    private UUID userId;

    @Column(nullable = false, length = 35)
    private String locale;

    @Column(nullable = false, length = 64)
    private String timezone;

    @Column(name = "default_reminder_methods", nullable = false, columnDefinition = "text[]")
    private String[] defaultReminderMethods;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(nullable = false, columnDefinition = "jsonb")
    private Map<String, Object> settings;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    protected UserPreferencesEntity() {
    }

    public UserPreferencesEntity(UUID userId, String locale, String timezone, Instant now) {
        this.userId = userId;
        this.locale = locale;
        this.timezone = timezone;
        this.defaultReminderMethods = new String[0];
        this.settings = Map.of();
        this.createdAt = now;
        this.updatedAt = now;
    }

    public UUID getUserId() {
        return userId;
    }

    public String getLocale() {
        return locale;
    }

    public String getTimezone() {
        return timezone;
    }

    public List<ReminderMethod> getDefaultReminderMethods() {
        List<ReminderMethod> methods = new ArrayList<>();
        for (String value : defaultReminderMethods) {
            methods.add(ReminderMethod.fromWire(value));
        }
        return List.copyOf(methods);
    }

    public Map<String, Object> getSettings() {
        return settings == null ? Map.of() : new LinkedHashMap<>(settings);
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    public void updateLocale(String locale, Instant now) {
        this.locale = locale;
        this.updatedAt = now;
    }

    public void updateTimezone(String timezone, Instant now) {
        this.timezone = timezone;
        this.updatedAt = now;
    }

    public void updateDefaultReminderMethods(List<ReminderMethod> methods, Instant now) {
        this.defaultReminderMethods = methods.stream().map(ReminderMethod::wireValue).toArray(String[]::new);
        this.updatedAt = now;
    }

    public void updateSettings(Map<String, Object> settings, Instant now) {
        this.settings = new LinkedHashMap<>(settings);
        this.updatedAt = now;
    }
}
