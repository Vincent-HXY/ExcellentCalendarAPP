package com.excellentcalendar.cloud.media.application;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

/**
 * Public avatar-asset API of the media module. Writes are called inside the caller's transaction
 * so asset rows and the profile pointer commit atomically; blob files are written before the row
 * insert and cleaned up best-effort on rollback.
 */
public interface AvatarAssetService {

    record AvatarAssetSnapshot(UUID assetId, String url, String thumbnailUrl, String etag, Instant updatedAt) {
    }

    record StoredAsset(UUID assetId, String storageKey) {
    }

    /**
     * Writes main/thumbnail blobs and inserts the asset row; joins the caller's transaction.
     */
    StoredAsset createAsset(
            UUID accountId,
            byte[] main,
            byte[] thumbnail,
            String mimeType,
            long sizeBytes,
            int width,
            int height,
            String etag);

    Optional<AvatarAssetSnapshot> findActive(UUID assetId);

    Optional<StoredAsset> findStored(UUID assetId);

    /**
     * Soft-deletes the asset row inside the caller's transaction.
     */
    void markDeleted(UUID assetId);

    void deleteFiles(UUID assetId);

    Optional<byte[]> loadMain(String storageKey);

    Optional<byte[]> loadThumbnail(String storageKey);
}
