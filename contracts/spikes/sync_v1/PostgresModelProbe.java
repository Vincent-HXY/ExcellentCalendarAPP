import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.Callable;
import java.util.concurrent.Executors;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.utility.DockerImageName;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

/** Disposable PostgreSQL DDL/constraint experiment; no Spring business implementation. */
public final class PostgresModelProbe {
    static int scalar(Connection db, String sql) throws Exception {
        try (var s = db.createStatement(); var rows = s.executeQuery(sql)) {
            if (!rows.next()) throw new IllegalStateException("Missing scalar result");
            return rows.getInt(1);
        }
    }
    static void execute(Connection db, String sql) throws SQLException {
        try (var s = db.createStatement()) { s.execute(sql); }
    }
    public static void main(String[] args) throws Exception {
        Path root = Path.of(args[0]);
        JsonMapper mapper = JsonMapper.builder().build();
        JsonNode fixtures = mapper.readTree(Files.readString(Path.of(args[1])));
        List<Map<String, Object>> cases = new ArrayList<>();
        Map<String, Object> report = new LinkedHashMap<>();
        report.put("passed", false);
        report.put("product_migration_executed", false);
        try (var postgres = new PostgreSQLContainer<>(DockerImageName.parse("postgres:17.11-alpine"))
                .withDatabaseName("sync_contract_probe").withUsername("probe").withPassword("isolated-test-only")
                .withEnv("TZ", "UTC").withEnv("PGTZ", "UTC")) {
            postgres.start();
            try (Connection db = DriverManager.getConnection(postgres.getJdbcUrl(), postgres.getUsername(), postgres.getPassword())) {
                for (String name : List.of("V1__identity_schema.sql", "V2__email_change_requests.sql", "V3__avatar_assets.sql")) {
                    execute(db, Files.readString(root.resolve("cloud_backend/src/main/resources/db/migration/" + name)));
                }
                int baseline = scalar(db, "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'");
                String ddl = Files.readString(root.resolve("contracts/storage/cloud_sync_postgresql_v1.sql"));
                db.setAutoCommit(false);
                execute(db, ddl);
                db.rollback();
                if (scalar(db, "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'") != baseline)
                    throw new IllegalStateException("DDL rollback leaked tables");
                execute(db, ddl);
                db.commit();
                int added = scalar(db, "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'") - baseline;
                if (added != fixtures.get("expected_new_tables").asInt()) throw new IllegalStateException("Table count drift");
                report.put("new_tables", added);
                report.put("ddl_transaction_rollback", true);
                execute(db, fixtures.get("seed_sql").asString());
                db.commit();
                for (JsonNode item : fixtures.get("cases")) {
                    String expected = item.get("sqlstate").asString();
                    String actual = "00000";
                    Integer scalar = null;
                    try {
                        execute(db, item.get("sql").asString());
                        // Force deferred FKs before deciding the result.
                        execute(db, "SET CONSTRAINTS ALL IMMEDIATE");
                        if (item.has("query")) scalar = scalar(db, item.get("query").asString());
                    } catch (SQLException failure) {
                        actual = failure.getSQLState();
                    } finally {
                        db.rollback();
                    }
                    boolean passed = expected.equals(actual) && (!item.has("scalar") || item.get("scalar").asInt() == scalar);
                    var row = new LinkedHashMap<String, Object>();
                    row.put("id", item.get("id").asString()); row.put("expected_sqlstate", expected);
                    row.put("actual_sqlstate", actual); row.put("passed", passed);
                    cases.add(row);
                    if (!passed) throw new IllegalStateException("Constraint case failed: " + item.get("id").asString() + " actual=" + actual);
                }
                // Real competing transactions at MAX-1; exactly one allocation.
                String account = fixtures.get("account_id").asString();
                execute(db, "UPDATE sync_account_sequences SET highest_server_sequence=9007199254740990,next_server_sequence=9007199254740991 WHERE account_id='" + account + "'");
                db.commit();
                Callable<Integer> allocation = () -> {
                    try (Connection concurrent = DriverManager.getConnection(postgres.getJdbcUrl(), postgres.getUsername(), postgres.getPassword())) {
                        concurrent.setAutoCommit(false);
                        try (var s = concurrent.createStatement()) {
                            int changed = s.executeUpdate("UPDATE sync_account_sequences SET highest_server_sequence=9007199254740991,next_server_sequence=NULL WHERE account_id='" + account + "' AND highest_server_sequence=9007199254740990");
                            concurrent.commit();
                            return changed;
                        }
                    }
                };
                try (var executor = Executors.newFixedThreadPool(2)) {
                    var first = executor.submit(allocation); var second = executor.submit(allocation);
                    if (first.get() + second.get() != 1) throw new IllegalStateException("MAX concurrent allocation is not atomic");
                }
                report.put("concurrent_last_allocation_winners", 1);
                List<Map<String, Object>> columns = new ArrayList<>();
                try (var s = db.createStatement(); var rows = s.executeQuery("SELECT table_name,column_name,data_type,is_nullable FROM information_schema.columns WHERE table_schema='public' ORDER BY table_name,ordinal_position")) {
                    while (rows.next()) columns.add(Map.of("table", rows.getString(1), "column", rows.getString(2), "type", rows.getString(3), "nullable", rows.getString(4)));
                }
                report.put("columns", columns);
                report.put("passed", true);
            }
        } catch (Exception error) {
            report.put("error", error.getClass().getSimpleName() + ": " + error.getMessage());
        } finally {
            report.put("cases", cases);
            Files.writeString(Path.of(args[2]), mapper.writerWithDefaultPrettyPrinter().writeValueAsString(report) + "\n");
        }
        if (!Boolean.TRUE.equals(report.get("passed"))) throw new IllegalStateException("PostgreSQL model experiment failed; inspect sanitized report");
    }
}
