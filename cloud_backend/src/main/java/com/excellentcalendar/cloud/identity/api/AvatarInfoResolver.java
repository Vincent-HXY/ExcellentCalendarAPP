package com.excellentcalendar.cloud.identity.api;

import com.excellentcalendar.cloud.media.application.AvatarAssetService;
import com.excellentcalendar.cloud.userdevice.api.AvatarInfoResponseDto;
import java.util.UUID;
import org.springframework.stereotype.Component;

/**
 * Resolves public avatar info through the media module; null keeps the client default-avatar
 * semantics when the account has no avatar.
 */
@Component
public class AvatarInfoResolver {

    private final AvatarAssetService avatarAssetService;

    public AvatarInfoResolver(AvatarAssetService avatarAssetService) {
        this.avatarAssetService = avatarAssetService;
    }

    public AvatarInfoResponseDto resolve(UUID avatarAssetId) {
        if (avatarAssetId == null) {
            return null;
        }
        return avatarAssetService.findActive(avatarAssetId)
                .map(asset -> new AvatarInfoResponseDto(
                        asset.assetId(),
                        asset.url(),
                        asset.thumbnailUrl(),
                        asset.etag(),
                        asset.updatedAt()))
                .orElse(null);
    }
}
