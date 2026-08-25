package com.excellentcalendar.cloud.platform.security;

import com.excellentcalendar.cloud.platform.api.ApiErrorCode;
import java.util.UUID;

/**
 * Resolves an access-token subject into a verified account/session snapshot. Implemented by the
 * identity module; the platform never touches business repositories directly.
 */
public interface AuthenticatedPrincipalResolver {

    PrincipalResolution resolve(UUID accountId, UUID sessionId);

    sealed interface PrincipalResolution {

        record Authenticated(AuthenticatedPrincipal principal) implements PrincipalResolution {
        }

        record Failed(ApiErrorCode code) implements PrincipalResolution {
        }
    }
}
