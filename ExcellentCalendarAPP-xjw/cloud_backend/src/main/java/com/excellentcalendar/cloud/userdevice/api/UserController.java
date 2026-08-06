package com.excellentcalendar.cloud.userdevice.api;

import com.excellentcalendar.cloud.identity.application.CurrentUserResult;
import com.excellentcalendar.cloud.identity.application.GetCurrentUserUseCase;
import com.excellentcalendar.cloud.identity.application.UpdateCurrentUserUseCase;
import com.excellentcalendar.cloud.platform.api.ApiResult;
import com.excellentcalendar.cloud.platform.api.RequestIdUtils;
import com.excellentcalendar.cloud.identity.application.AvatarUploadUseCase;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import java.io.IOException;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

/**
 * Controller for current user profile and preferences endpoints.
 * Base path: /api/v1/users/me
 */
@RestController
@RequestMapping("/api/v1/users/me")
public class UserController {

    private final GetCurrentUserUseCase getCurrentUserUseCase;
    private final UpdateCurrentUserUseCase updateCurrentUserUseCase;
    private final AvatarUploadUseCase avatarUploadUseCase;

    public UserController(
            GetCurrentUserUseCase getCurrentUserUseCase,
            UpdateCurrentUserUseCase updateCurrentUserUseCase,
            AvatarUploadUseCase avatarUploadUseCase) {
        this.getCurrentUserUseCase = getCurrentUserUseCase;
        this.updateCurrentUserUseCase = updateCurrentUserUseCase;
        this.avatarUploadUseCase = avatarUploadUseCase;
    }

    /**
     * GET /api/v1/users/me
     * Get the current authenticated user's aggregate data.
     */
    @GetMapping
    ResponseEntity<ApiResult<Map<String, Object>>> getCurrentUser(
            @AuthenticationPrincipal UUID userId,
            HttpServletRequest request) {
        var result = getCurrentUserUseCase.getCurrentUser(userId);
        return ResponseEntity.ok(
                ApiResult.success(buildCurrentUserResponse(result), requestId(request)));
    }

    /**
     * PATCH /api/v1/users/me
     * Update the current user's profile and/or preferences.
     */
    @PatchMapping
    ResponseEntity<ApiResult<Map<String, Object>>> updateCurrentUser(
            @Valid @RequestBody UpdateCurrentUserRequest body,
            @AuthenticationPrincipal UUID userId,
            HttpServletRequest request) {
        var result = updateCurrentUserUseCase.updateCurrentUser(
                userId, body.username(), body.displayName(),
                body.locale(), body.timezone(),
                body.defaultReminderMethods(), body.settingsJson());
        return ResponseEntity.ok(
                ApiResult.success(buildCurrentUserResponse(result), requestId(request)));
    }

    /**
     * POST /api/v1/users/me/avatar
     * Upload an avatar image.
     * Accepts multipart/form-data with a "file" part.
     */
    @PostMapping(path = "/avatar", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    ResponseEntity<ApiResult<Map<String, Object>>> uploadAvatar(
            @RequestParam("file") MultipartFile file,
            @AuthenticationPrincipal UUID userId,
            HttpServletRequest request) {
        // Validate file presence
        if (file == null || file.isEmpty()) {
            return ResponseEntity.badRequest().body(
                    ApiResult.failureTyped("API_VALIDATION_FAILED", "No file uploaded", false,
                            null, null, requestId(request)));
        }

        // Validate MIME type
        String mimeType = file.getContentType();
        if (mimeType == null) {
            mimeType = guessMimeType(file.getOriginalFilename());
        }

        // Read file bytes
        byte[] content;
        try {
            content = file.getBytes();
        } catch (IOException e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(ApiResult.failureTyped("AVATAR_UPLOAD_FAILED",
                            "The avatar could not be stored or processed", true,
                            null, null, requestId(request)));
        }

        // Delegate to use case
        avatarUploadUseCase.uploadAvatar(userId, mimeType, content);

        // Build and return the current user response
        var currentUser = getCurrentUserUseCase.getCurrentUser(userId);
        return ResponseEntity.ok(
                ApiResult.success(buildCurrentUserResponse(currentUser), requestId(request)));
    }

    /**
     * DELETE /api/v1/users/me/avatar
     * Delete the avatar.
     */
    @DeleteMapping("/avatar")
    ResponseEntity<ApiResult<Map<String, Object>>> deleteAvatar(
            @AuthenticationPrincipal UUID userId,
            HttpServletRequest request) {
        avatarUploadUseCase.deleteAvatar(userId);
        var currentUser = getCurrentUserUseCase.getCurrentUser(userId);
        return ResponseEntity.ok(
                ApiResult.success(buildCurrentUserResponse(currentUser), requestId(request)));
    }

    // ==================== Request DTO ====================

    record UpdateCurrentUserRequest(
            String username,
            String displayName,
            String locale,
            String timezone,
            String[] defaultReminderMethods,
            String settings
    ) {
        String settingsJson() { return settings; }
    }

    // ==================== Response Builder ====================

    private static Map<String, Object> buildCurrentUserResponse(CurrentUserResult result) {
        Map<String, Object> avatar = null;
        if (result.profile().avatar() != null) {
            avatar = Map.of(
                    "asset_id", result.profile().avatar().assetId().toString(),
                    "url", result.profile().avatar().url(),
                    "thumbnail_url", result.profile().avatar().thumbnailUrl(),
                    "etag", result.profile().avatar().etag(),
                    "updated_at", result.profile().avatar().updatedAt().toString()
            );
        }

        return Map.of(
                "account", Map.of(
                        "id", result.account().id().toString(),
                        "email", result.account().email(),
                        "status", result.account().status(),
                        "email_verified_at", result.account().emailVerifiedAt() != null
                                ? result.account().emailVerifiedAt().toString() : null,
                        "created_at", result.account().createdAt().toString(),
                        "updated_at", result.account().updatedAt().toString()
                ),
                "profile", Map.of(
                        "user_id", result.profile().userId().toString(),
                        "username", result.profile().username(),
                        "display_name", result.profile().displayName(),
                        "avatar", avatar,
                        "created_at", result.profile().createdAt().toString(),
                        "updated_at", result.profile().updatedAt().toString()
                ),
                "preferences", Map.of(
                        "user_id", result.preferences().userId().toString(),
                        "locale", result.preferences().locale(),
                        "timezone", result.preferences().timezone(),
                        "default_reminder_methods", result.preferences().defaultReminderMethods() != null
                                ? List.of(result.preferences().defaultReminderMethods()) : List.of(),
                        "settings", result.preferences().settings() != null
                                ? result.preferences().settings() : Map.of("theme", "system"),
                        "created_at", result.preferences().createdAt().toString(),
                        "updated_at", result.preferences().updatedAt().toString()
                )
        );
    }

    private static String guessMimeType(String filename) {
        if (filename == null) return "application/octet-stream";
        String lower = filename.toLowerCase();
        if (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) return "image/jpeg";
        if (lower.endsWith(".png")) return "image/png";
        if (lower.endsWith(".webp")) return "image/webp";
        return "application/octet-stream";
    }

    private static String requestId(HttpServletRequest request) {
        return RequestIdUtils.getRequestId(request);
    }
}