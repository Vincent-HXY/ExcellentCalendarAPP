package com.excellentcalendar.cloud.identity.infrastructure;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.excellentcalendar.cloud.identity.domain.EmailActionPurpose;
import jakarta.mail.Session;
import jakarta.mail.internet.MimeMessage;
import java.util.Properties;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.mail.MailSendException;
import org.springframework.mail.javamail.JavaMailSender;

/**
 * The SMTP adapter must build a well-formed UTF-8 message whose body is only the 6-digit code
 * (ADR-0004), and a provider failure must never propagate into the committed business flow.
 */
class SmtpMailSenderTest {

    private static final String FROM = "noreply@excellent-calendar.example";

    private static JavaMailSender mailSenderReturningRealMessage() {
        JavaMailSender javaMailSender = mock(JavaMailSender.class);
        when(javaMailSender.createMimeMessage())
                .thenAnswer(invocation -> new MimeMessage(Session.getInstance(new Properties())));
        return javaMailSender;
    }

    @Test
    void sendsAUtf8PlainTextMessageWithTheCodeOnly() throws Exception {
        JavaMailSender javaMailSender = mailSenderReturningRealMessage();
        SmtpMailSender sender = new SmtpMailSender(javaMailSender, FROM);

        sender.sendVerificationCode("user@example.com", EmailActionPurpose.registration_verification, "123456");

        MimeMessage sent = capture(javaMailSender);
        assertThat(sent.getFrom()[0].toString()).isEqualTo(FROM);
        assertThat(sent.getAllRecipients()[0].toString()).isEqualTo("user@example.com");
        assertThat(sent.getSubject()).isEqualTo("ExcellentCalendarAPP 注册验证码");
        assertThat(sent.getContent()).isEqualTo("123456");
    }

    @Test
    void subjectReflectsTheChallengePurpose() throws Exception {
        JavaMailSender javaMailSender = mailSenderReturningRealMessage();
        SmtpMailSender sender = new SmtpMailSender(javaMailSender, FROM);

        sender.sendVerificationCode("user@example.com", EmailActionPurpose.email_change, "111111");
        assertThat(capture(javaMailSender).getSubject()).isEqualTo("ExcellentCalendarAPP 修改邮箱验证码");

        sender.sendVerificationCode("user@example.com", EmailActionPurpose.password_reset, "222222");
        assertThat(capture(javaMailSender).getSubject()).isEqualTo("ExcellentCalendarAPP 密码重置验证码");
    }

    @Test
    void providerFailureIsLoggedWithoutBreakingTheCommittedFlow() {
        JavaMailSender javaMailSender = mailSenderReturningRealMessage();
        doThrow(new MailSendException("smtp down"))
                .when(javaMailSender)
                .send(any(MimeMessage.class));
        SmtpMailSender sender = new SmtpMailSender(javaMailSender, FROM);

        assertThatCode(() -> sender.sendVerificationCode(
                "user@example.com", EmailActionPurpose.password_reset, "654321"))
                .doesNotThrowAnyException();
    }

    @Test
    void masksRecipientsForLogging() {
        assertThat(SmtpMailSender.masked("user@example.com")).isEqualTo("u***r@example.com");
        assertThat(SmtpMailSender.masked("a@example.com")).isEqualTo("a***@example.com");
        // NormalizedEmail only rejects blank/overlong input, not the address shape.
        assertThat(SmtpMailSender.masked("")).isEqualTo("***");
    }

    private static MimeMessage capture(JavaMailSender javaMailSender) {
        ArgumentCaptor<MimeMessage> captor = ArgumentCaptor.forClass(MimeMessage.class);
        verify(javaMailSender, atLeastOnce()).send(captor.capture());
        var values = captor.getAllValues();
        return values.get(values.size() - 1);
    }
}
