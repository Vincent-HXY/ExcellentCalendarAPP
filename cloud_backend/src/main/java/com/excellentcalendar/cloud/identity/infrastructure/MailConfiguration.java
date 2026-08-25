package com.excellentcalendar.cloud.identity.infrastructure;

import com.excellentcalendar.cloud.identity.domain.MailSender;
import java.util.Properties;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.mail.javamail.JavaMailSenderImpl;

/**
 * Exactly one {@link MailSender} bean per environment, chosen in a fixed priority:
 *
 * <ol>
 *   <li>{@code excellent-calendar.mail.host} is set → {@link SmtpMailSender} (any profile);</li>
 *   <li>{@code dev}/{@code local} → {@link ConsoleMailSender} (codes on the console as the
 *       integration inbox);</li>
 *   <li>otherwise → {@link UnconfiguredMailSender} (code-free warning, so verification codes can
 *       never reach production logs).</li>
 * </ol>
 */
@Configuration(proxyBeanMethods = false)
@EnableConfigurationProperties(MailSendingProperties.class)
public class MailConfiguration {

    @Bean
    MailSender mailSender(MailSendingProperties properties, Environment environment) {
        if (properties.getHost() != null && !properties.getHost().isBlank()) {
            validateComplete(properties);
            String from = properties.getFrom() != null && !properties.getFrom().isBlank()
                    ? properties.getFrom()
                    : properties.getUsername();
            return new SmtpMailSender(smtpSender(properties), from);
        }
        if (environment.acceptsProfiles(Profiles.of("dev | local"))) {
            return new ConsoleMailSender();
        }
        return new UnconfiguredMailSender();
    }

    /**
     * Fail fast with a clear message instead of a cryptic provider error at the first send.
     */
    private static void validateComplete(MailSendingProperties properties) {
        if (properties.getUsername() == null || properties.getUsername().isBlank()) {
            throw new IllegalStateException("excellent-calendar.mail.host is set but "
                    + "excellent-calendar.mail.username is empty; "
                    + "set EXCELLENT_CALENDAR_MAIL_USERNAME");
        }
        if (properties.getPassword() == null || properties.getPassword().isBlank()) {
            throw new IllegalStateException("excellent-calendar.mail.host is set but "
                    + "excellent-calendar.mail.password is empty; "
                    + "set EXCELLENT_CALENDAR_MAIL_PASSWORD");
        }
    }

    /**
     * Provider-agnostic SMTP client: explicit auth, STARTTLS or implicit SSL, and bounded
     * connect/read/write timeouts so a dead provider cannot stall the after-commit send.
     */
    private static JavaMailSenderImpl smtpSender(MailSendingProperties properties) {
        JavaMailSenderImpl sender = new JavaMailSenderImpl();
        sender.setHost(properties.getHost());
        sender.setPort(properties.getPort());
        sender.setUsername(properties.getUsername());
        sender.setPassword(properties.getPassword());
        sender.setProtocol("smtp");
        sender.setDefaultEncoding("UTF-8");
        Properties mailProperties = new Properties();
        mailProperties.put("mail.smtp.auth", "true");
        if (properties.isSsl()) {
            mailProperties.put("mail.smtp.ssl.enable", "true");
            mailProperties.put("mail.smtp.starttls.enable", "false");
        } else {
            mailProperties.put("mail.smtp.ssl.enable", "false");
            mailProperties.put("mail.smtp.starttls.enable", Boolean.toString(properties.isStartTls()));
            mailProperties.put("mail.smtp.starttls.required", Boolean.toString(properties.isStartTls()));
        }
        mailProperties.put("mail.smtp.connectiontimeout",
                String.valueOf(properties.getConnectionTimeoutMs()));
        mailProperties.put("mail.smtp.timeout", String.valueOf(properties.getTimeoutMs()));
        mailProperties.put("mail.smtp.writetimeout", String.valueOf(properties.getWriteTimeoutMs()));
        sender.setJavaMailProperties(mailProperties);
        return sender;
    }
}
