package com.excellentcalendar.cloud.userdevice.web;

import com.excellentcalendar.cloud.userdevice.dto.request.UpdateProfileRequest;
import com.excellentcalendar.cloud.userdevice.dto.response.UserProfileResponse;
import com.excellentcalendar.cloud.userdevice.service.UserProfileService;
import jakarta.validation.Valid;
import java.util.UUID;
import org.springframework.http.MediaType;
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

@RestController
@RequestMapping(path = "/api/v1/users/me", produces = MediaType.APPLICATION_JSON_VALUE)
public class UserProfileController {

    private final UserProfileService userProfileService;

    public UserProfileController(UserProfileService userProfileService) {
        this.userProfileService = userProfileService;
    }

    @GetMapping
    public UserProfileResponse getProfile(@AuthenticationPrincipal UUID userId) {
        return userProfileService.getProfile(userId);
    }

    @PatchMapping
    public UserProfileResponse updateProfile(
            @AuthenticationPrincipal UUID userId,
            @Valid @RequestBody UpdateProfileRequest request) {
        return userProfileService.updateProfile(userId, request);
    }

    @PostMapping(value = "/avatar", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public UserProfileResponse uploadAvatar(
            @AuthenticationPrincipal UUID userId,
            @RequestParam("file") MultipartFile file) {
        return userProfileService.uploadAvatar(userId, file);
    }

    @DeleteMapping("/avatar")
    public UserProfileResponse deleteAvatar(@AuthenticationPrincipal UUID userId) {
        return userProfileService.deleteAvatar(userId);
    }
}