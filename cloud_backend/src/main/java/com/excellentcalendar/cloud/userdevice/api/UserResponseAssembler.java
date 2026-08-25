package com.excellentcalendar.cloud.userdevice.api;

import com.excellentcalendar.cloud.media.application.AvatarAssetService;
import com.excellentcalendar.cloud.platform.security.AuthenticatedPrincipal;
import com.excellentcalendar.cloud.userdevice.application.ProfileService.PreferencesSnapshot;
import com.excellentcalendar.cloud.userdevice.application.ProfileService.ProfileSnapshot;
import java.util.UUID;
import org.springframework.stereotype.Component;

/**
 * Assembles CurrentUserResponseDto from the verified principal, profile/preferences snapshots and
 * an optional freshly stored avatar; falls back to the media module for existing avatars.
 */
@Component
public class UserResponseAssembler {

    private final AvatarAssetService avatarAssetService;

    public UserResponseAssembler(AvatarAssetService avatarAssetService) {
        this.avatarAssetService = avatarAssetService;
    }

    public CurrentUserResponseDto assemble(
            AuthenticatedPrincipal principal,
            ProfileSnapshot profile,
            PreferencesSnapshot preferences,
            AvatarAssetService.AvatarAssetSnapshot freshAvatar) {
        return new CurrentUserResponseDto(
                new UserAccountResponseDto(
                        principal.accountId(),
                        principal.email(),
                        principal.status(),
                        principal.emailVerifiedAt(),
                        principal.createdAt(),
                        principal.updatedAt()),
                new UserProfileResponseDto(
                        profile.userId(),
                        profile.username(),
                        profile.displayName(),
                        freshAvatar != null ? toDto(freshAvatar) : resolveAvatar(profile.avatarAssetId()),
                        profile.createdAt(),
                        profile.updatedAt()),
                new UserPreferencesResponseDto(
                        preferences.userId(),
                        preferences.locale(),
                        preferences.timezone(),
                        preferences.defaultReminderMethods(),
                        preferences.settings(),
                        preferences.createdAt(),
                        preferences.updatedAt()));
    }

    private AvatarInfoResponseDto resolveAvatar(UUID avatarAssetId) {
        if (avatarAssetId == null) {
            return null;
        }
        return avatarAssetService.findActive(avatarAssetId)
                .map(this::toDto)
                .orElse(null);
    }

    private AvatarInfoResponseDto toDto(AvatarAssetService.AvatarAssetSnapshot asset) {
        return new AvatarInfoResponseDto(
                asset.assetId(), asset.url(), asset.thumbnailUrl(), asset.etag(), asset.updatedAt());
    }
}
