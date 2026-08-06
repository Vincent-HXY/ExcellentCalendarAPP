package com.excellentcalendar.cloud.userdevice.service;

import com.excellentcalendar.cloud.userdevice.dto.request.UpdateProfileRequest;
import com.excellentcalendar.cloud.userdevice.dto.response.UserProfileResponse;
import com.excellentcalendar.cloud.userdevice.model.UserProfile;
import com.excellentcalendar.cloud.userdevice.repository.UserProfileRepository;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

@Service
@Transactional
public class UserProfileService {

    private static final Logger log = LoggerFactory.getLogger(UserProfileService.class);

    private static final long MAX_FILE_SIZE = 5 * 1024 * 1024; // 5MB
    private static final List<String> ALLOWED_MIME_TYPES = List.of(
            "image/jpeg", "image/png", "image/webp");
    private static final List<byte[]> MAGIC_BYTES = List.of(
            new byte[]{(byte) 0xFF, (byte) 0xD8, (byte) 0xFF}, // JPEG
            new byte[]{(byte) 0x89, 'P', 'N', 'G'},           // PNG
            new byte[]{'R', 'I', 'F', 'F'}                     // WebP (RIFF....WEBP)
    );

    private final UserProfileRepository profileRepository;

    public UserProfileService(UserProfileRepository profileRepository) {
        this.profileRepository = profileRepository;
    }

    @Transactional(readOnly = true)
    public UserProfileResponse getProfile(UUID userId) {
        UserProfile profile = profileRepository.findById(userId)
                .orElse(null);
        if (profile == null) {
            // Lazily create a default profile if one doesn't exist.
            // This can happen when the identity module registered the user
            // before the userdevice module was deployed.
            profile = createDefaultProfile(userId);
        }
        return toResponse(profile);
    }

    public UserProfileResponse updateProfile(UUID userId, UpdateProfileRequest request) {
        UserProfile profile = getOrCreateProfile(userId);

        boolean changed = false;

        if (request.displayName() != null && !request.displayName().isBlank()
                && !request.displayName().equals(profile.getDisplayName())) {
            profile.setDisplayName(request.displayName().trim());
            changed = true;
        }

        if (request.username() != null && !request.username().isBlank()
                && !request.username().equals(profile.getUsername())) {
            if (profileRepository.existsByUsernameIgnoreCase(request.username())) {
                throw new UserDeviceException.UsernameAlreadyTaken("Username is already taken");
            }
            profile.setUsername(request.username().trim());
            changed = true;
        }

        if (request.language() != null && !request.language().isBlank()
                && !request.language().equals(profile.getLanguage())) {
            profile.setLanguage(request.language().trim());
            changed = true;
        }

        if (request.timezone() != null && !request.timezone().isBlank()
                && !request.timezone().equals(profile.getTimezone())) {
            profile.setTimezone(request.timezone().trim());
            changed = true;
        }

        if (changed) {
            profile.setUpdatedAt(Instant.now());
            profile = profileRepository.save(profile);
        }

        return toResponse(profile);
    }

    public UserProfileResponse uploadAvatar(UUID userId, MultipartFile file) {
        UserProfile profile = getOrCreateProfile(userId);

        // Validate file size
        if (file.getSize() > MAX_FILE_SIZE) {
            throw new UserDeviceException.FileTooLarge("File size exceeds 5MB limit");
        }

        // Validate MIME type
        String contentType = file.getContentType();
        if (contentType == null || !ALLOWED_MIME_TYPES.contains(contentType)) {
            throw new UserDeviceException.InvalidFileType(
                    "Invalid file type. Allowed: JPEG, PNG, WebP");
        }

        // Validate magic bytes
        try (InputStream in = file.getInputStream()) {
            byte[] header = new byte[8];
            int read = in.read(header);
            if (read < 4 || !isValidMagicBytes(header)) {
                throw new UserDeviceException.InvalidFileType(
                        "File content does not match the declared type");
            }
        } catch (IOException e) {
            throw new RuntimeException("Failed to read uploaded file", e);
        }

        // Determine file extension
        String extension = switch (contentType) {
            case "image/jpeg" -> ".jpg";
            case "image/png" -> ".png";
            case "image/webp" -> ".webp";
            default -> throw new UserDeviceException.InvalidFileType("Unsupported file type");
        };

        // Save to local filesystem
        try {
            Path uploadDir = Path.of("uploads", "avatars");
            Files.createDirectories(uploadDir);

            // Remove old avatar if exists
            if (profile.getAvatarPath() != null) {
                Path oldFile = Path.of(profile.getAvatarPath());
                Files.deleteIfExists(oldFile);
            }

            String filename = userId + extension;
            Path targetPath = uploadDir.resolve(filename);
            Files.copy(file.getInputStream(), targetPath, StandardCopyOption.REPLACE_EXISTING);

            profile.setAvatarPath(targetPath.toString());
            profile.setUpdatedAt(Instant.now());
            profile = profileRepository.save(profile);

            log.info("Avatar uploaded for user: id={}, path={}", userId, targetPath);

        } catch (IOException e) {
            throw new RuntimeException("Failed to save avatar file", e);
        }

        return toResponse(profile);
    }

    public UserProfileResponse deleteAvatar(UUID userId) {
        UserProfile profile = getOrCreateProfile(userId);

        if (profile.getAvatarPath() != null) {
            try {
                Path oldFile = Path.of(profile.getAvatarPath());
                Files.deleteIfExists(oldFile);
            } catch (IOException e) {
                log.warn("Failed to delete old avatar file: {}", profile.getAvatarPath(), e);
            }
            profile.setAvatarPath(null);
            profile.setUpdatedAt(Instant.now());
            profile = profileRepository.save(profile);
        }

        return toResponse(profile);
    }

    /**
     * Create a default profile for a user. If a profile already exists this is a no-op.
     */
    public UserProfile createDefaultProfile(UUID userId) {
        if (profileRepository.existsById(userId)) {
            return profileRepository.findById(userId).orElseThrow();
        }
        // Generate a random display name and username
        String suffix = Integer.toHexString(userId.hashCode()).substring(0, 6);
        String displayName = "User" + suffix;
        String username = "user" + suffix;

        Instant now = Instant.now();
        UserProfile profile = new UserProfile(userId, displayName, username, now);
        profile = profileRepository.save(profile);
        log.info("Default profile created for user: id={}", userId);
        return profile;
    }

    private UserProfile getOrCreateProfile(UUID userId) {
        return profileRepository.findById(userId)
                .orElseGet(() -> createDefaultProfile(userId));
    }

    private boolean isValidMagicBytes(byte[] header) {
        for (byte[] magic : MAGIC_BYTES) {
            boolean match = true;
            for (int i = 0; i < magic.length; i++) {
                if (i >= header.length || header[i] != magic[i]) {
                    match = false;
                    break;
                }
            }
            if (match) {
                return true;
            }
        }
        return false;
    }

    private UserProfileResponse toResponse(UserProfile profile) {
        return new UserProfileResponse(
                profile.getUserId(),
                profile.getDisplayName(),
                profile.getUsername(),
                profile.getAvatarPath(),
                profile.getLanguage(),
                profile.getTimezone());
    }
}