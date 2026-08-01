package com.excellentcalendar.cloud;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.file.Path;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.boot.env.YamlPropertySourceLoader;
import org.springframework.core.env.PropertySource;
import org.springframework.core.io.ClassPathResource;
import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.Resource;

class ConfigurationFilesTest {

    private final YamlPropertySourceLoader loader = new YamlPropertySourceLoader();

    @Test
    void runtimeProfilesDeclareDistinctRoles() throws IOException {
        assertThat(property("application-api.yml", "excellent-calendar.runtime.role")).isEqualTo("api");
        assertThat(property("application-worker.yml", "excellent-calendar.runtime.role")).isEqualTo("worker");
        assertThat(property("application-scheduler.yml", "excellent-calendar.runtime.role"))
                .isEqualTo("scheduler");
    }

    @Test
    void composeFileKeepsApplicationOptionalAndPostgresqlExplicit() throws IOException {
        Resource resource = new FileSystemResource(Path.of("compose.yaml"));
        List<PropertySource<?>> sources = loader.load("compose", resource);

        assertThat(read(sources, "services.postgres.image")).isEqualTo("postgres:17-alpine");
        assertThat(read(sources, "services.api.profiles[0]")).isEqualTo("app");
    }

    private Object property(String resourceName, String key) throws IOException {
        return read(loader.load(resourceName, new ClassPathResource(resourceName)), key);
    }

    private Object read(List<PropertySource<?>> sources, String key) {
        return sources.stream()
                .map(source -> source.getProperty(key))
                .filter(value -> value != null)
                .findFirst()
                .orElse(null);
    }
}
