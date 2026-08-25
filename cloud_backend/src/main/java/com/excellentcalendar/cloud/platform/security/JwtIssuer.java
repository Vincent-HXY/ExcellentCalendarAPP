package com.excellentcalendar.cloud.platform.security;

import com.excellentcalendar.cloud.platform.time.IdGenerator;
import java.time.Clock;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.JwtClaimsSet;
import org.springframework.security.oauth2.jwt.JwtEncoder;
import org.springframework.security.oauth2.jwt.JwtEncoderParameters;
import org.springframework.security.oauth2.jwt.JwsHeader;

/**
 * Issues short-lived HS256 access tokens. Claims: iss, aud, sub (account id), sid (session id),
 * jti, iat, exp.
 */
public class JwtIssuer {

    private final JwtEncoder encoder;
    private final JwtProperties properties;
    private final Clock clock;
    private final IdGenerator idGenerator;

    public JwtIssuer(JwtEncoder encoder, JwtProperties properties, Clock clock, IdGenerator idGenerator) {
        this.encoder = encoder;
        this.properties = properties;
        this.clock = clock;
        this.idGenerator = idGenerator;
    }

    public IssuedAccessToken issue(UUID accountId, UUID sessionId) {
        Instant now = clock.instant();
        Instant expiresAt = now.plusSeconds(properties.getAccessTokenTtlSeconds());
        JwtClaimsSet claims = JwtClaimsSet.builder()
                .issuer(properties.getIssuer())
                .audience(List.of(properties.getAudience()))
                .subject(accountId.toString())
                .claim("sid", sessionId.toString())
                .id(idGenerator.next().toString())
                .issuedAt(now)
                .expiresAt(expiresAt)
                .build();
        JwsHeader header = JwsHeader.with(MacAlgorithm.HS256).build();
        String tokenValue = encoder.encode(JwtEncoderParameters.from(header, claims)).getTokenValue();
        return new IssuedAccessToken(tokenValue, expiresAt);
    }

    public record IssuedAccessToken(String tokenValue, Instant expiresAt) {
    }
}
