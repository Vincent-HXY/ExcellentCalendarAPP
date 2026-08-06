package com.excellentcalendar.cloud.identity.application;

import com.excellentcalendar.cloud.identity.domain.UserAccount;
import com.excellentcalendar.cloud.identity.domain.UserAccountRepository;
import com.excellentcalendar.cloud.identity.infrastructure.UserProfileEntity;
import com.excellentcalendar.cloud.identity.infrastructure.UserProfileJpaRepository;
import com.excellentcalendar.cloud.identity.infrastructure.UserPreferencesEntity;
import com.excellentcalendar.cloud.identity.infrastructure.UserPreferencesJpaRepository;
import com.excellentcalendar.cloud.platform.password.AuthErrors;
import java.util.Map;
import java.util.UUID;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * Use case: get the current authenticated user's aggregate data.
 */
@Component
public class GetCurrentUserUseCase {

    private final UserAccountRepository userAccountRepository;
    private final UserProfileJpaRepository profileJpaRepository;
    private final UserPreferencesJpaRepository preferencesJpaRepository;

    public GetCurrentUserUseCase(
            UserAccountRepository userAccountRepository,
            UserProfileJpaRepository profileJpaRepository,
            UserPreferencesJpaRepository preferencesJpaRepository) {
        this.userAccountRepository = userAccountRepository;
        this.profileJpaRepository = profileJpaRepository;
        this.preferencesJpaRepository = preferencesJpaRepository;
    }

    @Transactional(readOnly = true)
    public CurrentUserResult getCurrentUser(UUID userId) {
        UserAccount account = userAccountRepository.findById(userId)
                .orElseThrow(AuthErrors::sessionExpired);

        UserProfileEntity profile = profileJpaRepository.findByUserId(userId)
                .orElse(null);

        UserPreferencesEntity prefs = preferencesJpaRepository.findByUserId(userId)
                .orElse(null);

        CurrentUserResult.AvatarInfo avatar = null;
        if (profile != null && profile.getAvatarAssetId() != null) {
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
                        userId,
                        profile != null ? profile.getUsername() : "",
                        profile != null ? profile.getDisplayName() : "",
                        avatar,
                        profile != null ? profile.getCreatedAt() : account.getCreatedAt(),
                        profile != null ? profile.getUpdatedAt() : account.getUpdatedAt()),
                new CurrentUserResult.PreferencesInfo(
                        userId,
                        prefs != null ? prefs.getLocale() : "en-US",
                        prefs != null ? prefs.getTimezone() : "UTC",
                        prefs != null ? prefs.getDefaultReminderMethods() : new String[]{"popup"},
                        Map.of("theme", "system"),
                        prefs != null ? prefs.getCreatedAt() : account.getCreatedAt(),
                        prefs != null ? prefs.getUpdatedAt() : account.getUpdatedAt()));
    }
}