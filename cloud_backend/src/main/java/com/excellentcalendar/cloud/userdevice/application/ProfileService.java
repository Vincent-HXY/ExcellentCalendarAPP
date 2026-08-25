package com.excellentcalendar.cloud.userdevice.application;

import com.excellentcalendar.cloud.userdevice.domain.ReminderMethod;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

/**
 * Public profile/preferences API of the userdevice module. Identity calls it inside its own
 * transactions (register, authentication responses); the api layer calls it for user.get_current
 * and update_current. All updates are last-write-wins.
 */
public interface ProfileService {

    record ProfileSnapshot(
            UUID userId,
            String username,
            String displayName,
            UUID avatarAssetId,
            Instant createdAt,
            Instant updatedAt) {
    }

    record PreferencesSnapshot(
            UUID userId,
            String locale,
            String timezone,
            List<String> defaultReminderMethods,
            Map<String, Object> settings,
            Instant createdAt,
            Instant updatedAt) {
    }

    record ProfileUpdate(String username, String displayName) {

        public static ProfileUpdate none() {
            return new ProfileUpdate(null, null);
        }
    }

    record PreferencesUpdate(
            String locale,
            String timezone,
            List<ReminderMethod> defaultReminderMethods,
            Map<String, Object> settings) {

        public static PreferencesUpdate none() {
            return new PreferencesUpdate(null, null, null, null);
        }
    }

    record UpdateResult(ProfileSnapshot profile, PreferencesSnapshot preferences) {
    }

    ProfileSnapshot createProfile(UUID userId, String username, String displayName);

    PreferencesSnapshot createPreferences(UUID userId, String locale, String timezone);

    Optional<ProfileSnapshot> findProfile(UUID userId);

    Optional<PreferencesSnapshot> findPreferences(UUID userId);

    ProfileSnapshot updateProfile(UUID userId, ProfileUpdate update);

    PreferencesSnapshot updatePreferences(UUID userId, PreferencesUpdate update);

    /**
     * PATCH semantics in one transaction: profile and preferences commit together or not at all.
     */
    UpdateResult update(UUID userId, ProfileUpdate profileUpdate, PreferencesUpdate preferencesUpdate);

    ProfileSnapshot updateAvatar(UUID userId, UUID avatarAssetId);
}
