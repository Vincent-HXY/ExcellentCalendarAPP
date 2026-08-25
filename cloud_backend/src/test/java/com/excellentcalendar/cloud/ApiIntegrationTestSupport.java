package com.excellentcalendar.cloud;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.ContextConfiguration;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.utility.DockerImageName;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

/**
 * Shared integration-test context: one PostgreSQL 17.11 container and one Spring context serve all
 * flow tests (identical inherited configuration keeps the context cache warm across classes).
 * HTTP is driven by the JDK HttpClient against the random server port. Without a Docker daemon the
 * whole class hierarchy is skipped instead of failing the build.
 */
@ActiveProfiles("api")
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ContextConfiguration(classes = {CloudBackendApplication.class, MailCaptureConfiguration.class})
@Testcontainers(disabledWithoutDocker = true)
public abstract class ApiIntegrationTestSupport {

    protected static final String BASE = "/api/v1";

    /**
     * Deliberately NOT a JUnit {@code @Container}: the extension would stop the shared container
     * after the first test class and kill the cached context's connection pool. The container is
     * started lazily (idempotently) from {@link #datasourceProperties}, which only runs while a
     * context is prepared after the Docker-availability check passed.
     */
    protected static final PostgreSQLContainer<?> POSTGRESQL = new PostgreSQLContainer<>(
            DockerImageName.parse("postgres:17.11-alpine"))
            .withDatabaseName("excellent_calendar_test")
            .withUsername("excellent_calendar_test")
            .withPassword("test-only-password")
            .withEnv("TZ", "UTC")
            .withEnv("PGTZ", "UTC");

    @DynamicPropertySource
    static void datasourceProperties(DynamicPropertyRegistry registry) {
        POSTGRESQL.start();
        registry.add("spring.datasource.url", POSTGRESQL::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRESQL::getUsername);
        registry.add("spring.datasource.password", POSTGRESQL::getPassword);
    }

    @LocalServerPort
    protected int port;

    @Autowired
    protected ObjectMapper objectMapper;

    @Autowired
    protected MailCaptureConfiguration.CapturingMailSender mailSender;

    @Autowired
    protected org.springframework.jdbc.core.JdbcTemplate jdbcTemplate;

    private final HttpClient client = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10))
            .build();

    public record ApiResponse(int status, JsonNode body, Map<String, List<String>> headers) {

        public String header(String name) {
            List<String> values = headers.get(name.toLowerCase());
            return values == null || values.isEmpty() ? null : values.get(0);
        }
    }

    protected ApiResponse postJson(String path, String body, String... headers) {
        return send("POST", path, body, "application/json", headers);
    }

    protected ApiResponse patchJson(String path, String body, String... headers) {
        return send("PATCH", path, body, "application/json", headers);
    }

    protected ApiResponse deleteJson(String path, String... headers) {
        return send("DELETE", path, null, null, headers);
    }

    protected ApiResponse getJson(String path, String... headers) {
        return send("GET", path, null, null, headers);
    }

    public record RawResponse(int status, byte[] body, Map<String, List<String>> headers) {
    }

    /**
     * Raw byte GET for the internal avatar serving path (non-JSON responses).
     */
    protected RawResponse getRaw(String path, String... headers) {
        try {
            HttpRequest.Builder builder = HttpRequest.newBuilder()
                    .uri(URI.create("http://localhost:" + port + BASE + path))
                    .timeout(Duration.ofSeconds(30));
            for (int i = 0; i + 1 < headers.length; i += 2) {
                builder.header(headers[i], headers[i + 1]);
            }
            HttpResponse<byte[]> response = client.send(
                    builder.GET().build(), HttpResponse.BodyHandlers.ofByteArray());
            return new RawResponse(response.statusCode(), response.body(), new LinkedHashMap<>(response.headers().map()));
        } catch (Exception exception) {
            throw new IllegalStateException("HTTP GET failed: " + path, exception);
        }
    }

    protected ApiResponse postMultipart(
            String path, Map<String, byte[]> parts, Map<String, String> partContentTypes, String... headers) {
        String boundary = "----excellent-calendar-" + UUID.randomUUID();
        java.io.ByteArrayOutputStream output = new java.io.ByteArrayOutputStream();
        try {
            for (Map.Entry<String, byte[]> part : parts.entrySet()) {
                String name = part.getKey();
                String contentType = partContentTypes.getOrDefault(name, "application/octet-stream");
                output.write(("--" + boundary + "\r\n").getBytes(StandardCharsets.UTF_8));
                output.write(("Content-Disposition: form-data; name=\"" + name + "\"; filename=\"" + name + ".bin\"\r\n")
                        .getBytes(StandardCharsets.UTF_8));
                output.write(("Content-Type: " + contentType + "\r\n\r\n").getBytes(StandardCharsets.UTF_8));
                output.write(part.getValue());
                output.write("\r\n".getBytes(StandardCharsets.UTF_8));
            }
            output.write(("--" + boundary + "--\r\n").getBytes(StandardCharsets.UTF_8));
        } catch (java.io.IOException exception) {
            throw new IllegalStateException(exception);
        }
        return sendBytes("POST", path, output.toByteArray(),
                "multipart/form-data; boundary=" + boundary, headers);
    }

    private ApiResponse sendBytes(String method, String path, byte[] body, String contentType, String... headers) {
        try {
            HttpRequest.Builder builder = HttpRequest.newBuilder()
                    .uri(URI.create("http://localhost:" + port + BASE + path))
                    .timeout(Duration.ofSeconds(60));
            for (int i = 0; i + 1 < headers.length; i += 2) {
                builder.header(headers[i], headers[i + 1]);
            }
            if (contentType != null) {
                builder.header("Content-Type", contentType);
            }
            builder.method(method, HttpRequest.BodyPublishers.ofByteArray(body));
            HttpResponse<byte[]> response = client.send(builder.build(), HttpResponse.BodyHandlers.ofByteArray());
            JsonNode node = response.body() == null || response.body().length == 0
                    ? null
                    : objectMapper.readTree(response.body());
            return new ApiResponse(response.statusCode(), node, new LinkedHashMap<>(response.headers().map()));
        } catch (Exception exception) {
            throw new IllegalStateException("HTTP request failed: " + method + " " + path, exception);
        }
    }

    private ApiResponse send(String method, String path, String body, String contentType, String... headers) {
        try {
            HttpRequest.Builder builder = HttpRequest.newBuilder()
                    .uri(URI.create("http://localhost:" + port + BASE + path))
                    .timeout(Duration.ofSeconds(60));
            for (int i = 0; i + 1 < headers.length; i += 2) {
                builder.header(headers[i], headers[i + 1]);
            }
            if (contentType != null) {
                builder.header("Content-Type", contentType);
            }
            if (body != null) {
                builder.method(method, HttpRequest.BodyPublishers.ofString(body, StandardCharsets.UTF_8));
            } else {
                builder.method(method, HttpRequest.BodyPublishers.noBody());
            }
            HttpResponse<byte[]> response = client.send(builder.build(), HttpResponse.BodyHandlers.ofByteArray());
            JsonNode node = response.body() == null || response.body().length == 0
                    ? null
                    : objectMapper.readTree(response.body());
            return new ApiResponse(response.statusCode(), node, new LinkedHashMap<>(response.headers().map()));
        } catch (Exception exception) {
            throw new IllegalStateException("HTTP request failed: " + method + " " + path, exception);
        }
    }

    protected String tokenOf(JsonNode envelope) {
        return envelope.path("data").path("tokens").path("access_token").asText();
    }

    protected String refreshTokenOf(JsonNode envelope) {
        return envelope.path("data").path("tokens").path("refresh_token").asText();
    }

    protected String auth(String accessToken) {
        return "Bearer " + accessToken;
    }
}
