package com.excellentcalendar.cloud.identity.application;

import com.excellentcalendar.cloud.identity.domain.UserAccountRepository;
import com.excellentcalendar.cloud.identity.infrastructure.UserProfileEntity;
import com.excellentcalendar.cloud.identity.infrastructure.UserProfileJpaRepository;
import com.excellentcalendar.cloud.identity.infrastructure.UserPreferencesEntity;
import com.excellentcalendar.cloud.identity.infrastructure.UserPreferencesJpaRepository;
import com.excellentcalendar.cloud.platform.password.AuthErrors;
import java.time.Clock;
import java.util.Map;
import java.util.UUID;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * Use case: update the current user's profile and/or preferences.
 */
@Component
public class UpdateCurrentUserUseCase {

    private final UserAccountRepository userAccountRepository;
    private final UserProfileJpaRepository profileJpaRepository;
    private final UserPreferencesJpaRepository preferencesJpaRepository;
    private final Clock clock;

    public UpdateCurrentUserUseCase(
            UserAccountRepository userAccountRepository,
            UserProfileJpaRepository profileJpaRepository,
            UserPreferencesJpaRepository preferencesJpaRepository,
            Clock clock) {
        this.userAccountRepository = userAccountRepository;
        this.profileJpaRepository = profileJpaRepository;
        this.preferencesJpaRepository = preferencesJpaRepository;
        this.clock = clock;
    }

    @Transactional
    public CurrentUserResult updateCurrentUser(
            UUID userId,
            String username, String displayName,
            String locale, String timezone,
            String[] defaultReminderMethods, String settingsJson) {

        // Verify account exists and is active
        var account = userAccountRepository.findById(userId)
                .orElseThrow(AuthErrors::sessionExpired);

        if (account.isDisabled()) {
            throw AuthErrors.accountDisabled();
        }

        // Update profile
        var profile = profileJpaRepository.findByUserId(userId).orElse(null);
        if (profile == null) {
            profile = new UserProfileEntity();
            profile.setUserId(userId);
            profile.setCreatedAt(clock.instant());
        }

        boolean profileChanged = false;
        if (username != null) {
            // Check unique username
            if (profileJpaRepository.existsByUsernameIgnoreCase(username)
                    && !username.equals(profile.getUsername())) {
                throw AuthErrors.usernameAlreadyExists();
            }
            profile.setUsername(username);
            profileChanged = true;
        }
        if (displayName != null) {
            profile.setDisplayName(displayName);
            profileChanged = true;
        }
        if (profileChanged) {
            profile.setUpdatedAt(clock.instant());
            profileJpaRepository.save(profile);
        }

        // Update preferences
        var prefs = preferencesJpaRepository.findByUserId(userId).orElse(null);
        if (prefs == null) {
            prefs = new UserPreferencesEntity();
            prefs.setUserId(userId);
            prefs.setCreatedAt(clock.instant());
        }

        boolean prefsChanged = false;
        if (locale != null) { prefs.setLocale(locale); prefsChanged = true; }
        if (timezone != null) { prefs.setTimezone(timezone); prefsChanged = true; }
        if (defaultReminderMethods != null) { prefs.setDefaultReminderMethods(defaultReminderMethods); prefsChanged = true; }
        if (settingsJson != null) { prefs.setSettings(settingsJson); prefsChanged = true; }
        if (prefsChanged) {
            prefs.setUpdatedAt(clock.instant());
            preferencesJpaRepository.save(prefs);
        }

        // Build and return the updated result
        CurrentUserResult.AvatarInfo avatar = null;
        if (profile.getAvatarAssetId() != null) {
            avatar = new CurrentUserResult.AvatarInfo(
                    profile.getAvatarAssetId(), profile.getAvatarUrl(),
                    profile.getAvatarThumbnailUrl(), profile.getAvatarEtag(),
                    profile.getAvatarUpdatedAt());
        }

        return new CurrentUserResult(
                new CurrentUserResult.AccountInfo(
                        account.getId(), account.getEmail(),
                        account.getStatus().name(),
                        account.getEmailVerifiedAt(),
                        account.getCreatedAt(), account.getUpdatedAt()),
                new CurrentUserResult.ProfileInfo(
                        userId, profile.getUsername(), profile.getDisplayName(),
                        avatar, profile.getCreatedAt(), profile.getUpdatedAt()),
                new CurrentUserResult.PreferencesInfo(
                        userId,
                        prefs.getLocale() != null ? prefs.getLocale() : "en-US",
                        prefs.getTimezone() != null ? prefs.getTimezone() : "UTC",
                        prefs.getDefaultReminderMethods() != null ? prefs.getDefaultReminderMethods() : new String[]{"popup"},
                        Map.of("theme", "system"),
                        prefs.getCreatedAt() != null ? prefs.getCreatedAt() : clock.instant(),
                        prefs.getUpdatedAt() != null ? prefs.getUpdatedAt() : clock.instant()));
    }
}