package com.excellentcalendar.cloud;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.modulith.core.ApplicationModules;

class ModuleArchitectureTest {

    private static final List<String> EXPECTED_MODULES = List.of(
            "admin",
            "ai",
            "backup",
            "boot",
            "calendar",
            "datedmessage",
            "holiday",
            "identity",
            "media",
            "notification",
            "platform",
            "reminder",
            "search",
            "sync",
            "userdevice");

    private final ApplicationModules modules = ApplicationModules.of(CloudBackendApplication.class);

    @Test
    void moduleDependenciesRespectModularMonolithBoundaries() {
        modules.verify();
    }

    @Test
    void plannedModuleBoundariesRemainVisible() {
        for (String expectedModule : EXPECTED_MODULES) {
            assertThat(modules.getModuleByName(expectedModule))
                    .as("module %s", expectedModule)
                    .isPresent();
        }
    }
}
