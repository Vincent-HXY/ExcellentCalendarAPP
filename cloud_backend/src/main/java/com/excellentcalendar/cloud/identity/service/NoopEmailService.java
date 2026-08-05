package com.excellentcalendar.cloud.identity.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

/**
 * No-op email service used when {@code excellent-calendar.identity.mail-enabled}
 * is explicitly set to {@code false}. Useful for development or testing without
 * a configured SMTP server.
 */
@Service
@ConditionalOnProperty(value = "excellent-calendar.identity.mail-enabled", havingValue = "false")
public class NoopEmailService implements EmailService {

    private static final Logger log = LoggerFactory.getLogger(NoopEmailService.class);

    @Override
    public void sendVerificationCode(String to, String code) {
        log.info("[NOOP] Verification code for {}: {}", to, code);
    }

    @Override
    public void sendPasswordResetToken(String to, String token) {
        log.info("[NOOP] Password reset token for {}: {}", to, token);
    }

    @Override
    public void sendEmailChangedNotification(String to, String newEmail) {
        log.info("[NOOP] Email changed notification for {}: new email {}", to, newEmail);
    }
}