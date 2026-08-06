package com.excellentcalendar.cloud.platform.security;

import com.excellentcalendar.cloud.platform.jwt.JwtTokenService;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.time.Clock;
import org.springframework.context.annotation.Profile;
import org.springframework.core.annotation.Order;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Extracts and validates the JWT access token from the Authorization header.
 * If valid, sets the {@link UserPrincipal} in the security context.
 */
@Component
@Profile("api")
@Order(2)
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private static final String AUTHORIZATION_HEADER = "Authorization";
    private static final String BEARER_PREFIX = "Bearer ";

    private final JwtTokenService jwtTokenService;
    private final Clock clock;

    public JwtAuthenticationFilter(JwtTokenService jwtTokenService, Clock clock) {
        this.jwtTokenService = jwtTokenService;
        this.clock = clock;
    }

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain) throws ServletException, IOException {

        String authHeader = request.getHeader(AUTHORIZATION_HEADER);
        if (authHeader != null && authHeader.startsWith(BEARER_PREFIX)) {
            String token = authHeader.substring(BEARER_PREFIX.length()).trim();
            JwtTokenService.ParsedToken parsed = jwtTokenService.parseAccessToken(token);

            if (parsed != null && !parsed.isExpired(clock)) {
                UserPrincipal principal = new UserPrincipal(parsed.userId(), parsed.sessionId());
                SecurityContextHolder.getContext().setAuthentication(principal);
            }
        }

        filterChain.doFilter(request, response);
    }
}