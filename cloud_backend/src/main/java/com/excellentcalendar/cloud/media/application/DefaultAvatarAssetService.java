package com.excellentcalendar.cloud.media.application;

import com.excellentcalendar.cloud.media.domain.AvatarStorage;
import com.excellentcalendar.cloud.media.infrastructure.MediaProperties;
import com.excellentcalendar.cloud.media.infrastructure.persistence.UserAvatarAssetEntity;
import com.excellentcalendar.cloud.media.infrastructure.persistence.UserAvatarAssetRepository;
import com.excellentcalendar.cloud.platform.time.IdGenerator;
import java.time.Clock;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class DefaultAvatarAssetService implements AvatarAssetService {

    public static final String SERVING_PATH = "/api/v1/media/avatars/";

    private final UserAvatarAssetRepository repository;
    private final AvatarStorage storage;
    private final MediaProperties properties;
    private final Clock clock;
    private final IdGenerator idGenerator;

    public DefaultAvatarAssetService(
            UserAvatarAssetRepository repository,
            AvatarStorage storage,
            MediaProperties properties,
            Clock clock,
            IdGenerator idGenerator) {
        this.repository = repository;
        this.storage = storage;
        this.properties = properties;
        this.clock = clock;
        this.idGenerator = idGenerator;
    }

    @Override
    @Transactional
    public StoredAsset createAsset(
            UUID accountId,
            byte[] main,
            byte[] thumbnail,
            String mimeType,
            long sizeBytes,
            int width,
            int height,
            String etag) {
        UUID assetId = idGenerator.next();
        String mainKey = assetId + ".jpg";
        String thumbnailKey = assetId + ".thumb.jpg";
        storage.write(mainKey, main);
        storage.write(thumbnailKey, thumbnail);
        try {
            repository.save(new UserAvatarAssetEntity(
                    assetId, accountId, mainKey, mimeType, sizeBytes, width, height, etag, clock.instant()));
        } catch (RuntimeException exception) {
            storage.delete(mainKey);
            storage.delete(thumbnailKey);
            throw exception;
        }
        return new StoredAsset(assetId, mainKey);
    }

    @Override
    @Transactional(readOnly = true)
    public Optional<AvatarAssetSnapshot> findActive(UUID assetId) {
        return repository.findById(assetId)
                .filter(asset -> !asset.isDeleted())
                .map(this::toSnapshot);
    }

    @Override
    @Transactional(readOnly = true)
    public Optional<StoredAsset> findStored(UUID assetId) {
        return repository.findById(assetId)
                .filter(asset -> !asset.isDeleted())
                .map(asset -> new StoredAsset(asset.getId(), asset.getStorageKey()));
    }

    @Override
    @Transactional
    public void markDeleted(UUID assetId) {
        repository.findById(assetId).ifPresent(asset -> asset.markDeleted(clock.instant()));
    }

    @Override
    public void deleteFiles(UUID assetId) {
        repository.findById(assetId).ifPresent(asset -> {
            storage.delete(asset.getStorageKey());
            storage.delete(thumbnailKeyOf(asset.getStorageKey()));
        });
    }

    @Override
    public Optional<byte[]> loadMain(String storageKey) {
        return storage.read(storageKey);
    }

    @Override
    public Optional<byte[]> loadThumbnail(String storageKey) {
        return storage.read(thumbnailKeyOf(storageKey));
    }

    private AvatarAssetSnapshot toSnapshot(UserAvatarAssetEntity asset) {
        String base = properties.getBaseUrl() + SERVING_PATH + asset.getId();
        return new AvatarAssetSnapshot(
                asset.getId(),
                base,
                base + "/thumbnail",
                asset.getEtag(),
                asset.getCreatedAt());
    }

    private static String thumbnailKeyOf(String storageKey) {
        return storageKey.replaceFirst("\\.jpg$", ".thumb.jpg");
    }
}
