package com.excellentcalendar.cloud.media.domain;

import java.util.Optional;

/**
 * Port for avatar blob storage. The local-disk implementation uses atomic temp-file moves; keys are
 * server-generated ({assetId}.jpg / {assetId}.thumb.jpg) and never exposed through the API.
 */
public interface AvatarStorage {

    /**
     * Atomically writes the blob (creates missing directories, replaces existing content).
     */
    void write(String storageKey, byte[] content);

    Optional<byte[]> read(String storageKey);

    void delete(String storageKey);
}
