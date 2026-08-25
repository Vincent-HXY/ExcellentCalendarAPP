package com.excellentcalendar.cloud.platform.security;

import java.time.Instant;
import java.util.UUID;

/**
 * Verified snapshot of the authenticated account and session, resolved per request from the
 * database by the identity module. Carries only public profile fields of the account.
 */
public record AuthenticatedPrincipal(
        UUID accountId,
        UUID sessionId,
        String email,
        String status,
        Instant emailVerifiedAt,
        Instant createdAt,
        Instant updatedAt) {
}
