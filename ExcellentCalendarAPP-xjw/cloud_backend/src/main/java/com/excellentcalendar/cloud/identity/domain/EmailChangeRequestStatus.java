package com.excellentcalendar.cloud.identity.domain;

/**
 * Status of an email change request.
 */
public enum EmailChangeRequestStatus {
    PENDING,
    VERIFIED,
    EXPIRED,
    CANCELLED
}