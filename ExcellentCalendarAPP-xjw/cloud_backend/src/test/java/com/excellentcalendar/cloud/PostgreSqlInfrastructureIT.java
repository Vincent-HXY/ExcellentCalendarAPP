package com.excellentcalendar.cloud;

import static org.assertj.core.api.Assertions.assertThat;

import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.postgresql.PostgreSQLContainer;
import org.testcontainers.utility.DockerImageName;

@ActiveProfiles("api")
@SpringBootTest
@Testcontainers(disabledWithoutDocker = true)
class PostgreSqlInfrastructureIT {

    @Container
    @ServiceConnection
    static final PostgreSQLContainer POSTGRESQL = new PostgreSQLContainer(
            DockerImageName.parse("postgres:17-alpine"))
            .withDatabaseName("excellent_calendar_test")
            .withUsername("excellent_calendar_test")
            .withPassword("test-only-password")
            .withEnv("TZ", "UTC")
            .withEnv("PGTZ", "UTC");

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private Flyway flyway;

    @Test
    void connectsToRealPostgresqlInUtc() {
        String databaseProduct = jdbcTemplate.queryForObject(
                "select version()",
                String.class);
        String timezone = jdbcTemplate.queryForObject(
                "select current_setting('TimeZone')",
                String.class);

        assertThat(databaseProduct).startsWith("PostgreSQL");
        assertThat(timezone).isEqualTo("UTC");
    }

    @Test
    void flywayOwnsSchemaEvolutionBeforeBusinessTablesExist() {
        assertThat(flyway.info().pending()).isEmpty();
        assertThat(flyway.info().current()).isNull();
    }
}
