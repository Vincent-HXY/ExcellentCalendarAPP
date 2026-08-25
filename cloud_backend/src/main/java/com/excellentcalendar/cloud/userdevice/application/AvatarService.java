package com.excellentcalendar.cloud.userdevice.application;

import com.excellentcalendar.cloud.media.application.AvatarAssetService;
import com.excellentcalendar.cloud.media.application.AvatarImageProcessor;
import com.excellentcalendar.cloud.platform.api.ApiErrorCode;
import com.excellentcalendar.cloud.platform.api.ApiException;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * Avatar upload/delete use case: the profile pointer and the asset row commit in one transaction;
 * blob cleanup is best-effort. A failed upload always keeps the previous avatar.
 */
@Service
public class AvatarService {

    private final AvatarAssetService assetService;
    private final ProfileService profileService;

    public AvatarService(AvatarAssetService assetService, ProfileService profileService) {
        this.assetService = assetService;
        this.profileService = profileService;
    }

    public record UploadResult(AvatarAssetService.AvatarAssetSnapshot asset, ProfileService.ProfileSnapshot profile) {
    }

    @Transactional
    public UploadResult upload(UUID accountId, byte[] raw) {
        AvatarImageProcessor.ProcessedImage processed;
        try {
            processed = AvatarImageProcessor.process(raw);
        } catch (AvatarImageProcessor.UnsupportedImageTypeException exception) {
            throw new ApiException(ApiErrorCode.AVATAR_TYPE_UNSUPPORTED);
        } catch (AvatarImageProcessor.ImageTooLargeException exception) {
            throw new ApiException(ApiErrorCode.AVATAR_TOO_LARGE);
        } catch (AvatarImageProcessor.ImageProcessingException exception) {
            throw new ApiException(ApiErrorCode.AVATAR_UPLOAD_FAILED);
        }

        ProfileService.ProfileSnapshot current = profileService.findProfile(accountId).orElseThrow();
        UUID previousAssetId = current.avatarAssetId();
        AvatarAssetService.StoredAsset stored = assetService.createAsset(
                accountId,
                processed.main(),
                processed.thumbnail(),
                AvatarImageProcessor.OUTPUT_MIME_TYPE,
                raw.length,
                processed.width(),
                processed.height(),
                processed.etag());
        try {
            if (previousAssetId != null) {
                assetService.markDeleted(previousAssetId);
            }
            ProfileService.ProfileSnapshot updated = profileService.updateAvatar(accountId, stored.assetId());
            afterCommit(() -> {
                if (previousAssetId != null) {
                    assetService.deleteFiles(previousAssetId);
                }
            });
            AvatarAssetService.AvatarAssetSnapshot snapshot =
                    assetService.findActive(stored.assetId()).orElseThrow();
            return new UploadResult(snapshot, updated);
        } catch (RuntimeException exception) {
            assetService.deleteFiles(stored.assetId());
            throw exception;
        }
    }

    @Transactional
    public ProfileService.ProfileSnapshot delete(UUID accountId) {
        ProfileService.ProfileSnapshot current = profileService.findProfile(accountId).orElseThrow();
        UUID previousAssetId = current.avatarAssetId();
        if (previousAssetId == null) {
            return current;
        }
        assetService.markDeleted(previousAssetId);
        ProfileService.ProfileSnapshot updated = profileService.updateAvatar(accountId, null);
        afterCommit(() -> assetService.deleteFiles(previousAssetId));
        return updated;
    }

    private void afterCommit(Runnable action) {
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCommit() {
                    action.run();
                }
            });
        } else {
            action.run();
        }
    }
}
