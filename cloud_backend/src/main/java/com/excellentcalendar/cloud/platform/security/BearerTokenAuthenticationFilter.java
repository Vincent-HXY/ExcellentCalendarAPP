package com.excellentcalendar.cloud.platform.security;

import com.excellentcalendar.cloud.platform.api.ApiErrorCode;
import com.excellentcalendar.cloud.platform.api.ApiErrorResponse;
import com.excellentcalendar.cloud.platform.api.ApiResultResponse;
import com.excellentcalendar.cloud.platform.api.ApiResultWriter;
import com.excellentcalendar.cloud.platform.api.RequestContext;
import tools.jackson.databind.ObjectMapper;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.Set;
import java.util.UUID;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtException;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Stateless bearer filter for protected API routes: verifies the JWT cryptographically, then
 * resolves account/session state through {@link AuthenticatedPrincipalResolver}. Failures are
 * written as ApiResult envelopes with the declared error codes.
 */
public class BearerTokenAuthenticationFilter extends OncePerRequestFilter {

    private static final Set<String> PUBLIC_POST_PATHS = Set.of(
            "/api/v1/auth/register",
            "/api/v1/auth/registration/verify",
            "/api/v1/auth/registration/resend",
            "/api/v1/auth/login",
            "/api/v1/auth/token/refresh",
            "/api/v1/auth/logout",
            "/api/v1/auth/password-reset/request",
            "/api/v1/auth/password-reset/confirm");

    private final AccessTokenVerifier verifier;
    private final AuthenticatedPrincipalResolver resolver;
    private final ObjectMapper objectMapper;

    public BearerTokenAuthenticationFilter(
            AccessTokenVerifier verifier,
            AuthenticatedPrincipalResolver resolver,
            ObjectMapper objectMapper) {
        this.verifier = verifier;
        this.resolver = resolver;
        this.objectMapper = objectMapper;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String path = request.getRequestURI();
        if (!path.startsWith("/api/v1/")) {
            return true;
        }
        if (HttpMethod.GET.matches(request.getMethod()) && path.startsWith("/api/v1/media/avatars")) {
            return true;
        }
        return PUBLIC_POST_PATHS.contains(path);
    }

    @Override
    protected void doFilterInternal(
            HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {
        String authorization = request.getHeader(HttpHeaders.AUTHORIZATION);
        if (authorization == null || !authorization.startsWith("Bearer ")) {
            writeFailure(response, ApiErrorCode.API_UNAUTHENTICATED);
            return;
        }
        Jwt jwt;
        try {
            jwt = verifier.verify(authorization.substring("Bearer ".length()));
        } catch (JwtException | IllegalArgumentException exception) {
            writeFailure(response, ApiErrorCode.API_UNAUTHENTICATED);
            return;
        }
        UUID accountId;
        UUID sessionId;
        try {
            accountId = UUID.fromString(jwt.getSubject());
            sessionId = UUID.fromString(jwt.getClaimAsString("sid"));
        } catch (IllegalArgumentException exception) {
            writeFailure(response, ApiErrorCode.API_UNAUTHENTICATED);
            return;
        }
        AuthenticatedPrincipalResolver.PrincipalResolution resolution = resolver.resolve(accountId, sessionId);
        switch (resolution) {
            case AuthenticatedPrincipalResolver.PrincipalResolution.Authenticated authenticated -> {
                SecurityContextHolder.getContext().setAuthentication(
                        new ApiAuthenticationToken(authenticated.principal()));
                filterChain.doFilter(request, response);
            }
            case AuthenticatedPrincipalResolver.PrincipalResolution.Failed failed ->
                    writeFailure(response, failed.code());
        }
    }

    private void writeFailure(HttpServletResponse response, ApiErrorCode code) throws IOException {
        ApiResultResponse<Void> envelope =
                ApiResultResponse.failure(ApiErrorResponse.of(code), RequestContext.requestId());
        ApiResultWriter.write(response, objectMapper, code.httpStatus(), envelope);
    }
}
