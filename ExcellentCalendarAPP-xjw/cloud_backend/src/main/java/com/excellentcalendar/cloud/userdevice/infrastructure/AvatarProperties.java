package com.excellentcalendar.cloud.userdevice.infrastructure;

import java.nio.file.Path;
import java.util.List;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

/**
 * Avatar upload configuration properties.
 */
@Validated
@ConfigurationProperties("excellent-calendar.avatar")
public class AvatarProperties {

    /** Directory where uploaded avatars are stored. */
    private Path uploadDir = Path.of("/data/avatars");

    /** Maximum file size in bytes (default: 5 MiB). */
    private long maxSizeBytes = 5 * 1024 * 1024;

    /** Accepted MIME types. */
    private List<String> acceptedMimeTypes = List.of("image/jpeg", "image/png", "image/webp");

    /** Base URL for serving avatar files. */
    private String baseUrl = "http://localhost:8080/avatars";

    public Path getUploadDir() { return uploadDir; }
    public void setUploadDir(Path uploadDir) { this.uploadDir = uploadDir; }

    public long getMaxSizeBytes() { return maxSizeBytes; }
    public void setMaxSizeBytes(long maxSizeBytes) { this.maxSizeBytes = maxSizeBytes; }

    public List<String> getAcceptedMimeTypes() { return List.copyOf(acceptedMimeTypes); }
    public void setAcceptedMimeTypes(List<String> acceptedMimeTypes) { this.acceptedMimeTypes = List.copyOf(acceptedMimeTypes); }

    public String getBaseUrl() { return baseUrl; }
    public void setBaseUrl(String baseUrl) { this.baseUrl = baseUrl; }
}