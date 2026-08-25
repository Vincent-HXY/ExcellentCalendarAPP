package com.excellentcalendar.cloud.identity.infrastructure.security;

import com.excellentcalendar.cloud.identity.domain.UserAccountStatus;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.UserAccountEntity;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.UserAccountRepository;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.UserSessionEntity;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.UserSessionRepository;
import com.excellentcalendar.cloud.platform.api.ApiErrorCode;
import com.excellentcalendar.cloud.platform.security.AuthenticatedPrincipal;
import com.excellentcalendar.cloud.platform.security.AuthenticatedPrincipalResolver;
import com.excellentcalendar.cloud.platform.security.AuthenticatedPrincipalResolver.PrincipalResolution;
import com.excellentcalendar.cloud.platform.security.AuthenticatedPrincipalResolver.PrincipalResolution.Authenticated;
import com.excellentcalendar.cloud.platform.security.AuthenticatedPrincipalResolver.PrincipalResolution.Failed;
import java.time.Clock;
import java.util.Optional;
import java.util.UUID;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * Database-backed principal resolution: validates that the session is live and the account may
 * still act, and returns the public account snapshot used by read endpoints.
 */
@Component
public class DbAuthenticatedPrincipalResolver implements AuthenticatedPrincipalResolver {

    private final UserSessionRepository sessionRepository;
    private final UserAccountRepository accountRepository;
    private final Clock clock;

    public DbAuthenticatedPrincipalResolver(
            UserSessionRepository sessionRepository,
            UserAccountRepository accountRepository,
            Clock clock) {
        this.sessionRepository = sessionRepository;
        this.accountRepository = accountRepository;
        this.clock = clock;
    }

    @Override
    @Transactional(readOnly = true)
    public PrincipalResolution resolve(UUID accountId, UUID sessionId) {
        Optional<UserSessionEntity> session = sessionRepository.findById(sessionId);
        if (session.isEmpty() || session.get().isRevoked() || !session.get().getExpiresAt().isAfter(clock.instant())) {
            return new Failed(ApiErrorCode.AUTH_SESSION_EXPIRED);
        }
        if (!session.get().getUserId().equals(accountId)) {
            return new Failed(ApiErrorCode.AUTH_SESSION_EXPIRED);
        }
        Optional<UserAccountEntity> account = accountRepository.findById(accountId);
        if (account.isEmpty() || account.get().getStatus() == UserAccountStatus.deleted) {
            return new Failed(ApiErrorCode.AUTH_SESSION_EXPIRED);
        }
        if (account.get().getStatus() == UserAccountStatus.disabled) {
            // A disabled account's sessions are effectively dead. AUTH_SESSION_EXPIRED is the only
            // account-state failure declared by EVERY bearer endpoint's error list (notably
            // auth.logout_all does NOT declare AUTH_ACCOUNT_DISABLED), while login/refresh emit
            // AUTH_ACCOUNT_DISABLED themselves where the contract lists it.
            return new Failed(ApiErrorCode.AUTH_SESSION_EXPIRED);
        }
        if (account.get().getStatus() != UserAccountStatus.active) {
            return new Failed(ApiErrorCode.AUTH_SESSION_EXPIRED);
        }
        UserAccountEntity current = account.get();
        return new Authenticated(new AuthenticatedPrincipal(
                current.getId(),
                session.get().getId(),
                current.getEmail(),
                current.getStatus().wireValue(),
                current.getEmailVerifiedAt(),
                current.getCreatedAt(),
                current.getUpdatedAt()));
    }
}
