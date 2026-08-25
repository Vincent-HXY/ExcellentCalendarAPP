package com.excellentcalendar.cloud.platform.security;

import com.excellentcalendar.cloud.platform.time.IdGenerator;
import java.time.Clock;
import java.util.Base64;
import javax.crypto.SecretKey;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtEncoder;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.oauth2.jwt.NimbusJwtEncoder;

/**
 * HS256 signing key, encoder and decoder. The key is derived from
 * {@code excellent-calendar.security.jwt.secret} (Base64) and must be at least 32 bytes.
 * JWT crypto belongs to the api role only: worker/scheduler must not require a signing secret.
 */
@Profile("api")
@EnableConfigurationProperties(JwtProperties.class)
@Configuration(proxyBeanMethods = false)
public class JwtCryptoConfiguration {

    @Bean
    SecretKey jwtSigningKey(JwtProperties properties) {
        String secret = properties.getSecret();
        if (secret == null || secret.isBlank()) {
            throw new IllegalStateException(
                    "excellent-calendar.security.jwt.secret is required for the api profile");
        }
        byte[] keyBytes;
        try {
            keyBytes = Base64.getDecoder().decode(secret.trim());
        } catch (IllegalArgumentException exception) {
            throw new IllegalStateException(
                    "excellent-calendar.security.jwt.secret must be Base64 encoded", exception);
        }
        if (keyBytes.length < 32) {
            throw new IllegalStateException(
                    "excellent-calendar.security.jwt.secret must decode to at least 32 bytes for HS256");
        }
        return new SecretKeySpec(keyBytes, "HmacSHA256");
    }

    @Bean
    JwtEncoder jwtEncoder(SecretKey jwtSigningKey) {
        return NimbusJwtEncoder.withSecretKey(jwtSigningKey)
                .algorithm(MacAlgorithm.HS256)
                .build();
    }

    @Bean
    JwtDecoder jwtDecoder(SecretKey jwtSigningKey) {
        return NimbusJwtDecoder.withSecretKey(jwtSigningKey)
                .macAlgorithm(MacAlgorithm.HS256)
                .build();
    }

    @Bean
    JwtIssuer jwtIssuer(JwtEncoder jwtEncoder, JwtProperties properties, Clock clock, IdGenerator idGenerator) {
        return new JwtIssuer(jwtEncoder, properties, clock, idGenerator);
    }

    @Bean
    AccessTokenVerifier accessTokenVerifier(JwtDecoder jwtDecoder, JwtProperties properties, Clock clock) {
        return new AccessTokenVerifier(jwtDecoder, properties, clock);
    }
}
