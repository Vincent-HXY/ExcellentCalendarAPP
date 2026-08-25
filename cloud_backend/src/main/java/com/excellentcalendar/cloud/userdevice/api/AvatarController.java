package com.excellentcalendar.cloud.userdevice.api;

import com.excellentcalendar.cloud.platform.api.ApiResultResponse;
import com.excellentcalendar.cloud.platform.api.RequestContext;
import com.excellentcalendar.cloud.platform.security.AuthenticatedPrincipal;
import com.excellentcalendar.cloud.userdevice.application.AvatarService;
import com.excellentcalendar.cloud.userdevice.application.ProfileService;
import com.excellentcalendar.cloud.userdevice.application.ProfileService.PreferencesSnapshot;
import com.excellentcalendar.cloud.userdevice.application.ProfileService.ProfileSnapshot;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.MediaType;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

@RestController
@RequestMapping("/api/v1/users/me/avatar")
public class AvatarController {

    private final AvatarService avatarService;
    private final ProfileService profileService;
    private final UserResponseAssembler assembler;

    public AvatarController(
            AvatarService avatarService, ProfileService profileService, UserResponseAssembler assembler) {
        this.avatarService = avatarService;
        this.profileService = profileService;
        this.assembler = assembler;
    }

    @PostMapping(consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ApiResultResponse<CurrentUserResponseDto> upload(
            @RequestParam("file") MultipartFile file, HttpServletRequest request) throws Exception {
        AuthenticatedPrincipal principal = requirePrincipal();
        AvatarService.UploadResult result = avatarService.upload(principal.accountId(), file.getBytes());
        PreferencesSnapshot preferences = requirePreferences(principal);
        return ApiResultResponse.success(
                assembler.assemble(principal, result.profile(), preferences, result.asset()),
                RequestContext.requestId());
    }

    @DeleteMapping
    public ApiResultResponse<CurrentUserResponseDto> delete() {
        AuthenticatedPrincipal principal = requirePrincipal();
        ProfileSnapshot profile = avatarService.delete(principal.accountId());
        PreferencesSnapshot preferences = requirePreferences(principal);
        return ApiResultResponse.success(
                assembler.assemble(principal, profile, preferences, null), RequestContext.requestId());
    }

    private PreferencesSnapshot requirePreferences(AuthenticatedPrincipal principal) {
        return profileService.findPreferences(principal.accountId()).orElseThrow();
    }

    private static AuthenticatedPrincipal requirePrincipal() {
        Object value = SecurityContextHolder.getContext().getAuthentication().getPrincipal();
        if (value instanceof AuthenticatedPrincipal principal) {
            return principal;
        }
        throw new IllegalStateException("no authenticated principal");
    }
}
