package com.excellentcalendar.cloud.identity.infrastructure;

import static org.assertj.core.api.Assertions.assertThat;

import com.excellentcalendar.cloud.identity.domain.MailSender;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;

/**
 * The console inbox (which logs verification codes) must only exist in dev/local; every other
 * profile gets the code-free fallback so verification codes can never reach production logs.
 */
class MailConfigurationTest {

    private final ApplicationContextRunner runner = new ApplicationContextRunner()
            .withUserConfiguration(MailConfiguration.class);

    @Test
    void productionApiProfileNeverExposesVerificationCodeLogging() {
        runner.withPropertyValues("spring.profiles.active=api").run(context -> {
            assertThat(context).hasSingleBean(MailSender.class);
            assertThat(context.getBean(MailSender.class)).isInstanceOf(UnconfiguredMailSender.class);
            assertThat(context).doesNotHaveBean(ConsoleMailSender.class);
        });
    }

    @Test
    void localProfileUsesTheConsoleInbox() {
        runner.withPropertyValues("spring.profiles.active=api,local").run(context -> {
            assertThat(context).hasSingleBean(MailSender.class);
            assertThat(context.getBean(MailSender.class)).isInstanceOf(ConsoleMailSender.class);
            assertThat(context).doesNotHaveBean(UnconfiguredMailSender.class);
        });
    }

    @Test
    void devProfileUsesTheConsoleInbox() {
        runner.withPropertyValues("spring.profiles.active=dev").run(context -> {
            assertThat(context).hasSingleBean(MailSender.class);
            assertThat(context.getBean(MailSender.class)).isInstanceOf(ConsoleMailSender.class);
        });
    }

    @Test
    void configuredSmtpWinsInEveryProfileIncludingLocal() {
        runner.withPropertyValues(
                        "spring.profiles.active=api,local",
                        "excellent-calendar.mail.host=smtp.example.com",
                        "excellent-calendar.mail.username=alerts@example.com",
                        "excellent-calendar.mail.password=s3cret")
                .run(context -> {
                    assertThat(context).hasSingleBean(MailSender.class);
                    assertThat(context.getBean(MailSender.class)).isInstanceOf(SmtpMailSender.class);
                    assertThat(context).doesNotHaveBean(ConsoleMailSender.class);
                    assertThat(context).doesNotHaveBean(UnconfiguredMailSender.class);
                });
    }

    @Test
    void configuredSmtpIsAvailableInTheProductionApiProfile() {
        runner.withPropertyValues(
                        "spring.profiles.active=api",
                        "excellent-calendar.mail.host=smtp.example.com",
                        "excellent-calendar.mail.username=alerts@example.com",
                        "excellent-calendar.mail.password=s3cret")
                .run(context -> {
                    assertThat(context).hasSingleBean(MailSender.class);
                    assertThat(context.getBean(MailSender.class)).isInstanceOf(SmtpMailSender.class);
                });
    }

    @Test
    void smtpHostWithoutCredentialsFailsFastWithAClearMessage() {
        runner.withPropertyValues(
                        "spring.profiles.active=api",
                        "excellent-calendar.mail.host=smtp.example.com")
                .run(context -> assertThat(context)
                        .getFailure()
                        .hasMessageContaining("excellent-calendar.mail.username"));
    }

    @Test
    void smtpHostWithoutPasswordFailsFastWithAClearMessage() {
        runner.withPropertyValues(
                        "spring.profiles.active=api",
                        "excellent-calendar.mail.host=smtp.example.com",
                        "excellent-calendar.mail.username=alerts@example.com")
                .run(context -> assertThat(context)
                        .getFailure()
                        .hasMessageContaining("excellent-calendar.mail.password"));
    }
}
