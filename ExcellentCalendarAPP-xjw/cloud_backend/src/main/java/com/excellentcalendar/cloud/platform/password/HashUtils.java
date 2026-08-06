package com.excellentcalendar.cloud.platform.password;

import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;

/**
 * Hashing utilities for verification codes and tokens.
 * Never log the inputs or outputs of these methods.
 */
public final class HashUtils {

    private static final SecureRandom RANDOM = new SecureRandom();

    private HashUtils() {}

    /**
     * Computes SHA-256 hex digest.
     */
    public static String sha256(String input) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] digest = md.digest(input.getBytes());
            StringBuilder sb = new StringBuilder();
            for (byte b : digest) {
                sb.append(String.format("%02x", b));
            }
            return sb.toString();
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 not available", e);
        }
    }

    /**
     * Generates a random 6-digit code as a string.
     */
    public static String generateCode() {
        int code = 100000 + RANDOM.nextInt(900000);
        return String.valueOf(code);
    }

    /**
     * Generates a cryptographically random opaque token.
     */
    public static String generateToken() {
        byte[] bytes = new byte[32];
        RANDOM.nextBytes(bytes);
        StringBuilder sb = new StringBuilder();
        for (byte b : bytes) {
            sb.append(String.format("%02x", b));
        }
        return sb.toString();
    }

    /**
     * Masks an email for display, e.g. "u***@example.com".
     */
    public static String maskEmail(String email) {
        int atIndex = email.indexOf('@');
        if (atIndex <= 1) return email;
        return email.charAt(0) + "***" + email.substring(atIndex);
    }
}