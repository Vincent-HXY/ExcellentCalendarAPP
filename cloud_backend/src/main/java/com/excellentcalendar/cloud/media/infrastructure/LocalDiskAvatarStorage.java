package com.excellentcalendar.cloud.media.infrastructure;

import com.excellentcalendar.cloud.media.domain.AvatarStorage;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.Optional;
import org.springframework.stereotype.Component;

/**
 * Local-disk avatar storage: atomic temp-file writes, path traversal guard, missing files read as
 * absent. Production can replace this bean with an object-storage implementation.
 */
@Component
public class LocalDiskAvatarStorage implements AvatarStorage {

    private final Path root;

    public LocalDiskAvatarStorage(MediaProperties properties) {
        this.root = properties.getDir().toAbsolutePath().normalize();
    }

    @Override
    public void write(String storageKey, byte[] content) {
        Path target = resolve(storageKey);
        try {
            Files.createDirectories(target.getParent());
            Path temp = Files.createTempFile(target.getParent(), "avatar-", ".tmp");
            Files.write(temp, content);
            Files.move(temp, target, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
        } catch (IOException exception) {
            throw new IllegalStateException("avatar storage write failed", exception);
        }
    }

    @Override
    public Optional<byte[]> read(String storageKey) {
        Path target = resolve(storageKey);
        try {
            if (!Files.isRegularFile(target)) {
                return Optional.empty();
            }
            return Optional.of(Files.readAllBytes(target));
        } catch (IOException exception) {
            return Optional.empty();
        }
    }

    @Override
    public void delete(String storageKey) {
        try {
            Files.deleteIfExists(resolve(storageKey));
        } catch (IOException ignored) {
            // Best-effort cleanup; soft-deleted assets are never served.
        }
    }

    private Path resolve(String storageKey) {
        Path candidate = root.resolve(storageKey).normalize();
        if (!candidate.startsWith(root)) {
            throw new IllegalArgumentException("invalid avatar storage key");
        }
        return candidate;
    }
}
