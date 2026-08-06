package com.excellentcalendar.cloud.platform.security;

import java.util.UUID;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;

/**
 * Simple authentication principal holding the authenticated user's UUID.
 */
public class UserPrincipal implements Authentication {

    private final UUID userId;
    private final UUID sessionId;
    private boolean authenticated = true;

    public UserPrincipal(UUID userId, UUID sessionId) {
        this.userId = userId;
        this.sessionId = sessionId;
    }

    public UUID getUserId() { return userId; }
    public UUID getSessionId() { return sessionId; }

    @Override
    public Object getPrincipal() { return userId; }

    @Override
    public Object getCredentials() { return null; }

    @Override
    public Object getDetails() { return null; }

    @Override
    public boolean isAuthenticated() { return authenticated; }

    @Override
    public void setAuthenticated(boolean isAuthenticated) throws IllegalArgumentException {
        this.authenticated = isAuthenticated;
    }

    @Override
    public String getName() { return userId.toString(); }

    @Override
    public java.util.Collection<? extends GrantedAuthority> getAuthorities() {
        return java.util.List.of(new SimpleGrantedAuthority("ROLE_USER"));
    }
}