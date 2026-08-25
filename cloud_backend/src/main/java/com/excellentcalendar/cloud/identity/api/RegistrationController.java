package com.excellentcalendar.cloud.identity.api;

import com.excellentcalendar.cloud.identity.application.AuthenticationResults;
import com.excellentcalendar.cloud.identity.application.RegistrationService;
import com.excellentcalendar.cloud.platform.api.ApiResultResponse;
import com.excellentcalendar.cloud.platform.api.RequestContext;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/auth")
public class RegistrationController {

    private final RegistrationService registrationService;
    private final AvatarInfoResolver avatarInfoResolver;

    public RegistrationController(RegistrationService registrationService, AvatarInfoResolver avatarInfoResolver) {
        this.registrationService = registrationService;
        this.avatarInfoResolver = avatarInfoResolver;
    }

    @PostMapping("/register")
    public ApiResultResponse<RegistrationPendingResponseDto> register(
            @Valid @RequestBody RegisterRequestDto request, HttpServletRequest servletRequest) {
        AuthenticationResults.RegistrationPending result = registrationService.register(
                servletRequest.getRemoteAddr(),
                request.email(),
                request.username(),
                request.displayName(),
                request.password(),
                request.locale(),
                request.timezone(),
                request.agreementVersion());
        return ApiResultResponse.success(
                RegistrationPendingResponseDto.from(result), RequestContext.requestId());
    }

    @PostMapping("/registration/resend")
    public ApiResultResponse<EmailChallengeResponseDto> resend(
            @Valid @RequestBody ResendRegistrationRequestDto request, HttpServletRequest servletRequest) {
        AuthenticationResults.Challenge result =
                registrationService.resend(servletRequest.getRemoteAddr(), request.challengeId());
        return ApiResultResponse.success(EmailChallengeResponseDto.from(result), RequestContext.requestId());
    }

    @PostMapping("/registration/verify")
    public ApiResultResponse<AuthenticationResponseDto> verify(
            @Valid @RequestBody VerifyRegistrationRequestDto request, HttpServletRequest servletRequest) {
        CredentialInput credential = CredentialInput.of(request.credential());
        AuthenticationResults.Authentication result = registrationService.verify(
                servletRequest.getRemoteAddr(),
                request.challengeId(),
                credential.type(),
                credential.code());
        return ApiResultResponse.success(
                AuthenticationResponseDto.from(result, avatarInfoResolver.resolve(result.currentUser().avatarAssetId())),
                RequestContext.requestId());
    }
}
