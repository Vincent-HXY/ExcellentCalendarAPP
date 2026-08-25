package com.excellentcalendar.cloud.platform.security;

import java.util.Collection;
import java.util.List;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.GrantedAuthority;

/**
 * Authentication token populated by {@link BearerTokenAuthenticationFilter} after both
 * cryptographic verification and database session/account resolution succeed.
 */
public class ApiAuthenticationToken implements Authentication {

    private final AuthenticatedPrincipal principal;

    public ApiAuthenticationToken(AuthenticatedPrincipal principal) {
        this.principal = principal;
    }

    @Override
    public Collection<? extends GrantedAuthority> getAuthorities() {
        return List.of();
    }

    @Override
    public Object getCredentials() {
        return null;
    }

    @Override
    public Object getDetails() {
        return null;
    }

    @Override
    public Object getPrincipal() {
        return principal;
    }

    @Override
    public boolean isAuthenticated() {
        return true;
    }

    @Override
    public void setAuthenticated(boolean isAuthenticated) throws IllegalArgumentException {
        if (!isAuthenticated) {
            throw new IllegalArgumentException("Cannot clear authentication of an ApiAuthenticationToken");
        }
    }

    @Override
    public String getName() {
        return principal.accountId().toString();
    }
}
