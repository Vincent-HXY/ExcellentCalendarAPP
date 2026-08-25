package com.excellentcalendar.cloud.identity.api;

import com.excellentcalendar.cloud.identity.application.AuthenticationResults;
import com.excellentcalendar.cloud.identity.application.EmailChangeService;
import com.excellentcalendar.cloud.platform.api.ApiResultResponse;
import com.excellentcalendar.cloud.platform.api.RequestContext;
import com.excellentcalendar.cloud.platform.security.AuthenticatedPrincipal;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/auth/email-change")
public class EmailChangeController {

    private final EmailChangeService emailChangeService;
    private final AvatarInfoResolver avatarInfoResolver;

    public EmailChangeController(EmailChangeService emailChangeService, AvatarInfoResolver avatarInfoResolver) {
        this.emailChangeService = emailChangeService;
        this.avatarInfoResolver = avatarInfoResolver;
    }

    @PostMapping("/request")
    public ApiResultResponse<EmailChallengeResponseDto> request(
            @Valid @RequestBody RequestEmailChangeRequestDto request) {
        AuthenticatedPrincipal principal = PrincipalSupport.requirePrincipal();
        AuthenticationResults.Challenge result = emailChangeService.requestChange(
                principal.accountId(), request.newEmail(), request.currentPassword());
        return ApiResultResponse.success(EmailChallengeResponseDto.from(result), RequestContext.requestId());
    }

    @PostMapping("/confirm")
    public ApiResultResponse<AuthenticationResponseDto> confirm(
            @Valid @RequestBody ConfirmEmailChangeRequestDto request) {
        AuthenticatedPrincipal principal = PrincipalSupport.requirePrincipal();
        CredentialInput credential = CredentialInput.of(request.credential());
        AuthenticationResults.Authentication result = emailChangeService.confirmChange(
                principal.accountId(),
                principal.sessionId(),
                request.emailChangeRequestId(),
                credential.type(),
                credential.code());
        return ApiResultResponse.success(
                AuthenticationResponseDto.from(result, avatarInfoResolver.resolve(result.currentUser().avatarAssetId())),
                RequestContext.requestId());
    }
}
