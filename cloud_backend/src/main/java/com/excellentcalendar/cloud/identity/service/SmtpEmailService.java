package com.excellentcalendar.cloud.identity.service;

import com.excellentcalendar.cloud.identity.config.IdentityProperties;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.stereotype.Service;

@Service
@ConditionalOnProperty(value = "excellent-calendar.identity.mail-enabled", havingValue = "true", matchIfMissing = true)
public class SmtpEmailService implements EmailService {

    private static final Logger log = LoggerFactory.getLogger(SmtpEmailService.class);

    private final JavaMailSender mailSender;
    private final IdentityProperties properties;

    public SmtpEmailService(JavaMailSender mailSender, IdentityProperties properties) {
        this.mailSender = mailSender;
        this.properties = properties;
    }

    @Override
    public void sendVerificationCode(String to, String code) {
        SimpleMailMessage message = new SimpleMailMessage();
        message.setFrom(properties.getMailFrom());
        message.setTo(to);
        message.setSubject("Verify your email address");
        message.setText("""
                Your email verification code is: %s

                This code will expire in %d minutes.

                If you did not create an account, please ignore this email.
                """
                .formatted(code, properties.getVerificationCodeExpiration().toMinutes()));
        mailSender.send(message);
        log.info("Verification code sent to {}", to);
    }

    @Override
    public void sendPasswordResetToken(String to, String token) {
        SimpleMailMessage message = new SimpleMailMessage();
        message.setFrom(properties.getMailFrom());
        message.setTo(to);
        message.setSubject("Reset your password");
        message.setText("""
                Your password reset code is: %s

                This code will expire in %d minutes.

                If you did not request a password reset, please ignore this email.
                """
                .formatted(token, properties.getPasswordResetExpiration().toMinutes()));
        mailSender.send(message);
        log.info("Password reset token sent to {}", to);
    }

    @Override
    public void sendEmailChangedNotification(String to, String newEmail) {
        SimpleMailMessage message = new SimpleMailMessage();
        message.setFrom(properties.getMailFrom());
        message.setTo(to);
        message.setSubject("Email address changed");
        message.setText("""
                Your email address has been changed to: %s

                If you did not make this change, please contact support immediately.
                """
                .formatted(newEmail));
        mailSender.send(message);
        log.info("Email change notification sent to {}", to);
    }
}