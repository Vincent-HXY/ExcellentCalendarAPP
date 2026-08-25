package com.excellentcalendar.cloud.identity.domain;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;

/**
 * SHA-256 hex digest of a secret; used for refresh tokens and verification codes. Only the digest
 * is persisted or compared.
 */
public record TokenHash(String hex) {

    public static TokenHash of(String value) {
        return new TokenHash(sha256Hex(value));
    }

    /**
     * Constant-time comparison of two pre-computed hex digests.
     */
    public static boolean constantTimeEquals(String hexA, String hexB) {
        if (hexA == null || hexB == null) {
            return false;
        }
        return MessageDigest.isEqual(
                hexA.getBytes(StandardCharsets.US_ASCII),
                hexB.getBytes(StandardCharsets.US_ASCII));
    }

    private static String sha256Hex(String value) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(value.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 unavailable", exception);
        }
    }
}
