package com.excellentcalendar.cloud.platform.mail;

import jakarta.annotation.Nullable;
import java.time.Instant;
import java.util.UUID;

/**
 * Public interface for sending email messages.
 * <p>
 * The initial implementation uses MailDev for local development.
 * Production implementations should use SendGrid, AWS SES, or similar.
 */
public interface EmailSender {

    /**
     * Sends a verification code email.
     *
     * @param to      recipient email address
     * @param code    the 6-digit verification code
     * @param expiresAt when the code expires
     */
    void sendVerificationCode(String to, String code, Instant expiresAt);

    /**
     * Sends a password reset email with a verification code.
     *
     * @param to      recipient email address
     * @param code    the 6-digit verification code
     * @param expiresAt when the code expires
     */
    void sendPasswordResetCode(String to, String code, Instant expiresAt);

    /**
     * Sends a notification that the email address has been changed.
     *
     * @param to the old email address
     */
    void sendEmailChangedNotification(String to);
}