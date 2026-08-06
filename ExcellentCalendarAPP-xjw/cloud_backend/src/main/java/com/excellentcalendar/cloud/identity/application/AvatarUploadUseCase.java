package com.excellentcalendar.cloud.identity.application;

import com.excellentcalendar.cloud.identity.infrastructure.UserProfileEntity;
import com.excellentcalendar.cloud.identity.infrastructure.UserProfileJpaRepository;
import com.excellentcalendar.cloud.platform.api.ApiException;
import com.excellentcalendar.cloud.userdevice.infrastructure.AvatarProperties;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Clock;
import java.time.Instant;
import java.util.HexFormat;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * Use case: upload and save a user avatar image to the local filesystem.
 */
@Component
public class AvatarUploadUseCase {

    private final UserProfileJpaRepository profileJpaRepository;
    private final AvatarProperties properties;
    private final Clock clock;

    public AvatarUploadUseCase(
            UserProfileJpaRepository profileJpaRepository,
            AvatarProperties properties,
            Clock clock) {
        this.profileJpaRepository = profileJpaRepository;
        this.properties = properties;
        this.clock = clock;
    }

    /**
     * Uploads and saves an avatar image for the given user.
     *
     * @param userId     the authenticated user's UUID
     * @param mimeType   the actual MIME type of the uploaded file
     * @param content    the raw file bytes
     * @return the updated profile entity
     */
    @Transactional
    public UserProfileEntity uploadAvatar(UUID userId, String mimeType, byte[] content) {
        // Validate MIME type
        if (!properties.getAcceptedMimeTypes().contains(mimeType)) {
            throw new ApiException("AVATAR_TYPE_UNSUPPORTED",
                    "The avatar file type is unsupported", false, HttpStatus.BAD_REQUEST);
        }

        // Validate size
        if (content.length > properties.getMaxSizeBytes()) {
            throw new ApiException("AVATAR_TOO_LARGE",
                    "The avatar file exceeds the 5 MiB limit", false, HttpStatus.BAD_REQUEST);
        }

        // Determine file extension
        String extension = switch (mimeType) {
            case "image/jpeg" -> ".jpg";
            case "image/png"  -> ".png";
            case "image/webp" -> ".webp";
            default -> throw new ApiException("AVATAR_TYPE_UNSUPPORTED",
                    "The avatar file type is unsupported", false, HttpStatus.BAD_REQUEST);
        };

        // Generate a unique filename
        UUID assetId = UUID.randomUUID();
        String filename = assetId + extension;

        // Ensure upload directory exists
        Path uploadDir = properties.getUploadDir();
        try {
            Files.createDirectories(uploadDir);
        } catch (IOException e) {
            throw new ApiException("AVATAR_UPLOAD_FAILED",
                    "The avatar could not be stored or processed", true, HttpStatus.INTERNAL_SERVER_ERROR);
        }

        // Write file to disk
        Path targetFile = uploadDir.resolve(filename);
        try {
            Files.write(targetFile, content);
        } catch (IOException e) {
            throw new ApiException("AVATAR_UPLOAD_FAILED",
                    "The avatar could not be stored or processed", true, HttpStatus.INTERNAL_SERVER_ERROR);
        }

        // Compute ETag (SHA-256 of content)
        String etag = computeSha256(content);
        Instant now = clock.instant();

        // Build the URL and thumbnail URL (same file for now)
        String avatarUrl = properties.getBaseUrl() + "/" + filename;
        String thumbnailUrl = properties.getBaseUrl() + "/" + filename;

        // Update the profile record
        UserProfileEntity profile = profileJpaRepository.findByUserId(userId)
                .orElseThrow(() -> new ApiException("AUTH_SESSION_EXPIRED",
                        "The authenticated session has expired", false, HttpStatus.UNAUTHORIZED));

        // If there was a previous avatar, delete the old file
        if (profile.getAvatarAssetId() != null && profile.getAvatarUrl() != null) {
            String oldFilename = profile.getAvatarUrl().substring(
                    profile.getAvatarUrl().lastIndexOf('/') + 1);
            Path oldFile = uploadDir.resolve(oldFilename);
            try {
                Files.deleteIfExists(oldFile);
            } catch (IOException ignored) {
                // Best-effort; stale files are acceptable
            }
        }

        profile.setAvatarAssetId(assetId);
        profile.setAvatarUrl(avatarUrl);
        profile.setAvatarThumbnailUrl(thumbnailUrl);
        profile.setAvatarEtag(etag);
        profile.setAvatarUpdatedAt(now);
        profile.setUpdatedAt(now);

        return profileJpaRepository.save(profile);
    }

    /**
     * Deletes the avatar for the given user.
     *
     * @param userId the authenticated user's UUID
     * @return the updated profile entity (without avatar)
     */
    @Transactional
    public UserProfileEntity deleteAvatar(UUID userId) {
        UserProfileEntity profile = profileJpaRepository.findByUserId(userId)
                .orElseThrow(() -> new ApiException("AUTH_SESSION_EXPIRED",
                        "The authenticated session has expired", false, HttpStatus.UNAUTHORIZED));

        // Delete the old file from disk
        if (profile.getAvatarUrl() != null) {
            String oldFilename = profile.getAvatarUrl().substring(
                    profile.getAvatarUrl().lastIndexOf('/') + 1);
            Path oldFile = properties.getUploadDir().resolve(oldFilename);
            try {
                Files.deleteIfExists(oldFile);
            } catch (IOException ignored) {
                // Best-effort
            }
        }

        Instant now = clock.instant();
        profile.setAvatarAssetId(null);
        profile.setAvatarUrl(null);
        profile.setAvatarThumbnailUrl(null);
        profile.setAvatarEtag(null);
        profile.setAvatarUpdatedAt(null);
        profile.setUpdatedAt(now);

        return profileJpaRepository.save(profile);
    }

    private static String computeSha256(byte[] content) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] digest = md.digest(content);
            return HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 not available", e);
        }
    }
}