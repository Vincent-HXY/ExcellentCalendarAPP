package com.excellentcalendar.cloud.identity.domain;

/**
 * Port for generating opaque refresh tokens (32 random bytes, Base64 URL, no padding).
 */
@FunctionalInterface
public interface RefreshTokenGenerator {

    String generate();
}
