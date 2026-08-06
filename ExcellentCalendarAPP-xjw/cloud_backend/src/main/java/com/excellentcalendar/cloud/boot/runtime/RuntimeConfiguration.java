package com.excellentcalendar.cloud.boot.runtime;

import java.util.Arrays;
import java.util.List;
import java.util.Locale;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;

@Configuration(proxyBeanMethods = false)
@EnableConfigurationProperties(RuntimeProperties.class)
class RuntimeConfiguration {

    private static final Logger LOGGER = LoggerFactory.getLogger(RuntimeConfiguration.class);

    @Bean
    ApplicationRunner runtimeRoleGuard(RuntimeProperties properties, Environment environment) {
        return arguments -> {
            validateSelectedProfile(properties.getRole(), environment);
            LOGGER.info("Cloud backend runtime role: {}", properties.getRole());
        };
    }

    static void validateSelectedProfile(RuntimeRole configuredRole, Environment environment) {
        List<String> selectedRoles = Arrays.stream(RuntimeRole.values())
                .map(role -> role.name().toLowerCase(Locale.ROOT))
                .filter(profile -> environment.acceptsProfiles(Profiles.of(profile)))
                .toList();
        String expectedProfile = configuredRole.name().toLowerCase(Locale.ROOT);

        if (selectedRoles.size() != 1 || !selectedRoles.contains(expectedProfile)) {
            throw new IllegalStateException(
                    "Exactly one runtime profile (api, worker, scheduler) must be active and match "
                            + "excellent-calendar.runtime.role. Selected=" + selectedRoles
                            + ", configured=" + configuredRole);
        }
    }
}
