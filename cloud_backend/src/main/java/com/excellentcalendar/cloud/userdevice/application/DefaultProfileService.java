package com.excellentcalendar.cloud.userdevice.application;

import com.excellentcalendar.cloud.userdevice.domain.NormalizedUsername;
import com.excellentcalendar.cloud.platform.api.ApiErrorCode;
import com.excellentcalendar.cloud.platform.api.ApiException;
import com.excellentcalendar.cloud.platform.api.ApiFieldErrorResponse;
import com.excellentcalendar.cloud.userdevice.domain.ReminderMethod;
import com.excellentcalendar.cloud.userdevice.domain.UserSettingsValue;
import com.excellentcalendar.cloud.userdevice.infrastructure.persistence.UserPreferencesEntity;
import com.excellentcalendar.cloud.userdevice.infrastructure.persistence.UserPreferencesRepository;
import com.excellentcalendar.cloud.userdevice.infrastructure.persistence.UserProfileEntity;
import com.excellentcalendar.cloud.userdevice.infrastructure.persistence.UserProfileRepository;
import java.time.Clock;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class DefaultProfileService implements ProfileService {

    private final UserProfileRepository profileRepository;
    private final UserPreferencesRepository preferencesRepository;
    private final Clock clock;

    public DefaultProfileService(
            UserProfileRepository profileRepository,
            UserPreferencesRepository preferencesRepository,
            Clock clock) {
        this.profileRepository = profileRepository;
        this.preferencesRepository = preferencesRepository;
        this.clock = clock;
    }

    @Override
    @Transactional
    public ProfileSnapshot createProfile(UUID userId, String username, String displayName) {
        NormalizedUsername normalized = NormalizedUsername.of(username);
        UserProfileEntity entity =
                new UserProfileEntity(userId, username, normalized.value(), displayName, clock.instant());
        // Flush raises the username uniqueness violation inside the caller's catch block.
        return toSnapshot(profileRepository.saveAndFlush(entity));
    }

    @Override
    @Transactional
    public PreferencesSnapshot createPreferences(UUID userId, String locale, String timezone) {
        UserPreferencesEntity entity = new UserPreferencesEntity(userId, locale, timezone, clock.instant());
        return toSnapshot(preferencesRepository.save(entity));
    }

    @Override
    @Transactional(readOnly = true)
    public Optional<ProfileSnapshot> findProfile(UUID userId) {
        return profileRepository.findById(userId).map(this::toSnapshot);
    }

    @Override
    @Transactional(readOnly = true)
    public Optional<PreferencesSnapshot> findPreferences(UUID userId) {
        return preferencesRepository.findById(userId).map(this::toSnapshot);
    }

    @Override
    @Transactional
    public ProfileSnapshot updateProfile(UUID userId, ProfileUpdate update) {
        UserProfileEntity profile = requireProfile(userId);
        if (update.username() != null) {
            NormalizedUsername normalized = NormalizedUsername.of(update.username());
            if (profileRepository.existsByNormalizedUsernameAndUserIdNot(normalized.value(), userId)) {
                throw new ApiException(ApiErrorCode.AUTH_USERNAME_ALREADY_EXISTS);
            }
            profile.updateUsername(update.username(), normalized.value(), clock.instant());
            // Flush raises a concurrent duplicate inside this method (the unique index is the final
            // concurrency guard); map it to the declared code instead of leaking a 500.
            try {
                profileRepository.saveAndFlush(profile);
            } catch (org.springframework.dao.DataIntegrityViolationException exception) {
                if (isUsernameViolation(exception)) {
                    throw new ApiException(ApiErrorCode.AUTH_USERNAME_ALREADY_EXISTS,
                            List.of(new ApiFieldErrorResponse(
                                    "username", ApiErrorCode.AUTH_USERNAME_ALREADY_EXISTS.code(),
                                    "The username is already in use")));
                }
                throw exception;
            }
        }
        if (update.displayName() != null) {
            String displayName = update.displayName().trim();
            if (displayName.isEmpty()) {
                throw new ApiException(ApiErrorCode.USER_PROFILE_INVALID,
                        List.of(fieldError("display_name", "display_name must not be blank")));
            }
            profile.updateDisplayName(displayName, clock.instant());
        }
        return toSnapshot(profile);
    }

    private static boolean isUsernameViolation(org.springframework.dao.DataIntegrityViolationException exception) {
        return String.valueOf(exception.getMostSpecificCause().getMessage())
                .contains("uq_user_profiles_normalized_username");
    }

    @Override
    @Transactional
    public PreferencesSnapshot updatePreferences(UUID userId, PreferencesUpdate update) {
        UserPreferencesEntity preferences = requirePreferences(userId);
        if (update.timezone() != null) {
            String timezone = com.excellentcalendar.cloud.platform.time.IanaTimezones
                    .tryNormalize(update.timezone())
                    .orElseThrow(() -> new ApiException(ApiErrorCode.USER_PROFILE_INVALID,
                            List.of(fieldError("timezone", "timezone must be a valid IANA timezone id"))));
            preferences.updateTimezone(timezone, clock.instant());
        }
        if (update.locale() != null) {
            preferences.updateLocale(update.locale(), clock.instant());
        }
        if (update.defaultReminderMethods() != null) {
            List<ReminderMethod> deduplicated = new LinkedHashSet<>(update.defaultReminderMethods())
                    .stream().toList();
            preferences.updateDefaultReminderMethods(deduplicated, clock.instant());
        }
        if (update.settings() != null) {
            try {
                Map<String, Object> validated = UserSettingsValue.of(update.settings()).values();
                preferences.updateSettings(validated, clock.instant());
            } catch (IllegalArgumentException exception) {
                throw new ApiException(ApiErrorCode.USER_PROFILE_INVALID,
                        List.of(fieldError("settings", exception.getMessage())));
            }
        }
        return toSnapshot(preferences);
    }

    @Override
    @Transactional
    public UpdateResult update(UUID userId, ProfileUpdate profileUpdate, PreferencesUpdate preferencesUpdate) {
        // Self-invocations join this single transaction: profile and preferences commit together.
        return new UpdateResult(updateProfile(userId, profileUpdate), updatePreferences(userId, preferencesUpdate));
    }

    @Override
    @Transactional
    public ProfileSnapshot updateAvatar(UUID userId, UUID avatarAssetId) {
        UserProfileEntity profile = requireProfile(userId);
        profile.updateAvatarAsset(avatarAssetId, clock.instant());
        return toSnapshot(profile);
    }

    private UserProfileEntity requireProfile(UUID userId) {
        return profileRepository.findById(userId)
                .orElseThrow(() -> new ApiException(ApiErrorCode.API_INTERNAL_ERROR));
    }

    private UserPreferencesEntity requirePreferences(UUID userId) {
        return preferencesRepository.findById(userId)
                .orElseThrow(() -> new ApiException(ApiErrorCode.API_INTERNAL_ERROR));
    }

    private ProfileSnapshot toSnapshot(UserProfileEntity entity) {
        return new ProfileSnapshot(
                entity.getUserId(),
                entity.getUsername(),
                entity.getDisplayName(),
                entity.getAvatarAssetId(),
                entity.getCreatedAt(),
                entity.getUpdatedAt());
    }

    private PreferencesSnapshot toSnapshot(UserPreferencesEntity entity) {
        return new PreferencesSnapshot(
                entity.getUserId(),
                entity.getLocale(),
                entity.getTimezone(),
                entity.getDefaultReminderMethods().stream()
                        .map(ReminderMethod::wireValue)
                        .toList(),
                entity.getSettings(),
                entity.getCreatedAt(),
                entity.getUpdatedAt());
    }

    private static ApiFieldErrorResponse fieldError(String field, String message) {
        return new ApiFieldErrorResponse(field, ApiErrorCode.USER_PROFILE_INVALID.code(), message);
    }
}
