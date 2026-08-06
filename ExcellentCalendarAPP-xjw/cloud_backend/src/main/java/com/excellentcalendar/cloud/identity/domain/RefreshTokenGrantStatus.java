package com.excellentcalendar.cloud.identity.domain;

/**
 * Lifecycle status of a refresh token grant.
 */
public enum RefreshTokenGrantStatus {
    ACTIVE,
    CONSUMED,
    REVOKED,
    EXPIRED
}