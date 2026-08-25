package com.excellentcalendar.cloud.platform.security;

import static org.assertj.core.api.Assertions.assertThat;

import com.excellentcalendar.cloud.platform.time.TimeConfiguration;
import javax.crypto.SecretKey;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.security.oauth2.jwt.JwtEncoder;

/**
 * JWT crypto belongs to the api role: worker/scheduler contexts must not demand a signing secret.
 */
class JwtCryptoProfileTest {

    private final ApplicationContextRunner runner = new ApplicationContextRunner()
            .withUserConfiguration(JwtCryptoConfiguration.class, TimeConfiguration.class);

    @Test
    void apiProfileWiresJwtBeans() {
        runner.withPropertyValues(
                        "spring.profiles.active=api",
                        "excellent-calendar.security.jwt.secret="
                                + "dGVzdC1vbmx5LWtleS10ZXN0LW9ubHkta2V5LXRlc3Qtb25seS1rZXktdGVzdC1vbmx5LWtleQ==")
                .run(context -> assertThat(context).hasSingleBean(JwtEncoder.class));
    }

    @Test
    void workerProfileDoesNotRequireJwtConfiguration() {
        runner.withPropertyValues("spring.profiles.active=worker")
                .run(context -> {
                    assertThat(context).doesNotHaveBean(JwtEncoder.class);
                    assertThat(context).doesNotHaveBean(SecretKey.class);
                    assertThat(context).hasNotFailed();
                });
    }

    @Test
    void schedulerProfileDoesNotRequireJwtConfiguration() {
        runner.withPropertyValues("spring.profiles.active=scheduler")
                .run(context -> {
                    assertThat(context).doesNotHaveBean(JwtEncoder.class);
                    assertThat(context).hasNotFailed();
                });
    }
}
