package com.excellentcalendar.cloud.identity.service;

/**
 * Abstraction for sending emails. The implementation uses Spring MailSender
 * in production; unit tests provide a no-op or spy variant.
 */
public interface EmailService {

    /**
     * Send an email verification code.
     */
    void sendVerificationCode(String to, String code);

    /**
     * Send a password reset token (as a code or link).
     */
    void sendPasswordResetToken(String to, String token);

    /**
     * Send a notification that the email address has been changed.
     */
    void sendEmailChangedNotification(String to, String newEmail);
}