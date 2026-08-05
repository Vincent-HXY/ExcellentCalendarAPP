package com.excellentcalendar.cloud.identity.web;

import com.excellentcalendar.cloud.identity.dto.request.UpdateProfileRequest;
import com.excellentcalendar.cloud.identity.dto.response.ProfileResponse;
import com.excellentcalendar.cloud.identity.service.UserProfileService;
import jakarta.validation.Valid;
import java.util.UUID;
import org.springframework.http.MediaType;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping(path = "/api/v1/profile", produces = MediaType.APPLICATION_JSON_VALUE)
public class ProfileController {

    private final UserProfileService userProfileService;

    public ProfileController(UserProfileService userProfileService) {
        this.userProfileService = userProfileService;
    }

    @GetMapping
    public ProfileResponse getProfile(@AuthenticationPrincipal UUID userId) {
        return userProfileService.getProfile(userId);
    }

    @PatchMapping
    public ProfileResponse updateProfile(
            @AuthenticationPrincipal UUID userId,
            @Valid @RequestBody UpdateProfileRequest request) {
        return userProfileService.updateProfile(userId, request);
    }

    @PutMapping("/avatar")
    public ProfileResponse updateAvatar(
            @AuthenticationPrincipal UUID userId,
            @RequestParam String avatarUrl) {
        return userProfileService.updateAvatar(userId, avatarUrl);
    }

    @DeleteMapping("/avatar")
    public ProfileResponse deleteAvatar(@AuthenticationPrincipal UUID userId) {
        userProfileService.deleteAvatar(userId);
        return userProfileService.getProfile(userId);
    }
}