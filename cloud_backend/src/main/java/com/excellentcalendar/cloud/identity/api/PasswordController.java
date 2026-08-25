package com.excellentcalendar.cloud.identity.api;

import com.excellentcalendar.cloud.identity.application.AuthenticationResults;
import com.excellentcalendar.cloud.identity.application.PasswordService;
import com.excellentcalendar.cloud.platform.api.ApiResultResponse;
import com.excellentcalendar.cloud.platform.api.RequestContext;
import com.excellentcalendar.cloud.platform.security.AuthenticatedPrincipal;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/auth")
public class PasswordController {

    private final PasswordService passwordService;
    private final AvatarInfoResolver avatarInfoResolver;

    public PasswordController(PasswordService passwordService, AvatarInfoResolver avatarInfoResolver) {
        this.passwordService = passwordService;
        this.avatarInfoResolver = avatarInfoResolver;
    }

    @PostMapping("/password-reset/request")
    public ApiResultResponse<PasswordResetDispatchResponseDto> requestReset(
            @Valid @RequestBody PasswordResetRequestDto request, HttpServletRequest servletRequest) {
        AuthenticationResults.PasswordResetDispatch result =
                passwordService.requestReset(servletRequest.getRemoteAddr(), request.email());
        return ApiResultResponse.success(
                PasswordResetDispatchResponseDto.from(result), RequestContext.requestId());
    }

    @PostMapping("/password-reset/confirm")
    public ApiResultResponse<OperationResponseDto> confirmReset(
            @Valid @RequestBody ConfirmPasswordResetRequestDto request, HttpServletRequest servletRequest) {
        CredentialInput credential = CredentialInput.of(request.credential());
        passwordService.confirmReset(
                servletRequest.getRemoteAddr(),
                request.email(),
                credential.type(),
                credential.code(),
                request.newPassword());
        return ApiResultResponse.success(OperationResponseDto.done(), RequestContext.requestId());
    }

    @PostMapping("/password/change")
    public ApiResultResponse<AuthenticationResponseDto> change(
            @Valid @RequestBody ChangePasswordRequestDto request) {
        AuthenticatedPrincipal principal = PrincipalSupport.requirePrincipal();
        AuthenticationResults.Authentication result = passwordService.change(
                principal.accountId(),
                principal.sessionId(),
                request.currentPassword(),
                request.newPassword());
        return ApiResultResponse.success(
                AuthenticationResponseDto.from(result, avatarInfoResolver.resolve(result.currentUser().avatarAssetId())),
                RequestContext.requestId());
    }
}
