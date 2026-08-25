package com.excellentcalendar.cloud.identity.api;

import com.excellentcalendar.cloud.platform.api.ApiErrorCode;
import com.excellentcalendar.cloud.platform.api.ApiException;
import com.excellentcalendar.cloud.platform.security.ApiAuthenticationToken;
import com.excellentcalendar.cloud.platform.security.AuthenticatedPrincipal;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;

/**
 * Reads the verified principal set by the bearer filter; bearer endpoints never trust body
 * identity fields.
 */
public final class PrincipalSupport {

    private PrincipalSupport() {
    }

    public static AuthenticatedPrincipal requirePrincipal() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication instanceof ApiAuthenticationToken token
                && token.getPrincipal() instanceof AuthenticatedPrincipal principal) {
            return principal;
        }
        throw new ApiException(ApiErrorCode.API_UNAUTHENTICATED);
    }
}
