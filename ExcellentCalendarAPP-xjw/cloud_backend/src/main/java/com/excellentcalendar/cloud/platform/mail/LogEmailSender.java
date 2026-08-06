package com.excellentcalendar.cloud.platform.mail;

import java.time.Instant;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Primary;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

/**
 * Log-based email sender for local development.
 * Prints the email content to the log — never use this in production.
 */
@Component
@Profile("local")
@Primary
public class LogEmailSender implements EmailSender {

    private static final Logger LOGGER = LoggerFactory.getLogger(LogEmailSender.class);

    @Override
    public void sendVerificationCode(String to, String code, Instant expiresAt) {
        LOGGER.info("=== EMAIL (verification code) ===");
        LOGGER.info("To: {}", to);
        LOGGER.info("Code: {}", code);
        LOGGER.info("Expires at: {}", expiresAt);
        LOGGER.info("=================================");
    }

    @Override
    public void sendPasswordResetCode(String to, String code, Instant expiresAt) {
        LOGGER.info("=== EMAIL (password reset) ===");
        LOGGER.info("To: {}", to);
        LOGGER.info("Code: {}", code);
        LOGGER.info("Expires at: {}", expiresAt);
        LOGGER.info("================================");
    }

    @Override
    public void sendEmailChangedNotification(String to) {
        LOGGER.info("=== EMAIL (email changed) ===");
        LOGGER.info("To: {}", to);
        LOGGER.info("Your email address has been changed.");
        LOGGER.info("==============================");
    }
}