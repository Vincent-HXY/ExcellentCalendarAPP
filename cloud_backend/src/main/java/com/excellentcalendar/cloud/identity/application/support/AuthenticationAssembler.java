package com.excellentcalendar.cloud.identity.application.support;

import com.excellentcalendar.cloud.identity.application.AuthenticationResults;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.UserAccountEntity;
import com.excellentcalendar.cloud.platform.api.ApiErrorCode;
import com.excellentcalendar.cloud.platform.api.ApiException;
import com.excellentcalendar.cloud.userdevice.application.ProfileService;
import com.excellentcalendar.cloud.userdevice.application.ProfileService.PreferencesSnapshot;
import com.excellentcalendar.cloud.userdevice.application.ProfileService.ProfileSnapshot;
import java.util.UUID;
import org.springframework.stereotype.Component;

/**
 * Assembles the authenticated user aggregate (account + profile + preferences) for every token
 * pair response. Avatar URLs are resolved by the api layer through the media module.
 */
@Component
public class AuthenticationAssembler {

    private final ProfileService profileService;

    public AuthenticationAssembler(ProfileService profileService) {
        this.profileService = profileService;
    }

    public AuthenticationResults.Authentication assemble(
            UserAccountEntity account, AuthenticationResults.TokenPair tokens) {
        UUID userId = account.getId();
        ProfileSnapshot profile = profileService.findProfile(userId)
                .orElseThrow(() -> new ApiException(ApiErrorCode.API_INTERNAL_ERROR));
        PreferencesSnapshot preferences = profileService.findPreferences(userId)
                .orElseThrow(() -> new ApiException(ApiErrorCode.API_INTERNAL_ERROR));
        AuthenticationResults.CurrentUser currentUser = new AuthenticationResults.CurrentUser(
                account.getId(),
                account.getEmail(),
                account.getStatus().wireValue(),
                account.getEmailVerifiedAt(),
                account.getCreatedAt(),
                account.getUpdatedAt(),
                profile.userId(),
                profile.username(),
                profile.displayName(),
                profile.avatarAssetId(),
                profile.createdAt(),
                profile.updatedAt(),
                preferences.userId(),
                preferences.locale(),
                preferences.timezone(),
                preferences.defaultReminderMethods(),
                preferences.settings(),
                preferences.createdAt(),
                preferences.updatedAt());
        return new AuthenticationResults.Authentication(currentUser, tokens);
    }
}
