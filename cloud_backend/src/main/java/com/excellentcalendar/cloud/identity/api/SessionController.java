package com.excellentcalendar.cloud.identity.api;

import com.excellentcalendar.cloud.identity.application.AuthenticationResults;
import com.excellentcalendar.cloud.identity.application.SessionService;
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
public class SessionController {

    private final SessionService sessionService;
    private final AvatarInfoResolver avatarInfoResolver;

    public SessionController(SessionService sessionService, AvatarInfoResolver avatarInfoResolver) {
        this.sessionService = sessionService;
        this.avatarInfoResolver = avatarInfoResolver;
    }

    @PostMapping("/login")
    public ApiResultResponse<AuthenticationResponseDto> login(
            @Valid @RequestBody LoginRequestDto request, HttpServletRequest servletRequest) {
        AuthenticationResults.Authentication result = sessionService.login(
                servletRequest.getRemoteAddr(), request.email(), request.password());
        return ApiResultResponse.success(
                AuthenticationResponseDto.from(result, avatarInfoResolver.resolve(result.currentUser().avatarAssetId())),
                RequestContext.requestId());
    }

    @PostMapping("/token/refresh")
    public ApiResultResponse<TokenPairResponseDto> refresh(
            @Valid @RequestBody RefreshSessionRequestDto request) {
        AuthenticationResults.TokenPair tokens = sessionService.refresh(request.refreshToken());
        return ApiResultResponse.success(TokenPairResponseDto.from(tokens), RequestContext.requestId());
    }

    @PostMapping("/logout")
    public ApiResultResponse<OperationResponseDto> logout(@Valid @RequestBody LogoutRequestDto request) {
        return ApiResultResponse.success(
                OperationResponseDto.of(sessionService.logout(request.refreshToken())),
                RequestContext.requestId());
    }

    @PostMapping("/logout-all")
    public ApiResultResponse<OperationResponseDto> logoutAll() {
        sessionService.logoutAll(PrincipalSupport.requirePrincipal().accountId());
        return ApiResultResponse.success(OperationResponseDto.done(), RequestContext.requestId());
    }
}
