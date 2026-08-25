package com.excellentcalendar.cloud.identity.application.support;

import com.excellentcalendar.cloud.identity.application.AuthenticationResults;
import com.excellentcalendar.cloud.identity.domain.RefreshTokenGenerator;
import com.excellentcalendar.cloud.identity.domain.TokenHash;
import com.excellentcalendar.cloud.identity.infrastructure.IdentityProperties;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.RefreshTokenGrantEntity;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.RefreshTokenGrantRepository;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.UserSessionEntity;
import com.excellentcalendar.cloud.identity.infrastructure.persistence.UserSessionRepository;
import com.excellentcalendar.cloud.platform.security.JwtIssuer;
import com.excellentcalendar.cloud.platform.time.IdGenerator;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.UUID;
import org.springframework.stereotype.Component;

/**
 * Creates sessions and token pairs. Called inside the caller's transaction so the session, its
 * first grant and the returned tokens commit atomically.
 */
@Component
public class SessionIssuer {

    private final UserSessionRepository sessionRepository;
    private final RefreshTokenGrantRepository grantRepository;
    private final RefreshTokenGenerator refreshTokenGenerator;
    private final JwtIssuer jwtIssuer;
    private final IdentityProperties properties;
    private final Clock clock;
    private final IdGenerator idGenerator;

    public SessionIssuer(
            UserSessionRepository sessionRepository,
            RefreshTokenGrantRepository grantRepository,
            RefreshTokenGenerator refreshTokenGenerator,
            JwtIssuer jwtIssuer,
            IdentityProperties properties,
            Clock clock,
            IdGenerator idGenerator) {
        this.sessionRepository = sessionRepository;
        this.grantRepository = grantRepository;
        this.refreshTokenGenerator = refreshTokenGenerator;
        this.jwtIssuer = jwtIssuer;
        this.properties = properties;
        this.clock = clock;
        this.idGenerator = idGenerator;
    }

    public record IssuedSession(UserSessionEntity session, RefreshTokenGrantEntity grant, String refreshToken) {
    }

    public IssuedSession issueNewSession(UUID accountId) {
        Instant now = clock.instant();
        Duration ttl = Duration.ofSeconds(properties.getRefreshTokenTtlSeconds());
        UserSessionEntity session = new UserSessionEntity(
                idGenerator.next(), accountId, idGenerator.next(), now.plus(ttl), now);
        sessionRepository.save(session);
        return issueGrant(session, null, now, ttl);
    }

    /**
     * Rotates the grants of an existing session: revokes its current grants and issues a fresh one,
     * keeping the same session and token family.
     */
    public IssuedSession rotateSessionGrants(UserSessionEntity session) {
        Instant now = clock.instant();
        Duration ttl = Duration.ofSeconds(properties.getRefreshTokenTtlSeconds());
        session.touch(now, now.plus(ttl));
        sessionRepository.save(session);
        for (RefreshTokenGrantEntity grant : grantRepository.findBySessionId(session.getId())) {
            grant.revoke(now);
        }
        return issueGrant(session, null, now, ttl);
    }

    /**
     * Continues the rotation chain during a refresh: slides the session and issues a child grant of
     * the consumed one.
     */
    public IssuedSession issueChildGrant(UserSessionEntity session, UUID parentGrantId) {
        Instant now = clock.instant();
        Duration ttl = Duration.ofSeconds(properties.getRefreshTokenTtlSeconds());
        session.touch(now, now.plus(ttl));
        sessionRepository.save(session);
        return issueGrant(session, parentGrantId, now, ttl);
    }

    public AuthenticationResults.TokenPair tokensFor(UserSessionEntity session, IssuedSession issued) {
        JwtIssuer.IssuedAccessToken accessToken = jwtIssuer.issue(session.getUserId(), session.getId());
        return new AuthenticationResults.TokenPair(
                session.getId(),
                accessToken.tokenValue(),
                accessToken.expiresAt(),
                issued.refreshToken(),
                issued.grant().getExpiresAt());
    }

    private IssuedSession issueGrant(UserSessionEntity session, UUID parentGrantId, Instant now, Duration ttl) {
        String refreshToken = refreshTokenGenerator.generate();
        RefreshTokenGrantEntity grant = new RefreshTokenGrantEntity(
                idGenerator.next(),
                session.getId(),
                TokenHash.of(refreshToken).hex(),
                parentGrantId,
                now,
                now.plus(ttl));
        grantRepository.save(grant);
        return new IssuedSession(session, grant, refreshToken);
    }
}
