package com.excellentcalendar.cloud.identity.service;

import com.excellentcalendar.cloud.identity.config.IdentityProperties;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.Jwts;
import java.time.Duration;
import java.time.Instant;
import java.util.Date;
import java.util.UUID;
import org.springframework.stereotype.Component;

@Component
public class JwtTokenProvider {

    private final IdentityProperties properties;

    public JwtTokenProvider(IdentityProperties properties) {
        this.properties = properties;
    }

    public String createAccessToken(UUID userId) {
        return createToken(userId, properties.getAccessTokenExpiration());
    }

    public String createRefreshToken(UUID userId) {
        return createToken(userId, properties.getRefreshTokenExpiration());
    }

    public boolean validateToken(String token) {
        try {
            Jwts.parser()
                    .verifyWith(properties.jwtSecretKey())
                    .build()
                    .parseSignedClaims(token);
            return true;
        } catch (JwtException | IllegalArgumentException e) {
            return false;
        }
    }

    public UUID getUserIdFromToken(String token) {
        Claims claims = Jwts.parser()
                .verifyWith(properties.jwtSecretKey())
                .build()
                .parseSignedClaims(token)
                .getPayload();
        return UUID.fromString(claims.getSubject());
    }

    public Instant getExpirationFromToken(String token) {
        Claims claims = Jwts.parser()
                .verifyWith(properties.jwtSecretKey())
                .build()
                .parseSignedClaims(token)
                .getPayload();
        return claims.getExpiration().toInstant();
    }

    private String createToken(UUID userId, Duration expiration) {
        Instant now = Instant.now();
        return Jwts.builder()
                .subject(userId.toString())
                .issuedAt(Date.from(now))
                .expiration(Date.from(now.plus(expiration)))
                .signWith(properties.jwtSecretKey())
                .compact();
    }
}