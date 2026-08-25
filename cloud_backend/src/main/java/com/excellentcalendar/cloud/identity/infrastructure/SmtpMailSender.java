package com.excellentcalendar.cloud.identity.infrastructure;

import com.excellentcalendar.cloud.identity.domain.EmailActionPurpose;
import com.excellentcalendar.cloud.identity.domain.MailSender;
import com.excellentcalendar.cloud.identity.domain.NormalizedEmail;
import jakarta.mail.MessagingException;
import jakarta.mail.internet.MimeMessage;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.mail.MailException;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.javamail.MimeMessageHelper;

/**
 * SMTP adapter for the {@link MailSender} port. Runs after the surrounding business transaction
 * commits (see {@code ChallengeSupport}), so a rolled-back registration never emails anyone.
 * Delivery is best-effort: a provider failure is logged without the verification code, the
 * recipient address or credentials, and the committed challenge stays resendable through its
 * resend endpoint — an SMTP outage never fails the already-committed flow.
 */
public class SmtpMailSender implements MailSender {

    private static final Logger log = LoggerFactory.getLogger("mail");

    private final JavaMailSender mailSender;
    private final String from;

    public SmtpMailSender(JavaMailSender mailSender, String from) {
        this.mailSender = mailSender;
        this.from = from;
    }

    @Override
    public void sendVerificationCode(String to, EmailActionPurpose purpose, String code) {
        try {
            MimeMessage message = mailSender.createMimeMessage();
            MimeMessageHelper helper = new MimeMessageHelper(message, "UTF-8");
            helper.setFrom(from);
            helper.setTo(to);
            helper.setSubject(subject(purpose));
            // ADR-0004: the body contains only the 6-digit code in this phase (no link tokens).
            helper.setText(code, false);
            mailSender.send(message);
            log.info("[mail] verification email sent to={} purpose={}",
                    masked(to), purpose.wireValue());
        } catch (MailException | MessagingException e) {
            log.warn("[mail] verification email delivery failed to={} purpose={}; "
                    + "the challenge remains resendable", masked(to), purpose.wireValue(), e);
        }
    }

    private static String subject(EmailActionPurpose purpose) {
        return switch (purpose) {
            case registration_verification -> "ExcellentCalendarAPP 注册验证码";
            case email_change -> "ExcellentCalendarAPP 修改邮箱验证码";
            case password_reset -> "ExcellentCalendarAPP 密码重置验证码";
        };
    }

    static String masked(String email) {
        try {
            return NormalizedEmail.of(email).masked();
        } catch (IllegalArgumentException e) {
            return "***";
        }
    }
}
