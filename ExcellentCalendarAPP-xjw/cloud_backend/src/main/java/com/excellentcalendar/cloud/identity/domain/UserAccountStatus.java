package com.excellentcalendar.cloud.identity.domain;

/**
 * Account lifecycle status.
 * Maps to the {@code UserAccountStatus} enum in {@code contracts/enums.yaml}.
 */
public enum UserAccountStatus {
    PENDING_VERIFICATION,
    ACTIVE,
    DISABLED,
    DELETED
}