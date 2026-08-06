package com.excellentcalendar.cloud.platform.mail;

import java.time.Instant;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.stereotype.Component;

/**
 * No-op email sender used when no profile-specific implementation is active.
 * Logs a warning that email sending is not configured.
 */
@Component
@ConditionalOnMissingBean(EmailSender.class)
public class NoopEmailSender implements EmailSender {

    private static final Logger LOGGER = LoggerFactory.getLogger(NoopEmailSender.class);

    @Override
    public void sendVerificationCode(String to, String code, Instant expiresAt) {
        LOGGER.warn("Email not sent: verification code for {} (code={}). No email sender configured.", to, code);
    }

    @Override
    public void sendPasswordResetCode(String to, String code, Instant expiresAt) {
        LOGGER.warn("Email not sent: password reset code for {} (code={}). No email sender configured.", to, code);
    }

    @Override
    public void sendEmailChangedNotification(String to) {
        LOGGER.warn("Email not sent: email changed notification for {}. No email sender configured.", to);
    }
}