#include "excellent_calendar/storage/sqlite/sqlite_calendar_database.hpp"

#include <picojson/picojson.h>
#include <sqlite3.h>

#include <array>
#include <cerrno>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <exception>
#include <filesystem>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <system_error>
#include <utility>

#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#else
#include <fcntl.h>
#include <unistd.h>
#endif

#include "excellent_calendar/storage/json/anniversary_json_codec.hpp"
#include "excellent_calendar/storage/json/atomic_json_file_store.hpp"
#include "excellent_calendar/storage/json/calendar_core_v3_storage_bootstrap.hpp"
#include "excellent_calendar/storage/json/category_json_codec.hpp"
#include "excellent_calendar/storage/json/json_category_repository.hpp"
#include "excellent_calendar/storage/json/json_event_reminder_transaction.hpp"
#include "excellent_calendar/storage/json/json_event_repository.hpp"
#include "excellent_calendar/storage/json/json_notification_repository.hpp"
#include "excellent_calendar/storage/json/json_recurring_event_transaction.hpp"
#include "excellent_calendar/storage/json/json_reminder_notification_transaction.hpp"
#include "excellent_calendar/storage/json/json_reminder_repository.hpp"
#include "excellent_calendar/storage/json/legacy_json_codec.hpp"
#include "excellent_calendar/storage/json/recurring_event_json_codec.hpp"

namespace excellent_calendar::storage::sqlite {
namespace {

constexpr int kApplicationId = 0x4543414c;  // "ECAL"
constexpr double kMaxExactJsonInteger = 9007199254740991.0;
constexpr const char* kFormatName = "excellent_calendar_core_sqlite";
constexpr const char* kCutoverMigrationId =
    "calendar_core_json_to_sqlite_v4_cutover_v1";
constexpr const char* kCutoverJournalFileName =
    "calendar_core_sqlite_cutover.json";
static_assert(
    SQLITE_VERSION_NUMBER == 3053004,
    "SQLite dependency and Storage v4 Contract must be upgraded together");

struct StoreSpec {
  const char* logical_name;
  const char* file_name;
  const char* table_name;
  const char* collection_field;
  int payload_version = 3;
};

constexpr std::array<StoreSpec, 10> kStoreSpecs{{
    {"events", "events.json", "events", "events"},
    {"recurrence_versions", "recurrence_versions.json", "recurrence_versions",
     "recurrence_versions"},
    {"event_occurrence_states", "event_occurrence_states.json",
     "event_occurrence_states", "event_occurrence_states"},
    {"anniversaries", "anniversaries.json", "anniversaries", "anniversaries"},
    {"anniversary_recurrences", "anniversary_recurrences.json",
     "anniversary_recurrences", "anniversary_recurrences"},
    {"anniversary_reminder_templates", "anniversary_reminder_templates.json",
     "anniversary_reminder_templates", "anniversary_reminder_templates"},
    {"reminders", "reminders.json", "reminders", "reminders"},
    {"notifications", "notifications.json", "notifications", "notifications"},
    {"reminder_recovery_batches", "reminder_recovery_batches.json",
     "reminder_recovery_batches", "reminder_recovery_batches"},
    {"categories", "categories.json", "categories", "categories"},
}};

constexpr std::array<StoreSpec, 3> kLegacyStoreSpecs{{
    {"legacy_events", "events.json", "legacy_events", "events", 1},
    {"legacy_reminders", "reminders.json", "legacy_reminders", "reminders", 1},
    {"legacy_notifications", "notifications.json", "legacy_notifications",
     "notifications", 1},
}};

constexpr std::array<const char*, 16> kRequiredTables{{
    "schema_metadata",
    "store_generations",
    "migration_history",
    "events",
    "recurrence_versions",
    "event_occurrence_states",
    "anniversaries",
    "anniversary_recurrences",
    "anniversary_reminder_templates",
    "reminders",
    "notifications",
    "reminder_recovery_batches",
    "categories",
    "legacy_events",
    "legacy_reminders",
    "legacy_notifications",
}};

struct NamedSchema {
  const char* name;
  const char* sql;
};

constexpr std::array<NamedSchema, 16> kRequiredIndexes{{
    {"ux_recurrence_identity",
     "CREATE UNIQUE INDEX ux_recurrence_identity ON recurrence_versions("
     "json_extract(payload_json,'$.recurrence_id'),"
     "CAST(json_extract(payload_json,'$.revision') AS INTEGER))"},
    {"ux_occurrence_state_identity",
     "CREATE UNIQUE INDEX ux_occurrence_state_identity ON "
     "event_occurrence_states("
     "json_extract(payload_json,'$.event_id'),"
     "CAST(json_extract(payload_json,'$.recurrence_revision') AS INTEGER),"
     "json_extract(payload_json,'$.occurrence_key'))"},
    {"ux_reminder_recurring_identity",
     "CREATE UNIQUE INDEX ux_reminder_recurring_identity ON reminders("
     "json_extract(payload_json,'$.target_id'),"
     "CAST(json_extract(payload_json,'$.recurrence_revision') AS INTEGER),"
     "json_extract(payload_json,'$.occurrence_key'),"
     "CAST(json_extract(payload_json,'$.advance_minutes') AS INTEGER),"
     "json_extract(payload_json,'$.methods')) "
     "WHERE json_extract(payload_json,'$.recurrence_revision') IS NOT NULL"},
    {"ux_notification_attempt_id",
     "CREATE UNIQUE INDEX ux_notification_attempt_id ON notifications("
     "json_extract(payload_json,'$.delivery_attempt_id'))"},
    {"ux_notification_prepared_delivery",
     "CREATE UNIQUE INDEX ux_notification_prepared_delivery ON notifications("
     "json_extract(payload_json,'$.delivery_id')) "
     "WHERE json_extract(payload_json,'$.status')='prepared'"},
    {"ux_notification_sent_delivery",
     "CREATE UNIQUE INDEX ux_notification_sent_delivery ON notifications("
     "json_extract(payload_json,'$.delivery_id')) "
     "WHERE json_extract(payload_json,'$.status')='sent'"},
    {"ux_recovery_request_id",
     "CREATE UNIQUE INDEX ux_recovery_request_id ON reminder_recovery_batches("
     "json_extract(payload_json,'$.recovery_request_id'))"},
    {"ux_single_recovery_in_progress",
     "CREATE UNIQUE INDEX ux_single_recovery_in_progress ON "
     "reminder_recovery_batches((1)) "
     "WHERE json_extract(payload_json,'$.status')='in_progress'"},
    {"ux_anniversary_template_identity",
     "CREATE UNIQUE INDEX ux_anniversary_template_identity ON "
     "anniversary_reminder_templates("
     "json_extract(payload_json,'$.anniversary_id'),"
     "CAST(json_extract(payload_json,'$.advance_days') AS INTEGER),"
     "json_extract(payload_json,'$.local_time'),"
     "json_extract(payload_json,'$.timezone_mode'),"
     "json_extract(payload_json,'$.method'))"},
    {"ix_reminders_schedulable",
     "CREATE INDEX ix_reminders_schedulable ON reminders("
     "CAST(json_extract(payload_json,'$.is_enabled') AS INTEGER),"
     "json_extract(payload_json,'$.deleted_at'),"
     "json_extract(payload_json,'$.status'),"
     "json_extract(payload_json,'$.remind_at'), record_key)"},
    {"ix_events_active_time",
     "CREATE INDEX ix_events_active_time ON events("
     "json_extract(payload_json,'$.deleted_at'),"
     "json_extract(payload_json,'$.status'),"
     "json_extract(payload_json,'$.start_at'),"
     "json_extract(payload_json,'$.start_date'), record_key)"},
    {"ix_events_category",
     "CREATE INDEX ix_events_category ON events("
     "json_extract(payload_json,'$.category_id'),"
     "json_extract(payload_json,'$.deleted_at'))"},
    {"ix_notifications_reminder",
     "CREATE INDEX ix_notifications_reminder ON notifications("
     "json_extract(payload_json,'$.reminder_id'), position)"},
    {"ix_categories_active_order",
     "CREATE INDEX ix_categories_active_order ON categories("
     "json_extract(payload_json,'$.deleted_at'),"
     "CAST(json_extract(payload_json,'$.sort_order') AS INTEGER),"
     "json_extract(payload_json,'$.created_at'), record_key)"},
    {"ix_legacy_reminders_schedulable",
     "CREATE INDEX ix_legacy_reminders_schedulable ON legacy_reminders("
     "CAST(json_extract(payload_json,'$.is_enabled') AS INTEGER),"
     "json_extract(payload_json,'$.deleted_at'),"
     "json_extract(payload_json,'$.status'),"
     "json_extract(payload_json,'$.remind_at'), record_key)"},
    {"ix_legacy_notifications_reminder",
     "CREATE INDEX ix_legacy_notifications_reminder ON "
     "legacy_notifications(json_extract(payload_json,'$.reminder_id'),"
     "position)"},
}};

struct JsonGuardSpec {
  const char* file_name;
  const char* collection_field;
};

// storage_migrations blocks v2/v3 bootstrap first; events then blocks the
// supported v1 runtime before any database publication can happen.
constexpr std::array<JsonGuardSpec, 16> kJsonWriterGuards{{
    {"storage_migrations.json", "migrations"},
    {"events.json", "events"},
    {"reminders.json", "reminders"},
    {"notifications.json", "notifications"},
    {"recurrence_versions.json", "recurrence_versions"},
    {"event_occurrence_states.json", "event_occurrence_states"},
    {"anniversaries.json", "anniversaries"},
    {"anniversary_recurrences.json", "anniversary_recurrences"},
    {"anniversary_reminder_templates.json",
     "anniversary_reminder_templates"},
    {"reminder_recovery_batches.json", "reminder_recovery_batches"},
    {"categories.json", "categories"},
    {"event_reminder_transaction.json", nullptr},
    {"reminder_notification_transaction.json", nullptr},
    {"workflow_transactions.json", "transactions"},
    {"anniversary_workflow_transactions.json", "transactions"},
    {"calendar_workflow_transactions.json", "transactions"},
}};

enum class MigrationSourceKind { kFresh, kJsonV1, kJsonV2, kJsonV3 };

struct CutoverJournal {
  MigrationSourceKind source_kind = MigrationSourceKind::kFresh;
  std::string state;
  std::map<std::string, std::optional<picojson::value>> source_roots;
};

constexpr std::array<const char*, 9> kRecurringStoreFiles{{
    "events.json",
    "recurrence_versions.json",
    "event_occurrence_states.json",
    "anniversaries.json",
    "anniversary_recurrences.json",
    "anniversary_reminder_templates.json",
    "reminders.json",
    "notifications.json",
    "reminder_recovery_batches.json",
}};

constexpr std::array<const char*, 4> kAnniversaryStoreFiles{{
    "anniversaries.json",
    "anniversary_recurrences.json",
    "anniversary_reminder_templates.json",
    "reminders.json",
}};

const StoreSpec* find_store(std::string_view file_name) {
  for (const auto& spec : kStoreSpecs) {
    if (file_name == spec.file_name) return &spec;
  }
  return nullptr;
}

const StoreSpec* find_legacy_store(std::string_view logical_name) {
  for (const auto& spec : kLegacyStoreSpecs) {
    if (logical_name == spec.logical_name) return &spec;
  }
  return nullptr;
}

common::Error sqlite_error(::sqlite3* database, std::string phase,
                           int result_code = SQLITE_ERROR) {
  std::string reason = database == nullptr ? "SQLite database is unavailable"
                                           : ::sqlite3_errmsg(database);
  return common::make_error("STORAGE_IO_ERROR",
                            "Storage input/output operation failed",
                            {{"phase", std::move(phase)},
                             {"sqlite_code", std::to_string(result_code)},
                             {"reason", std::move(reason)}},
                            true);
}

common::Error corrupted(std::string reason, std::string field = {}) {
  return common::make_error(
      "STORAGE_DATA_CORRUPTED", "Storage data is corrupted",
      field.empty()
          ? std::map<std::string, std::string>{{"reason", std::move(reason)}}
          : std::map<std::string, std::string>{{"reason", std::move(reason)},
                                               {"field", std::move(field)}});
}

common::Error invalid_path(const std::filesystem::path& path) {
  return common::make_error("STORAGE_PATH_INVALID",
                            "Storage path is invalid or not writable",
                            {{"path", path.string()}});
}

common::Error filesystem_io_error(std::string phase,
                                  const std::filesystem::path& path,
                                  std::string reason) {
  return common::make_error("STORAGE_IO_ERROR",
                            "Storage input/output operation failed",
                            {{"phase", std::move(phase)},
                             {"path", path.string()},
                             {"reason", std::move(reason)}},
                            true);
}

common::Result<common::Unit> sync_file_to_disk(
    const std::filesystem::path& path) {
#if defined(_WIN32)
  const auto handle =
      ::CreateFileW(path.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr,
                    OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (handle == INVALID_HANDLE_VALUE) {
    return common::Result<common::Unit>::failure(filesystem_io_error(
        "open_database_for_sync", path,
        "CreateFile failed with code " + std::to_string(::GetLastError())));
  }
  const bool flushed = ::FlushFileBuffers(handle) != 0;
  const auto error = flushed ? ERROR_SUCCESS : ::GetLastError();
  ::CloseHandle(handle);
  return flushed ? common::Result<common::Unit>::success(common::Unit{})
                 : common::Result<common::Unit>::failure(filesystem_io_error(
                       "sync_database", path,
                       "FlushFileBuffers failed with code " +
                           std::to_string(error)));
#else
  const int descriptor = ::open(path.c_str(), O_RDONLY);
  if (descriptor < 0) {
    return common::Result<common::Unit>::failure(filesystem_io_error(
        "open_database_for_sync", path, std::system_category().message(errno)));
  }
  const int result = ::fsync(descriptor);
  const int error = errno;
  ::close(descriptor);
  return result == 0
             ? common::Result<common::Unit>::success(common::Unit{})
             : common::Result<common::Unit>::failure(
                   filesystem_io_error("sync_database", path,
                                       std::system_category().message(error)));
#endif
}

common::Result<common::Unit> publish_database_atomically(
    const std::filesystem::path& source, const std::filesystem::path& target) {
#if defined(_WIN32)
  if (!::MoveFileExW(source.c_str(), target.c_str(), MOVEFILE_WRITE_THROUGH)) {
    return common::Result<common::Unit>::failure(filesystem_io_error(
        "publish_database", target,
        "MoveFileEx failed with code " + std::to_string(::GetLastError())));
  }
#else
  std::error_code rename_error;
  std::filesystem::rename(source, target, rename_error);
  if (rename_error) {
    return common::Result<common::Unit>::failure(filesystem_io_error(
        "publish_database", target, rename_error.message()));
  }

  int flags = O_RDONLY;
#if defined(O_DIRECTORY)
  flags |= O_DIRECTORY;
#endif
  const int descriptor = ::open(target.parent_path().c_str(), flags);
  if (descriptor < 0) {
    return common::Result<common::Unit>::failure(filesystem_io_error(
        "open_database_directory_for_sync", target.parent_path(),
        std::system_category().message(errno)));
  }
  const int result = ::fsync(descriptor);
  const int error = errno;
  ::close(descriptor);
  if (result != 0) {
    return common::Result<common::Unit>::failure(
        filesystem_io_error("sync_database_directory", target.parent_path(),
                            std::system_category().message(error)));
  }
#endif
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Error invalid_configuration(std::string setting, std::string expected,
                                    std::string actual) {
  return common::make_error("STORAGE_IO_ERROR",
                            "Storage input/output operation failed",
                            {{"phase", "configure_database"},
                             {"setting", std::move(setting)},
                             {"expected", std::move(expected)},
                             {"actual", std::move(actual)}},
                            true);
}

common::Result<common::Unit> execute_sql(::sqlite3* database,
                                         const std::string& sql,
                                         std::string phase) {
  char* message = nullptr;
  const int code =
      ::sqlite3_exec(database, sql.c_str(), nullptr, nullptr, &message);
  if (code == SQLITE_OK) {
    return common::Result<common::Unit>::success(common::Unit{});
  }
  std::string reason =
      message == nullptr ? ::sqlite3_errmsg(database) : message;
  ::sqlite3_free(message);
  return common::Result<common::Unit>::failure(common::make_error(
      "STORAGE_IO_ERROR", "Storage input/output operation failed",
      {{"phase", std::move(phase)},
       {"sqlite_code", std::to_string(code)},
       {"reason", std::move(reason)}},
      true));
}

class Statement final {
 public:
  Statement() = default;
  explicit Statement(::sqlite3_stmt* statement) : statement_(statement) {}
  ~Statement() {
    if (statement_ != nullptr) ::sqlite3_finalize(statement_);
  }

  Statement(const Statement&) = delete;
  Statement& operator=(const Statement&) = delete;
  Statement(Statement&& other) noexcept
      : statement_(std::exchange(other.statement_, nullptr)) {}
  Statement& operator=(Statement&& other) noexcept {
    if (this != &other) {
      if (statement_ != nullptr) ::sqlite3_finalize(statement_);
      statement_ = std::exchange(other.statement_, nullptr);
    }
    return *this;
  }

  ::sqlite3_stmt* get() const { return statement_; }

 private:
  ::sqlite3_stmt* statement_ = nullptr;
};

common::Result<Statement> prepare(::sqlite3* database, const std::string& sql,
                                  std::string phase) {
  ::sqlite3_stmt* statement = nullptr;
  const int code =
      ::sqlite3_prepare_v2(database, sql.c_str(), -1, &statement, nullptr);
  if (code != SQLITE_OK) {
    return common::Result<Statement>::failure(
        sqlite_error(database, std::move(phase), code));
  }
  return common::Result<Statement>::success(Statement(statement));
}

common::Result<int> query_single_int(::sqlite3* database,
                                     const std::string& sql,
                                     std::string phase) {
  auto statement = prepare(database, sql, phase);
  if (!statement.ok()) {
    return common::Result<int>::failure(statement.error());
  }
  const int step = ::sqlite3_step(statement.value().get());
  if (step != SQLITE_ROW) {
    return common::Result<int>::failure(
        sqlite_error(database, std::move(phase), step));
  }
  const int value = ::sqlite3_column_int(statement.value().get(), 0);
  if (::sqlite3_step(statement.value().get()) != SQLITE_DONE) {
    return common::Result<int>::failure(
        corrupted("query returned multiple rows"));
  }
  return common::Result<int>::success(value);
}

common::Result<std::string> query_single_text(::sqlite3* database,
                                              const std::string& sql,
                                              std::string phase) {
  auto statement = prepare(database, sql, phase);
  if (!statement.ok()) {
    return common::Result<std::string>::failure(statement.error());
  }
  const int step = ::sqlite3_step(statement.value().get());
  if (step != SQLITE_ROW ||
      ::sqlite3_column_type(statement.value().get(), 0) != SQLITE_TEXT) {
    return common::Result<std::string>::failure(
        step == SQLITE_ROW ? corrupted("query result is not text")
                           : sqlite_error(database, std::move(phase), step));
  }
  const auto* text = ::sqlite3_column_text(statement.value().get(), 0);
  const int size = ::sqlite3_column_bytes(statement.value().get(), 0);
  std::string value(reinterpret_cast<const char*>(text),
                    static_cast<std::size_t>(size));
  if (::sqlite3_step(statement.value().get()) != SQLITE_DONE) {
    return common::Result<std::string>::failure(
        corrupted("query returned multiple rows"));
  }
  return common::Result<std::string>::success(std::move(value));
}

std::string normalized_schema_sql(std::string_view sql) {
  std::string normalized;
  normalized.reserve(sql.size());
  for (const unsigned char character : sql) {
    if (std::isspace(character) != 0 || character == ';') continue;
    normalized.push_back(static_cast<char>(std::tolower(character)));
  }
  return normalized;
}

std::string expected_table_schema(std::string_view name) {
  if (name == "schema_metadata") {
    return "CREATE TABLE schema_metadata("
           "key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID";
  }
  if (name == "store_generations") {
    return "CREATE TABLE store_generations("
           "store_name TEXT PRIMARY KEY,"
           "generation INTEGER NOT NULL CHECK(generation >= 0)) WITHOUT ROWID";
  }
  if (name == "migration_history") {
    return "CREATE TABLE migration_history("
           "migration_id TEXT PRIMARY KEY,"
           "source_format TEXT NOT NULL,"
           "source_version INTEGER NOT NULL,"
           "target_version INTEGER NOT NULL,"
           "completed_at TEXT NOT NULL) WITHOUT ROWID";
  }
  return "CREATE TABLE " + std::string(name) +
         "(record_key TEXT PRIMARY KEY,"
         "position INTEGER NOT NULL UNIQUE CHECK(position >= 0),"
         "payload_json TEXT NOT NULL CHECK(json_valid(payload_json))) "
         "WITHOUT ROWID";
}

common::Result<common::Unit> require_schema_object(
    ::sqlite3* database, std::string_view type, std::string_view name,
    std::string_view expected_sql) {
  auto statement = prepare(
      database, "SELECT sql FROM sqlite_schema WHERE type=?1 AND name=?2",
      "validate_schema_object");
  if (!statement.ok()) {
    return common::Result<common::Unit>::failure(statement.error());
  }
  int code =
      ::sqlite3_bind_text(statement.value().get(), 1, std::string(type).c_str(),
                          -1, SQLITE_TRANSIENT);
  if (code == SQLITE_OK) {
    code = ::sqlite3_bind_text(statement.value().get(), 2,
                               std::string(name).c_str(), -1, SQLITE_TRANSIENT);
  }
  if (code != SQLITE_OK) {
    return common::Result<common::Unit>::failure(
        sqlite_error(database, "validate_schema_object", code));
  }
  const int step = ::sqlite3_step(statement.value().get());
  if (step != SQLITE_ROW ||
      ::sqlite3_column_type(statement.value().get(), 0) != SQLITE_TEXT) {
    return common::Result<common::Unit>::failure(
        corrupted("required SQLite schema object is missing",
                  std::string(type) + "." + std::string(name)));
  }
  const auto* sql_text = ::sqlite3_column_text(statement.value().get(), 0);
  const int sql_size = ::sqlite3_column_bytes(statement.value().get(), 0);
  const std::string actual_sql(reinterpret_cast<const char*>(sql_text),
                               static_cast<std::size_t>(sql_size));
  if (::sqlite3_step(statement.value().get()) != SQLITE_DONE) {
    return common::Result<common::Unit>::failure(
        corrupted("SQLite schema object is duplicated",
                  std::string(type) + "." + std::string(name)));
  }
  if (normalized_schema_sql(actual_sql) !=
      normalized_schema_sql(expected_sql)) {
    return common::Result<common::Unit>::failure(
        corrupted("SQLite schema object definition differs from Storage v4",
                  std::string(type) + "." + std::string(name)));
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<std::string> required_string(const picojson::object& object,
                                            std::string_view field,
                                            std::string_view store) {
  const auto found = object.find(std::string(field));
  if (found == object.end() || !found->second.is<std::string>() ||
      found->second.get<std::string>().empty()) {
    return common::Result<std::string>::failure(
        corrupted("record identity field is missing or invalid",
                  std::string(store) + "." + std::string(field)));
  }
  return common::Result<std::string>::success(found->second.get<std::string>());
}

common::Result<std::string> required_integer(const picojson::object& object,
                                             std::string_view field,
                                             std::string_view store) {
  const auto found = object.find(std::string(field));
  if (found == object.end() || !found->second.is<double>()) {
    return common::Result<std::string>::failure(
        corrupted("record identity integer is missing",
                  std::string(store) + "." + std::string(field)));
  }
  const double number = found->second.get<double>();
  if (!std::isfinite(number) || std::floor(number) != number || number < 0.0 ||
      number > kMaxExactJsonInteger) {
    return common::Result<std::string>::failure(
        corrupted("record identity integer is invalid",
                  std::string(store) + "." + std::string(field)));
  }
  return common::Result<std::string>::success(
      std::to_string(static_cast<std::int64_t>(number)));
}

common::Result<std::string> record_key(const StoreSpec& spec,
                                       const picojson::value& record) {
  if (!record.is<picojson::object>()) {
    return common::Result<std::string>::failure(
        corrupted("record must be an object", spec.logical_name));
  }
  const auto& object = record.get<picojson::object>();
  if (std::string_view(spec.logical_name).rfind("legacy_", 0) == 0U ||
      std::string_view(spec.file_name) == "events.json" ||
      std::string_view(spec.file_name) == "anniversaries.json" ||
      std::string_view(spec.file_name) == "categories.json") {
    return required_string(object, "id", spec.logical_name);
  }
  if (std::string_view(spec.file_name) == "recurrence_versions.json") {
    auto id = required_string(object, "recurrence_id", spec.logical_name);
    if (!id.ok()) return id;
    auto revision = required_integer(object, "revision", spec.logical_name);
    if (!revision.ok()) return revision;
    return common::Result<std::string>::success(id.value() + "\x1f" +
                                                revision.value());
  }
  if (std::string_view(spec.file_name) == "event_occurrence_states.json") {
    auto event = required_string(object, "event_id", spec.logical_name);
    if (!event.ok()) return event;
    auto revision =
        required_integer(object, "recurrence_revision", spec.logical_name);
    if (!revision.ok()) return revision;
    auto occurrence =
        required_string(object, "occurrence_key", spec.logical_name);
    if (!occurrence.ok()) return occurrence;
    return common::Result<std::string>::success(event.value() + "\x1f" +
                                                revision.value() + "\x1f" +
                                                occurrence.value());
  }
  if (std::string_view(spec.file_name) == "anniversary_recurrences.json") {
    return required_string(object, "recurrence_id", spec.logical_name);
  }
  if (std::string_view(spec.file_name) ==
      "anniversary_reminder_templates.json") {
    return required_string(object, "template_key", spec.logical_name);
  }
  if (std::string_view(spec.file_name) == "reminders.json") {
    return required_string(object, "reminder_id", spec.logical_name);
  }
  if (std::string_view(spec.file_name) == "notifications.json") {
    return required_string(object, "notification_id", spec.logical_name);
  }
  if (std::string_view(spec.file_name) == "reminder_recovery_batches.json") {
    return required_string(object, "recovery_batch_id", spec.logical_name);
  }
  return common::Result<std::string>::failure(
      corrupted("unknown SQLite logical store", spec.file_name));
}

common::Result<picojson::value> read_store_root(::sqlite3* database,
                                                const StoreSpec& spec) {
  auto statement =
      prepare(database,
              "SELECT record_key, position, payload_json FROM " +
                  std::string(spec.table_name) + " ORDER BY position ASC",
              std::string("read_") + spec.logical_name);
  if (!statement.ok()) {
    return common::Result<picojson::value>::failure(statement.error());
  }

  picojson::array records;
  std::int64_t expected_position = 0;
  while (true) {
    const int step = ::sqlite3_step(statement.value().get());
    if (step == SQLITE_DONE) break;
    if (step != SQLITE_ROW) {
      return common::Result<picojson::value>::failure(sqlite_error(
          database, std::string("read_") + spec.logical_name, step));
    }
    if (::sqlite3_column_type(statement.value().get(), 0) != SQLITE_TEXT ||
        ::sqlite3_column_type(statement.value().get(), 1) != SQLITE_INTEGER ||
        ::sqlite3_column_type(statement.value().get(), 2) != SQLITE_TEXT) {
      return common::Result<picojson::value>::failure(
          corrupted("SQLite record columns are invalid", spec.logical_name));
    }
    const auto position = ::sqlite3_column_int64(statement.value().get(), 1);
    if (position != expected_position++) {
      return common::Result<picojson::value>::failure(corrupted(
          "SQLite record positions are not contiguous", spec.logical_name));
    }
    const auto* key_text = ::sqlite3_column_text(statement.value().get(), 0);
    const int key_size = ::sqlite3_column_bytes(statement.value().get(), 0);
    const auto* payload_text =
        ::sqlite3_column_text(statement.value().get(), 2);
    const int payload_size = ::sqlite3_column_bytes(statement.value().get(), 2);
    const std::string stored_key(reinterpret_cast<const char*>(key_text),
                                 static_cast<std::size_t>(key_size));
    const std::string payload(reinterpret_cast<const char*>(payload_text),
                              static_cast<std::size_t>(payload_size));
    picojson::value record;
    const std::string parse_error = picojson::parse(record, payload);
    if (!parse_error.empty()) {
      return common::Result<picojson::value>::failure(
          corrupted("SQLite record JSON is malformed: " + parse_error,
                    spec.logical_name));
    }
    auto derived_key = record_key(spec, record);
    if (!derived_key.ok()) {
      return common::Result<picojson::value>::failure(derived_key.error());
    }
    if (derived_key.value() != stored_key) {
      return common::Result<picojson::value>::failure(corrupted(
          "SQLite record key does not match its payload", spec.logical_name));
    }
    records.push_back(std::move(record));
  }

  picojson::object root;
  root["storage_version"] =
      picojson::value(static_cast<double>(spec.payload_version));
  root[spec.collection_field] = picojson::value(std::move(records));
  return common::Result<picojson::value>::success(
      picojson::value(std::move(root)));
}

common::Result<common::Unit> replace_store_root(::sqlite3* database,
                                                const StoreSpec& spec,
                                                const picojson::value& root) {
  if (!root.is<picojson::object>()) {
    return common::Result<common::Unit>::failure(
        corrupted("encoded Store root is invalid", spec.logical_name));
  }
  const auto& object = root.get<picojson::object>();
  const auto version = object.find("storage_version");
  const auto values = object.find(spec.collection_field);
  if (version == object.end() || !version->second.is<double>() ||
      version->second.get<double>() !=
          static_cast<double>(spec.payload_version) ||
      values == object.end() || !values->second.is<picojson::array>()) {
    return common::Result<common::Unit>::failure(
        corrupted("encoded Store envelope is invalid", spec.logical_name));
  }

  auto removed =
      execute_sql(database, "DELETE FROM " + std::string(spec.table_name),
                  std::string("clear_") + spec.logical_name);
  if (!removed.ok()) return removed;

  auto statement =
      prepare(database,
              "INSERT INTO " + std::string(spec.table_name) +
                  "(record_key, position, payload_json) VALUES(?1, ?2, ?3)",
              std::string("write_") + spec.logical_name);
  if (!statement.ok()) {
    return common::Result<common::Unit>::failure(statement.error());
  }

  const auto& array = values->second.get<picojson::array>();
  for (std::size_t index = 0; index < array.size(); ++index) {
    auto key = record_key(spec, array[index]);
    if (!key.ok()) return common::Result<common::Unit>::failure(key.error());
    const std::string payload = array[index].serialize();
    ::sqlite3_reset(statement.value().get());
    ::sqlite3_clear_bindings(statement.value().get());
    int code = ::sqlite3_bind_text(statement.value().get(), 1,
                                   key.value().c_str(), -1, SQLITE_TRANSIENT);
    if (code == SQLITE_OK) {
      code = ::sqlite3_bind_int64(statement.value().get(), 2,
                                  static_cast<::sqlite3_int64>(index));
    }
    if (code == SQLITE_OK) {
      code = ::sqlite3_bind_text(statement.value().get(), 3, payload.c_str(),
                                 static_cast<int>(payload.size()),
                                 SQLITE_TRANSIENT);
    }
    if (code != SQLITE_OK ||
        ::sqlite3_step(statement.value().get()) != SQLITE_DONE) {
      const int write_code =
          code == SQLITE_OK ? ::sqlite3_errcode(database) : code;
      return common::Result<common::Unit>::failure(sqlite_error(
          database, std::string("write_") + spec.logical_name, write_code));
    }
  }

  auto generation =
      prepare(database,
              "UPDATE store_generations SET generation = generation + 1 "
              "WHERE store_name = ?1",
              std::string("generation_") + spec.logical_name);
  if (!generation.ok()) {
    return common::Result<common::Unit>::failure(generation.error());
  }
  int code = ::sqlite3_bind_text(generation.value().get(), 1, spec.logical_name,
                                 -1, SQLITE_STATIC);
  if (code != SQLITE_OK ||
      ::sqlite3_step(generation.value().get()) != SQLITE_DONE ||
      ::sqlite3_changes(database) != 1) {
    const int update_code =
        code == SQLITE_OK ? ::sqlite3_errcode(database) : code;
    return common::Result<common::Unit>::failure(sqlite_error(
        database, std::string("generation_") + spec.logical_name, update_code));
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<std::int64_t> generation_for(::sqlite3* database,
                                            std::string_view store_name) {
  auto statement =
      prepare(database,
              "SELECT generation FROM store_generations WHERE store_name = ?1",
              "read_store_generation");
  if (!statement.ok()) {
    return common::Result<std::int64_t>::failure(statement.error());
  }
  int code = ::sqlite3_bind_text(statement.value().get(), 1,
                                 std::string(store_name).c_str(), -1,
                                 SQLITE_TRANSIENT);
  if (code != SQLITE_OK) {
    return common::Result<std::int64_t>::failure(
        sqlite_error(database, "read_store_generation", code));
  }
  const int step = ::sqlite3_step(statement.value().get());
  if (step != SQLITE_ROW ||
      ::sqlite3_column_type(statement.value().get(), 0) != SQLITE_INTEGER) {
    return common::Result<std::int64_t>::failure(
        step == SQLITE_ROW
            ? corrupted("Store generation is invalid")
            : sqlite_error(database, "read_store_generation", step));
  }
  const auto value = ::sqlite3_column_int64(statement.value().get(), 0);
  if (value < 0 || ::sqlite3_step(statement.value().get()) != SQLITE_DONE) {
    return common::Result<std::int64_t>::failure(
        corrupted("Store generation is invalid"));
  }
  return common::Result<std::int64_t>::success(value);
}

common::Result<common::Unit> remove_stale_database_files(
    const std::filesystem::path& database_path) {
  std::error_code error;
  for (const auto& path :
       {database_path, std::filesystem::path(database_path.string() + "-wal"),
        std::filesystem::path(database_path.string() + "-shm")}) {
    if (std::filesystem::exists(path, error)) {
      error.clear();
      std::filesystem::remove(path, error);
      if (error) {
        return common::Result<common::Unit>::failure(invalid_path(path));
      }
    }
    error.clear();
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<bool> has_legacy_v1_source(
    const std::filesystem::path& storage_directory) {
  storage::json::AtomicJsonFileStore store(storage_directory);
  auto initialized = store.initialize();
  if (!initialized.ok()) {
    return common::Result<bool>::failure(initialized.error());
  }
  bool has_v1 = false;
  bool has_modern = false;
  for (const auto& spec : kStoreSpecs) {
    auto root = store.read_json_file(spec.file_name);
    if (!root.ok()) return common::Result<bool>::failure(root.error());
    if (!root.value().has_value()) continue;
    if (!root.value()->is<picojson::object>()) {
      return common::Result<bool>::failure(
          corrupted("Store root must be object", spec.file_name));
    }
    const auto& object = root.value()->get<picojson::object>();
    const auto version = object.find("storage_version");
    if (version == object.end() || !version->second.is<double>() ||
        !std::isfinite(version->second.get<double>()) ||
        std::floor(version->second.get<double>()) !=
            version->second.get<double>()) {
      return common::Result<bool>::failure(
          corrupted("storage_version must be integer", spec.file_name));
    }
    const auto file_name = std::string_view(spec.file_name);
    const bool legacy_v1_store = file_name == "events.json" ||
                                 file_name == "reminders.json" ||
                                 file_name == "notifications.json";
    if (legacy_v1_store && version->second.get<double>() == 1.0) {
      has_v1 = true;
    } else {
      has_modern = true;
    }
  }
  std::error_code filesystem_error;
  bool has_legacy_journal = false;
  for (const auto* file_name : {"event_reminder_transaction.json",
                                "reminder_notification_transaction.json"}) {
    has_legacy_journal = std::filesystem::exists(storage_directory / file_name,
                                                 filesystem_error) ||
                         has_legacy_journal;
    if (filesystem_error) break;
  }
  for (const auto* file_name :
       {"workflow_transactions.json", "anniversary_workflow_transactions.json",
        "calendar_workflow_transactions.json", "storage_migrations.json"}) {
    has_modern = std::filesystem::exists(storage_directory / file_name,
                                         filesystem_error) ||
                 has_modern;
    if (filesystem_error) break;
  }
  if (filesystem_error) {
    return common::Result<bool>::failure(invalid_path(storage_directory));
  }
  // Mixed transitional directories remain owned by the established v2/v3
  // bootstrap, which has the journal-aware rules needed to resolve them.
  return common::Result<bool>::success((has_v1 || has_legacy_journal) &&
                                       !has_modern);
}

const StoreSpec* find_legacy_store_by_file(std::string_view file_name) {
  for (const auto& spec : kLegacyStoreSpecs) {
    if (file_name == spec.file_name) return &spec;
  }
  return nullptr;
}

std::string source_kind_name(MigrationSourceKind source_kind) {
  switch (source_kind) {
    case MigrationSourceKind::kFresh:
      return "fresh";
    case MigrationSourceKind::kJsonV1:
      return "json_v1";
    case MigrationSourceKind::kJsonV2:
      return "json_v2";
    case MigrationSourceKind::kJsonV3:
      return "json_v3";
  }
  return "";
}

common::Result<MigrationSourceKind> parse_source_kind(
    std::string_view source_kind) {
  if (source_kind == "fresh") {
    return common::Result<MigrationSourceKind>::success(
        MigrationSourceKind::kFresh);
  }
  if (source_kind == "json_v1") {
    return common::Result<MigrationSourceKind>::success(
        MigrationSourceKind::kJsonV1);
  }
  if (source_kind == "json_v2") {
    return common::Result<MigrationSourceKind>::success(
        MigrationSourceKind::kJsonV2);
  }
  if (source_kind == "json_v3") {
    return common::Result<MigrationSourceKind>::success(
        MigrationSourceKind::kJsonV3);
  }
  return common::Result<MigrationSourceKind>::failure(
      corrupted("SQLite cutover source kind is invalid",
                kCutoverJournalFileName));
}

common::Result<common::Unit> call_migration_hook(
    const SqliteCalendarDatabase::MigrationFailureHook& hook,
    std::string_view phase) {
  if (!hook) {
    return common::Result<common::Unit>::success(common::Unit{});
  }
  try {
    return hook(phase);
  } catch (const std::exception& error) {
    return common::Result<common::Unit>::failure(filesystem_io_error(
        "migration_failure_hook", kCutoverJournalFileName, error.what()));
  } catch (...) {
    return common::Result<common::Unit>::failure(filesystem_io_error(
        "migration_failure_hook", kCutoverJournalFileName,
        "unknown failure hook exception"));
  }
}

common::Result<picojson::value> guarded_json_root(
    const JsonGuardSpec& spec,
    const std::optional<picojson::value>& source_root) {
  picojson::value guarded;
  if (source_root.has_value()) {
    if (!source_root->is<picojson::object>()) {
      return common::Result<picojson::value>::failure(
          corrupted("JSON source root must be an object", spec.file_name));
    }
    guarded = *source_root;
  } else {
    guarded = picojson::value(picojson::object{});
    if (spec.collection_field != nullptr) {
      guarded.get<picojson::object>()[spec.collection_field] =
          picojson::value(picojson::array{});
    }
  }
  guarded.get<picojson::object>()["storage_version"] = picojson::value(
      static_cast<double>(kCalendarCoreSqliteStorageVersion));
  return common::Result<picojson::value>::success(std::move(guarded));
}

picojson::value encode_cutover_journal(const CutoverJournal& journal) {
  picojson::object source_roots;
  for (const auto& spec : kJsonWriterGuards) {
    const auto found = journal.source_roots.find(spec.file_name);
    source_roots[spec.file_name] =
        found != journal.source_roots.end() && found->second.has_value()
            ? *found->second
            : picojson::value();
  }
  picojson::object root;
  root["storage_version"] = picojson::value(
      static_cast<double>(kCalendarCoreSqliteStorageVersion));
  root["journal_version"] = picojson::value(1.0);
  root["migration_id"] = picojson::value(kCutoverMigrationId);
  root["state"] = picojson::value(journal.state);
  root["source_kind"] = picojson::value(source_kind_name(journal.source_kind));
  root["source_roots"] = picojson::value(std::move(source_roots));
  return picojson::value(std::move(root));
}

common::Result<CutoverJournal> decode_cutover_journal(
    const picojson::value& root) {
  if (!root.is<picojson::object>()) {
    return common::Result<CutoverJournal>::failure(
        corrupted("SQLite cutover journal must be an object",
                  kCutoverJournalFileName));
  }
  const auto& object = root.get<picojson::object>();
  const std::set<std::string> fields{
      "storage_version", "journal_version", "migration_id",
      "state",           "source_kind",     "source_roots"};
  if (object.size() != fields.size()) {
    return common::Result<CutoverJournal>::failure(
        corrupted("SQLite cutover journal fields are invalid",
                  kCutoverJournalFileName));
  }
  for (const auto& field : fields) {
    if (object.find(field) == object.end()) {
      return common::Result<CutoverJournal>::failure(
          corrupted("SQLite cutover journal field is missing", field));
    }
  }
  if (!object.at("storage_version").is<double>() ||
      object.at("storage_version").get<double>() != 4.0 ||
      !object.at("journal_version").is<double>() ||
      object.at("journal_version").get<double>() != 1.0 ||
      !object.at("migration_id").is<std::string>() ||
      object.at("migration_id").get<std::string>() != kCutoverMigrationId ||
      !object.at("state").is<std::string>() ||
      !object.at("source_kind").is<std::string>() ||
      !object.at("source_roots").is<picojson::object>()) {
    return common::Result<CutoverJournal>::failure(
        corrupted("SQLite cutover journal metadata is invalid",
                  kCutoverJournalFileName));
  }
  const auto& state = object.at("state").get<std::string>();
  if (state != "prepared" && state != "guards_installed") {
    return common::Result<CutoverJournal>::failure(
        corrupted("SQLite cutover journal state is invalid",
                  kCutoverJournalFileName));
  }
  auto source_kind =
      parse_source_kind(object.at("source_kind").get<std::string>());
  if (!source_kind.ok()) {
    return common::Result<CutoverJournal>::failure(source_kind.error());
  }
  const auto& roots = object.at("source_roots").get<picojson::object>();
  if (roots.size() != kJsonWriterGuards.size()) {
    return common::Result<CutoverJournal>::failure(
        corrupted("SQLite cutover source snapshot is incomplete",
                  kCutoverJournalFileName));
  }
  CutoverJournal journal;
  journal.source_kind = source_kind.value();
  journal.state = state;
  for (const auto& spec : kJsonWriterGuards) {
    const auto found = roots.find(spec.file_name);
    if (found == roots.end() ||
        (!found->second.is<picojson::object>() &&
         !found->second.is<picojson::null>())) {
      return common::Result<CutoverJournal>::failure(
          corrupted("SQLite cutover source root is invalid", spec.file_name));
    }
    journal.source_roots[spec.file_name] =
        found->second.is<picojson::null>()
            ? std::optional<picojson::value>{}
            : std::optional<picojson::value>{found->second};
  }
  return common::Result<CutoverJournal>::success(std::move(journal));
}

using DurableJsonStore = storage::json::AtomicJsonFileStore;

DurableJsonStore cutover_json_store(
    const std::filesystem::path& storage_directory) {
  return DurableJsonStore(
      storage_directory, DurableJsonStore::FailureHook{},
      DurableJsonStore::DirectorySyncFailurePolicy::kRestorePreviousSnapshot);
}

common::Result<std::optional<CutoverJournal>> read_cutover_journal(
    const std::filesystem::path& storage_directory) {
  auto store = cutover_json_store(storage_directory);
  auto root = store.read_json_file(kCutoverJournalFileName);
  if (!root.ok()) {
    return common::Result<std::optional<CutoverJournal>>::failure(root.error());
  }
  if (!root.value().has_value()) {
    return common::Result<std::optional<CutoverJournal>>::success(std::nullopt);
  }
  auto decoded = decode_cutover_journal(*root.value());
  return decoded.ok()
             ? common::Result<std::optional<CutoverJournal>>::success(
                   std::move(decoded.value()))
             : common::Result<std::optional<CutoverJournal>>::failure(
                   decoded.error());
}

common::Result<common::Unit> write_cutover_journal(
    const std::filesystem::path& storage_directory,
    const CutoverJournal& journal) {
  auto store = cutover_json_store(storage_directory);
  return store.write_json_file(kCutoverJournalFileName,
                               encode_cutover_journal(journal));
}

common::Result<CutoverJournal> capture_cutover_journal(
    const std::filesystem::path& storage_directory,
    MigrationSourceKind source_kind) {
  auto store = cutover_json_store(storage_directory);
  CutoverJournal journal;
  journal.source_kind = source_kind;
  journal.state = "prepared";
  for (const auto& spec : kJsonWriterGuards) {
    auto root = store.read_json_file(spec.file_name);
    if (!root.ok()) {
      return common::Result<CutoverJournal>::failure(root.error());
    }
    journal.source_roots[spec.file_name] = std::move(root.value());
  }
  return common::Result<CutoverJournal>::success(std::move(journal));
}

bool same_root(const std::optional<picojson::value>& left,
               const std::optional<picojson::value>& right) {
  if (left.has_value() != right.has_value()) return false;
  return !left.has_value() || left->serialize() == right->serialize();
}

bool missing_root_requires_guard(std::string_view file_name,
                                 MigrationSourceKind source_kind) {
  if (source_kind == MigrationSourceKind::kFresh &&
      find_store(file_name) != nullptr) {
    return true;
  }
  return file_name == "storage_migrations.json" ||
         file_name == "events.json" || file_name == "reminders.json" ||
         file_name == "notifications.json";
}

common::Result<common::Unit> apply_cutover_guards(
    const std::filesystem::path& storage_directory, CutoverJournal& journal,
    const SqliteCalendarDatabase::MigrationFailureHook& hook) {
  auto store = cutover_json_store(storage_directory);
  for (const auto& spec : kJsonWriterGuards) {
    const auto source = journal.source_roots.find(spec.file_name);
    if (source == journal.source_roots.end()) {
      return common::Result<common::Unit>::failure(
          corrupted("SQLite cutover source snapshot is incomplete",
                    spec.file_name));
    }
    auto current = store.read_json_file(spec.file_name);
    if (!current.ok()) {
      return common::Result<common::Unit>::failure(current.error());
    }
    if (!source->second.has_value() && !current.value().has_value() &&
        !missing_root_requires_guard(spec.file_name, journal.source_kind)) {
      const std::string phase =
          std::string("cutover_after_json_guard:") + spec.file_name;
      auto hooked = call_migration_hook(hook, phase);
      if (!hooked.ok()) return hooked;
      continue;
    }
    auto guarded = guarded_json_root(spec, source->second);
    if (!guarded.ok()) {
      return common::Result<common::Unit>::failure(guarded.error());
    }
    const std::optional<picojson::value> expected_guard{guarded.value()};
    if (!same_root(current.value(), expected_guard)) {
      if (!same_root(current.value(), source->second)) {
        return common::Result<common::Unit>::failure(corrupted(
            "JSON source changed after the SQLite candidate was prepared; "
            "database publication is blocked",
            spec.file_name));
      }
      auto written = store.write_json_file(spec.file_name, guarded.value());
      if (!written.ok()) return written;
    }
    const std::string phase =
        std::string("cutover_after_json_guard:") + spec.file_name;
    auto hooked = call_migration_hook(hook, phase);
    if (!hooked.ok()) return hooked;
  }
  journal.state = "guards_installed";
  auto persisted = write_cutover_journal(storage_directory, journal);
  if (!persisted.ok()) return persisted;
  return call_migration_hook(hook, "cutover_after_guards_installed");
}

common::Result<MigrationSourceKind> inspect_migration_source(
    const std::filesystem::path& storage_directory) {
  auto legacy = has_legacy_v1_source(storage_directory);
  if (!legacy.ok()) {
    return common::Result<MigrationSourceKind>::failure(legacy.error());
  }
  if (legacy.value()) {
    return common::Result<MigrationSourceKind>::success(
        MigrationSourceKind::kJsonV1);
  }

  auto store = cutover_json_store(storage_directory);
  bool has_known_source = false;
  bool has_v2 = false;
  bool has_v3 = false;
  for (const auto& spec : kStoreSpecs) {
    auto root = store.read_json_file(spec.file_name);
    if (!root.ok()) {
      return common::Result<MigrationSourceKind>::failure(root.error());
    }
    if (!root.value().has_value()) continue;
    has_known_source = true;
    if (!root.value()->is<picojson::object>()) {
      return common::Result<MigrationSourceKind>::failure(
          corrupted("JSON source root must be an object", spec.file_name));
    }
    const auto version =
        root.value()->get<picojson::object>().find("storage_version");
    if (version == root.value()->get<picojson::object>().end() ||
        !version->second.is<double>()) {
      return common::Result<MigrationSourceKind>::failure(
          corrupted("JSON source storage_version is invalid", spec.file_name));
    }
    if (version->second.get<double>() == 2.0) has_v2 = true;
    if (version->second.get<double>() == 3.0) has_v3 = true;
    if (version->second.get<double>() == 4.0) {
      return common::Result<MigrationSourceKind>::failure(corrupted(
          "SQLite downgrade guard exists without its database",
          spec.file_name));
    }
  }

  auto migration_root = store.read_json_file("storage_migrations.json");
  if (!migration_root.ok()) {
    return common::Result<MigrationSourceKind>::failure(
        migration_root.error());
  }
  if (migration_root.value().has_value()) {
    has_known_source = true;
  }
  for (const auto& spec : kJsonWriterGuards) {
    std::error_code exists_error;
    const bool exists =
        std::filesystem::exists(storage_directory / spec.file_name, exists_error);
    if (exists_error) {
      return common::Result<MigrationSourceKind>::failure(
          invalid_path(storage_directory / spec.file_name));
    }
    has_known_source = has_known_source || exists;
  }
  if (!has_known_source) {
    return common::Result<MigrationSourceKind>::success(
        MigrationSourceKind::kFresh);
  }
  if (has_v2) {
    return common::Result<MigrationSourceKind>::success(
        MigrationSourceKind::kJsonV2);
  }
  // A known non-v1 source without v2 roots is validated by the frozen v3
  // bootstrap before it can be imported.
  static_cast<void>(has_v3);
  return common::Result<MigrationSourceKind>::success(
      MigrationSourceKind::kJsonV3);
}

bool retained_root_is_readable_by_json_writer(const StoreSpec& spec,
                                              const picojson::value& root,
                                              double source_version) {
  if (source_version == 1.0) {
    const auto file_name = std::string_view(spec.file_name);
    if (file_name == "events.json") {
      return storage::json::decode_legacy_event_store(root).ok();
    }
    if (file_name == "reminders.json") {
      return storage::json::decode_legacy_reminder_store(root).ok();
    }
    if (file_name == "notifications.json") {
      return storage::json::decode_legacy_notification_store(root).ok();
    }
    return false;
  }
  if (source_version != 3.0) return false;
  if (std::string_view(spec.file_name) == "categories.json") {
    return storage::json::decode_category_store(root, 3).ok();
  }
  repository::RecurringEventState state;
  return storage::json::decode_recurring_event_store(spec.file_name, root,
                                                      state)
      .ok();
}

common::Result<common::Unit> install_legacy_json_downgrade_guard(
    const std::filesystem::path& storage_directory, ::sqlite3* database) {
  auto store = cutover_json_store(storage_directory);
  for (const auto& spec : kStoreSpecs) {
    auto root = store.read_json_file(spec.file_name);
    if (!root.ok()) {
      // A malformed retained root already blocks every supported JSON reader.
      if (root.error().code == "STORAGE_DATA_CORRUPTED") continue;
      return common::Result<common::Unit>::failure(root.error());
    }
    if (!root.value().has_value()) {
      const auto file_name = std::string_view(spec.file_name);
      if (file_name != "events.json" && file_name != "reminders.json" &&
          file_name != "notifications.json") {
        continue;
      }
      JsonGuardSpec guard_spec{spec.file_name, spec.collection_field};
      auto guarded = guarded_json_root(guard_spec, std::nullopt);
      if (!guarded.ok()) {
        return common::Result<common::Unit>::failure(guarded.error());
      }
      auto written = store.write_json_file(spec.file_name, guarded.value());
      if (!written.ok()) return written;
      continue;
    }
    if (!root.value()->is<picojson::object>()) continue;
    const auto& object = root.value()->get<picojson::object>();
    const auto version = object.find("storage_version");
    if (version == object.end() || !version->second.is<double>()) continue;
    const double source_version = version->second.get<double>();
    if (source_version == 4.0) continue;

    if ((source_version == 1.0 || source_version == 3.0) &&
        !retained_root_is_readable_by_json_writer(spec, *root.value(),
                                                  source_version)) {
      JsonGuardSpec guard_spec{spec.file_name, spec.collection_field};
      auto guarded = guarded_json_root(guard_spec, *root.value());
      if (!guarded.ok()) {
        return common::Result<common::Unit>::failure(guarded.error());
      }
      auto written = store.write_json_file(spec.file_name, guarded.value());
      if (!written.ok()) return written;
      continue;
    }

    const StoreSpec* database_spec = nullptr;
    if (source_version == 3.0) database_spec = &spec;
    if (source_version == 1.0) {
      database_spec = find_legacy_store_by_file(spec.file_name);
    }
    if (database_spec == nullptr) {
      return common::Result<common::Unit>::failure(corrupted(
          "retained JSON and SQLite cannot be proven equivalent; refusing "
          "to hide possible post-cutover writes",
          spec.file_name));
    }
    auto database_root = read_store_root(database, *database_spec);
    if (!database_root.ok()) {
      return common::Result<common::Unit>::failure(database_root.error());
    }
    if (database_root.value().serialize() != root.value()->serialize()) {
      return common::Result<common::Unit>::failure(corrupted(
          "retained JSON differs from SQLite; possible interrupted legacy "
          "write detected",
          spec.file_name));
    }
    JsonGuardSpec guard_spec{spec.file_name, spec.collection_field};
    auto guarded = guarded_json_root(guard_spec, *root.value());
    if (!guarded.ok()) {
      return common::Result<common::Unit>::failure(guarded.error());
    }
    auto written = store.write_json_file(spec.file_name, guarded.value());
    if (!written.ok()) return written;
  }

  for (const auto& spec : kJsonWriterGuards) {
    if (find_store(spec.file_name) != nullptr) continue;
    auto root = store.read_json_file(spec.file_name);
    if (!root.ok()) {
      if (root.error().code == "STORAGE_DATA_CORRUPTED") continue;
      return common::Result<common::Unit>::failure(root.error());
    }
    if (!root.value().has_value() ||
        !root.value()->is<picojson::object>()) {
      continue;
    }
    const auto version =
        root.value()->get<picojson::object>().find("storage_version");
    if (version == root.value()->get<picojson::object>().end() ||
        !version->second.is<double>() || version->second.get<double>() == 4.0) {
      continue;
    }
    auto guarded = guarded_json_root(spec, *root.value());
    if (!guarded.ok()) {
      return common::Result<common::Unit>::failure(guarded.error());
    }
    auto written = store.write_json_file(spec.file_name, guarded.value());
    if (!written.ok()) return written;
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<common::Unit> write_migration_history(
    ::sqlite3* database, MigrationSourceKind source_kind) {
  switch (source_kind) {
    case MigrationSourceKind::kFresh:
      return execute_sql(
          database,
          "INSERT INTO migration_history("
          "migration_id,source_format,source_version,target_version,"
          "completed_at) VALUES('calendar_core_fresh_sqlite_v4',"
          "'none',0,4,strftime('%Y-%m-%dT%H:%M:%SZ','now'))",
          "write_fresh_storage_history");
    case MigrationSourceKind::kJsonV1:
      return execute_sql(
          database,
          "INSERT INTO migration_history("
          "migration_id,source_format,source_version,target_version,"
          "completed_at) VALUES("
          "'calendar_core_json_v1_compat_to_sqlite_v4',"
          "'excellent_calendar_core_json',1,4,"
          "strftime('%Y-%m-%dT%H:%M:%SZ','now'))",
          "write_v1_storage_history");
    case MigrationSourceKind::kJsonV2:
      return execute_sql(
          database,
          "INSERT INTO migration_history("
          "migration_id,source_format,source_version,target_version,"
          "completed_at) VALUES("
          "'calendar_core_json_v2_to_v3_anniversary_reminder_r1',"
          "'excellent_calendar_core_json',2,3,"
          "strftime('%Y-%m-%dT%H:%M:%SZ','now'));"
          "INSERT INTO migration_history("
          "migration_id,source_format,source_version,target_version,"
          "completed_at) VALUES('calendar_core_json_v3_to_sqlite_v4',"
          "'excellent_calendar_core_json',3,4,"
          "strftime('%Y-%m-%dT%H:%M:%SZ','now'))",
          "write_v2_storage_history");
    case MigrationSourceKind::kJsonV3:
      return execute_sql(
          database,
          "INSERT INTO migration_history("
          "migration_id,source_format,source_version,target_version,"
          "completed_at) VALUES('calendar_core_json_v3_to_sqlite_v4',"
          "'excellent_calendar_core_json',3,4,"
          "strftime('%Y-%m-%dT%H:%M:%SZ','now'))",
          "write_v3_storage_history");
  }
  return common::Result<common::Unit>::failure(
      corrupted("SQLite migration source kind is unsupported"));
}

}  // namespace

SqliteCalendarDatabase::SqliteCalendarDatabase(
    std::filesystem::path storage_directory,
    std::filesystem::path database_path, ::sqlite3* database)
    : storage_directory_(std::move(storage_directory)),
      database_path_(std::move(database_path)),
      database_(database) {}

SqliteCalendarDatabase::~SqliteCalendarDatabase() {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  if (database_ != nullptr) {
    ::sqlite3_close_v2(database_);
    database_ = nullptr;
  }
}

common::Result<std::shared_ptr<SqliteCalendarDatabase>>
SqliteCalendarDatabase::open(
    std::filesystem::path storage_directory,
    MigrationFailureHook migration_failure_hook) {
  if (storage_directory.empty()) {
    return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
        invalid_path(storage_directory));
  }
  std::error_code filesystem_error;
  std::filesystem::create_directories(storage_directory, filesystem_error);
  if (filesystem_error || !std::filesystem::is_directory(storage_directory)) {
    return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
        invalid_path(storage_directory));
  }

  auto coordination_store = cutover_json_store(storage_directory);
  auto coordination_initialized = coordination_store.initialize();
  if (!coordination_initialized.ok()) {
    return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
        coordination_initialized.error());
  }
  auto directory_lock = coordination_store.acquire_directory_lock();

  const auto database_path = storage_directory / kCalendarCoreSqliteFileName;
  const auto migrating_path =
      storage_directory /
      (std::string(kCalendarCoreSqliteFileName) + ".migrating");

  auto open_existing_database = [&]()
      -> common::Result<std::shared_ptr<SqliteCalendarDatabase>> {
    ::sqlite3* raw_database = nullptr;
    const int code = ::sqlite3_open_v2(
        database_path.string().c_str(), &raw_database,
        SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nullptr);
    if (code != SQLITE_OK) {
      const auto error = sqlite_error(raw_database, "open_database", code);
      if (raw_database != nullptr) ::sqlite3_close_v2(raw_database);
      return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
          error);
    }
    auto database =
        std::shared_ptr<SqliteCalendarDatabase>(new SqliteCalendarDatabase(
            storage_directory, database_path, raw_database));
    auto configured = database->configure_connection(true);
    if (!configured.ok()) {
      return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
          configured.error());
    }
    auto valid = database->validate();
    if (!valid.ok()) {
      return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
          valid.error());
    }

    auto cutover = read_cutover_journal(storage_directory);
    if (!cutover.ok()) {
      return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
          cutover.error());
    }
    if (cutover.value().has_value()) {
      auto journal = std::move(*cutover.value());
      auto guarded = apply_cutover_guards(storage_directory, journal, {});
      if (!guarded.ok()) {
        return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
            guarded.error());
      }
      auto removed_journal =
          coordination_store.remove_file(kCutoverJournalFileName);
      if (!removed_journal.ok()) {
        return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
            removed_journal.error());
      }
      auto hooked = call_migration_hook(
          migration_failure_hook, "cutover_after_journal_cleanup");
      if (!hooked.ok()) {
        return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
            hooked.error());
      }
    } else {
      auto guarded = install_legacy_json_downgrade_guard(
          storage_directory, database->database_);
      if (!guarded.ok()) {
        return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
            guarded.error());
      }
    }
    return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::success(
        std::move(database));
  };

  if (std::filesystem::exists(database_path)) {
    return open_existing_database();
  }

  auto pending_cutover = read_cutover_journal(storage_directory);
  if (!pending_cutover.ok()) {
    return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
        pending_cutover.error());
  }
  if (pending_cutover.value().has_value()) {
    if (!std::filesystem::exists(migrating_path)) {
      return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
          corrupted("SQLite cutover candidate is missing",
                    migrating_path.filename().string()));
    }
    ::sqlite3* raw_candidate = nullptr;
    const int candidate_code = ::sqlite3_open_v2(
        migrating_path.string().c_str(), &raw_candidate,
        SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nullptr);
    if (candidate_code != SQLITE_OK) {
      const auto error =
          sqlite_error(raw_candidate, "reopen_migration_candidate",
                       candidate_code);
      if (raw_candidate != nullptr) ::sqlite3_close_v2(raw_candidate);
      return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
          error);
    }
    auto candidate =
        std::shared_ptr<SqliteCalendarDatabase>(new SqliteCalendarDatabase(
            storage_directory, migrating_path, raw_candidate));
    auto configured = candidate->configure_connection(false);
    if (!configured.ok()) {
      return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
          configured.error());
    }
    auto valid = candidate->validate();
    if (!valid.ok()) {
      return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
          valid.error());
    }
    candidate.reset();
    auto journal = std::move(*pending_cutover.value());
    auto guarded = apply_cutover_guards(storage_directory, journal,
                                        migration_failure_hook);
    if (!guarded.ok()) {
      return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
          guarded.error());
    }
    auto published =
        publish_database_atomically(migrating_path, database_path);
    if (!published.ok()) {
      return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
          published.error());
    }
    auto hooked = call_migration_hook(migration_failure_hook,
                                      "cutover_after_database_publish");
    if (!hooked.ok()) {
      return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
          hooked.error());
    }
    return open_existing_database();
  }

  auto removed = remove_stale_database_files(migrating_path);
  if (!removed.ok()) {
    return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
        removed.error());
  }

  repository::RecurringEventState recurring_state;
  repository::CategoryState category_state;
  std::vector<domain::Event> legacy_events;
  std::vector<domain::Reminder> legacy_reminders;
  std::vector<domain::Notification> legacy_notifications;

  auto source_kind = inspect_migration_source(storage_directory);
  if (!source_kind.ok()) {
    return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
        source_kind.error());
  }
  CutoverJournal cutover_journal;
  if (source_kind.value() == MigrationSourceKind::kJsonV1) {
    storage::json::JsonEventReminderTransaction event_transaction(
        storage_directory);
    auto event_recovered = event_transaction.initialize();
    if (!event_recovered.ok()) {
      return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
          event_recovered.error());
    }
    storage::json::JsonReminderNotificationTransaction notification_transaction(
        storage_directory);
    auto notification_recovered = notification_transaction.initialize();
    if (!notification_recovered.ok()) {
      return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
          notification_recovered.error());
    }
    storage::json::JsonEventRepository events(storage_directory);
    storage::json::JsonReminderRepository reminders(storage_directory);
    storage::json::JsonNotificationRepository notifications(storage_directory);
    auto events_initialized = events.initialize();
    auto reminders_initialized = reminders.initialize();
    auto notifications_initialized = notifications.initialize();
    if (!events_initialized.ok()) {
      return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
          events_initialized.error());
    }
    if (!reminders_initialized.ok()) {
      return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
          reminders_initialized.error());
    }
    if (!notifications_initialized.ok()) {
      return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
          notifications_initialized.error());
    }
    auto captured =
        capture_cutover_journal(storage_directory, source_kind.value());
    if (!captured.ok()) {
      return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
          captured.error());
    }
    cutover_journal = std::move(captured.value());
    auto loaded_events = events.find_all();
    auto loaded_reminders = reminders.find_all();
    auto loaded_notifications = notifications.find_all();
    if (!loaded_events.ok()) {
      return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
          loaded_events.error());
    }
    if (!loaded_reminders.ok()) {
      return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
          loaded_reminders.error());
    }
    if (!loaded_notifications.ok()) {
      return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
          loaded_notifications.error());
    }
    legacy_events = std::move(loaded_events.value());
    legacy_reminders = std::move(loaded_reminders.value());
    legacy_notifications = std::move(loaded_notifications.value());
  } else if (source_kind.value() != MigrationSourceKind::kFresh) {
    auto prepared_json =
        storage::json::prepare_calendar_core_v3_storage(storage_directory);
    if (!prepared_json.ok()) {
      return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
          prepared_json.error());
    }
    if (prepared_json.value().migrated || prepared_json.value().resumed) {
      source_kind = common::Result<MigrationSourceKind>::success(
          MigrationSourceKind::kJsonV2);
    }
    storage::json::JsonRecurringEventTransaction json_transaction(
        storage_directory);
    auto json_initialized = json_transaction.initialize();
    if (!json_initialized.ok()) {
      return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
          json_initialized.error());
    }
    storage::json::JsonCategoryRepository json_categories(
        storage_directory, {},
        storage::json::JsonCategoryRepository::FailureHook{}, 3);
    auto categories_initialized = json_categories.initialize();
    if (!categories_initialized.ok()) {
      return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
          categories_initialized.error());
    }
    auto captured =
        capture_cutover_journal(storage_directory, source_kind.value());
    if (!captured.ok()) {
      return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
          captured.error());
    }
    cutover_journal = std::move(captured.value());
    auto loaded_recurring = json_transaction.load();
    if (!loaded_recurring.ok()) {
      return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
          loaded_recurring.error());
    }
    recurring_state = std::move(loaded_recurring.value());
    auto loaded_categories = json_categories.load();
    if (!loaded_categories.ok()) {
      return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
          loaded_categories.error());
    }
    category_state = std::move(loaded_categories.value());
  } else {
    auto captured =
        capture_cutover_journal(storage_directory, source_kind.value());
    if (!captured.ok()) {
      return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
          captured.error());
    }
    cutover_journal = std::move(captured.value());
  }

  ::sqlite3* raw_database = nullptr;
  int code =
      ::sqlite3_open_v2(migrating_path.string().c_str(), &raw_database,
                        SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE |
                            SQLITE_OPEN_EXCLUSIVE | SQLITE_OPEN_FULLMUTEX,
                        nullptr);
  if (code != SQLITE_OK) {
    const auto error = sqlite_error(raw_database, "create_database", code);
    if (raw_database != nullptr) ::sqlite3_close_v2(raw_database);
    return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
        error);
  }
  auto candidate =
      std::shared_ptr<SqliteCalendarDatabase>(new SqliteCalendarDatabase(
          storage_directory, migrating_path, raw_database));
  auto configured = candidate->configure_connection(false);
  if (!configured.ok()) {
    return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
        configured.error());
  }
  repository::RecurringEventState empty_recurring;
  repository::CategoryState empty_categories;
  auto imported = candidate->transaction([&]() {
    auto schema = candidate->create_schema();
    if (!schema.ok()) return schema;
    auto recurring = candidate->write_recurring_changes_locked(empty_recurring,
                                                               recurring_state);
    if (!recurring.ok()) return recurring;
    auto categories = candidate->write_category_changes_locked(empty_categories,
                                                               category_state);
    if (!categories.ok()) return categories;
    auto events = candidate->write_legacy_events_locked(legacy_events);
    if (!events.ok()) return events;
    auto reminders = candidate->write_legacy_reminders_locked(legacy_reminders);
    if (!reminders.ok()) return reminders;
    auto notifications =
        candidate->write_legacy_notifications_locked(legacy_notifications);
    if (!notifications.ok()) return notifications;
    return write_migration_history(candidate->database_, source_kind.value());
  });
  if (!imported.ok()) {
    candidate.reset();
    remove_stale_database_files(migrating_path);
    return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
        imported.error());
  }
  auto candidate_valid = candidate->validate();
  if (!candidate_valid.ok()) {
    candidate.reset();
    remove_stale_database_files(migrating_path);
    return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
        candidate_valid.error());
  }
  const int cache_flush_code = ::sqlite3_db_cacheflush(candidate->database_);
  if (cache_flush_code != SQLITE_OK) {
    const auto error = sqlite_error(
        candidate->database_, "flush_migration_candidate", cache_flush_code);
    candidate.reset();
    remove_stale_database_files(migrating_path);
    return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
        error);
  }
  candidate.reset();

  auto candidate_synced = sync_file_to_disk(migrating_path);
  if (!candidate_synced.ok()) {
    remove_stale_database_files(migrating_path);
    return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
          candidate_synced.error());
  }
  auto hooked = call_migration_hook(migration_failure_hook,
                                    "cutover_after_candidate_sync");
  if (!hooked.ok()) {
    return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
        hooked.error());
  }
  auto journal_written =
      write_cutover_journal(storage_directory, cutover_journal);
  if (!journal_written.ok()) {
    return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
        journal_written.error());
  }
  hooked = call_migration_hook(migration_failure_hook,
                               "cutover_after_journal_prepared");
  if (!hooked.ok()) {
    return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
        hooked.error());
  }
  auto guarded = apply_cutover_guards(storage_directory, cutover_journal,
                                      migration_failure_hook);
  if (!guarded.ok()) {
    return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
        guarded.error());
  }
  auto published = publish_database_atomically(migrating_path, database_path);
  if (!published.ok()) {
    return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
        published.error());
  }
  hooked = call_migration_hook(migration_failure_hook,
                               "cutover_after_database_publish");
  if (!hooked.ok()) {
    return common::Result<std::shared_ptr<SqliteCalendarDatabase>>::failure(
        hooked.error());
  }
  return open_existing_database();
}

common::Result<common::Unit> SqliteCalendarDatabase::configure_connection(
    bool enable_wal) {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  int code = ::sqlite3_extended_result_codes(database_, 1);
  if (code == SQLITE_OK) code = ::sqlite3_busy_timeout(database_, 5000);
  if (code == SQLITE_OK) {
    code =
        ::sqlite3_db_config(database_, SQLITE_DBCONFIG_DEFENSIVE, 1, nullptr);
  }
  if (code != SQLITE_OK) {
    return common::Result<common::Unit>::failure(
        sqlite_error(database_, "configure_connection", code));
  }
  auto configured = execute_sql(database_,
                                "PRAGMA foreign_keys=ON;"
                                "PRAGMA synchronous=FULL;"
                                "PRAGMA temp_store=MEMORY;",
                                "configure_database");
  if (!configured.ok()) return configured;
  configured = execute_sql(database_,
                           enable_wal ? "PRAGMA journal_mode=WAL;"
                                        "PRAGMA wal_autocheckpoint=1000;"
                                      : "PRAGMA journal_mode=DELETE;",
                           "configure_journal");
  if (!configured.ok()) return configured;

  auto journal_mode =
      query_single_text(database_, "PRAGMA journal_mode", "read_journal_mode");
  auto foreign_keys =
      query_single_int(database_, "PRAGMA foreign_keys", "read_foreign_keys");
  auto synchronous =
      query_single_int(database_, "PRAGMA synchronous", "read_synchronous");
  auto temp_store =
      query_single_int(database_, "PRAGMA temp_store", "read_temp_store");
  if (!journal_mode.ok()) {
    return common::Result<common::Unit>::failure(journal_mode.error());
  }
  if (!foreign_keys.ok()) {
    return common::Result<common::Unit>::failure(foreign_keys.error());
  }
  if (!synchronous.ok()) {
    return common::Result<common::Unit>::failure(synchronous.error());
  }
  if (!temp_store.ok()) {
    return common::Result<common::Unit>::failure(temp_store.error());
  }
  const std::string expected_journal = enable_wal ? "wal" : "delete";
  if (journal_mode.value() != expected_journal) {
    return common::Result<common::Unit>::failure(invalid_configuration(
        "journal_mode", expected_journal, journal_mode.value()));
  }
  if (foreign_keys.value() != 1) {
    return common::Result<common::Unit>::failure(invalid_configuration(
        "foreign_keys", "1", std::to_string(foreign_keys.value())));
  }
  if (synchronous.value() != 2) {
    return common::Result<common::Unit>::failure(invalid_configuration(
        "synchronous", "2", std::to_string(synchronous.value())));
  }
  if (temp_store.value() != 2) {
    return common::Result<common::Unit>::failure(invalid_configuration(
        "temp_store", "2", std::to_string(temp_store.value())));
  }
  if (enable_wal) {
    auto checkpoint = query_single_int(database_, "PRAGMA wal_autocheckpoint",
                                       "read_wal_autocheckpoint");
    if (!checkpoint.ok()) {
      return common::Result<common::Unit>::failure(checkpoint.error());
    }
    if (checkpoint.value() != 1000) {
      return common::Result<common::Unit>::failure(invalid_configuration(
          "wal_autocheckpoint", "1000", std::to_string(checkpoint.value())));
    }
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<common::Unit> SqliteCalendarDatabase::create_schema() {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  auto common_schema = execute_sql(
      database_,
      "CREATE TABLE schema_metadata("
      "key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;"
      "CREATE TABLE store_generations("
      "store_name TEXT PRIMARY KEY,"
      "generation INTEGER NOT NULL CHECK(generation >= 0)) WITHOUT ROWID;"
      "CREATE TABLE migration_history("
      "migration_id TEXT PRIMARY KEY,"
      "source_format TEXT NOT NULL,"
      "source_version INTEGER NOT NULL,"
      "target_version INTEGER NOT NULL,"
      "completed_at TEXT NOT NULL) WITHOUT ROWID;",
      "create_schema_metadata");
  if (!common_schema.ok()) return common_schema;

  for (const auto& spec : kStoreSpecs) {
    auto created = execute_sql(
        database_,
        "CREATE TABLE " + std::string(spec.table_name) +
            "(record_key TEXT PRIMARY KEY,"
            "position INTEGER NOT NULL UNIQUE CHECK(position >= 0),"
            "payload_json TEXT NOT NULL CHECK(json_valid(payload_json))) "
            "WITHOUT ROWID;",
        std::string("create_") + spec.logical_name);
    if (!created.ok()) return created;
  }
  for (const auto& spec : kLegacyStoreSpecs) {
    auto created = execute_sql(
        database_,
        "CREATE TABLE " + std::string(spec.table_name) +
            "(record_key TEXT PRIMARY KEY,"
            "position INTEGER NOT NULL UNIQUE CHECK(position >= 0),"
            "payload_json TEXT NOT NULL CHECK(json_valid(payload_json))) "
            "WITHOUT ROWID;",
        std::string("create_") + spec.logical_name);
    if (!created.ok()) return created;
  }

  auto indexes = execute_sql(
      database_,
      "CREATE UNIQUE INDEX ux_recurrence_identity ON recurrence_versions("
      "json_extract(payload_json,'$.recurrence_id'),"
      "CAST(json_extract(payload_json,'$.revision') AS INTEGER));"
      "CREATE UNIQUE INDEX ux_occurrence_state_identity ON "
      "event_occurrence_states("
      "json_extract(payload_json,'$.event_id'),"
      "CAST(json_extract(payload_json,'$.recurrence_revision') AS INTEGER),"
      "json_extract(payload_json,'$.occurrence_key'));"
      "CREATE UNIQUE INDEX ux_reminder_recurring_identity ON reminders("
      "json_extract(payload_json,'$.target_id'),"
      "CAST(json_extract(payload_json,'$.recurrence_revision') AS INTEGER),"
      "json_extract(payload_json,'$.occurrence_key'),"
      "CAST(json_extract(payload_json,'$.advance_minutes') AS INTEGER),"
      "json_extract(payload_json,'$.methods')) "
      "WHERE json_extract(payload_json,'$.recurrence_revision') IS NOT NULL;"
      "CREATE UNIQUE INDEX ux_notification_attempt_id ON notifications("
      "json_extract(payload_json,'$.delivery_attempt_id'));"
      "CREATE UNIQUE INDEX ux_notification_prepared_delivery ON notifications("
      "json_extract(payload_json,'$.delivery_id')) "
      "WHERE json_extract(payload_json,'$.status')='prepared';"
      "CREATE UNIQUE INDEX ux_notification_sent_delivery ON notifications("
      "json_extract(payload_json,'$.delivery_id')) "
      "WHERE json_extract(payload_json,'$.status')='sent';"
      "CREATE UNIQUE INDEX ux_recovery_request_id ON reminder_recovery_batches("
      "json_extract(payload_json,'$.recovery_request_id'));"
      "CREATE UNIQUE INDEX ux_single_recovery_in_progress ON "
      "reminder_recovery_batches((1)) "
      "WHERE json_extract(payload_json,'$.status')='in_progress';"
      "CREATE UNIQUE INDEX ux_anniversary_template_identity ON "
      "anniversary_reminder_templates("
      "json_extract(payload_json,'$.anniversary_id'),"
      "CAST(json_extract(payload_json,'$.advance_days') AS INTEGER),"
      "json_extract(payload_json,'$.local_time'),"
      "json_extract(payload_json,'$.timezone_mode'),"
      "json_extract(payload_json,'$.method'));"
      "CREATE INDEX ix_reminders_schedulable ON reminders("
      "CAST(json_extract(payload_json,'$.is_enabled') AS INTEGER),"
      "json_extract(payload_json,'$.deleted_at'),"
      "json_extract(payload_json,'$.status'),"
      "json_extract(payload_json,'$.remind_at'), record_key);"
      "CREATE INDEX ix_events_active_time ON events("
      "json_extract(payload_json,'$.deleted_at'),"
      "json_extract(payload_json,'$.status'),"
      "json_extract(payload_json,'$.start_at'),"
      "json_extract(payload_json,'$.start_date'), record_key);"
      "CREATE INDEX ix_events_category ON events("
      "json_extract(payload_json,'$.category_id'),"
      "json_extract(payload_json,'$.deleted_at'));"
      "CREATE INDEX ix_notifications_reminder ON notifications("
      "json_extract(payload_json,'$.reminder_id'), position);"
      "CREATE INDEX ix_categories_active_order ON categories("
      "json_extract(payload_json,'$.deleted_at'),"
      "CAST(json_extract(payload_json,'$.sort_order') AS INTEGER),"
      "json_extract(payload_json,'$.created_at'), record_key);"
      "CREATE INDEX ix_legacy_reminders_schedulable ON legacy_reminders("
      "CAST(json_extract(payload_json,'$.is_enabled') AS INTEGER),"
      "json_extract(payload_json,'$.deleted_at'),"
      "json_extract(payload_json,'$.status'),"
      "json_extract(payload_json,'$.remind_at'), record_key);"
      "CREATE INDEX ix_legacy_notifications_reminder ON "
      "legacy_notifications(json_extract(payload_json,'$.reminder_id'),"
      "position);",
      "create_indexes");
  if (!indexes.ok()) return indexes;

  auto metadata = execute_sql(
      database_,
      "INSERT INTO schema_metadata(key,value) VALUES"
      "('format_name','excellent_calendar_core_sqlite'),"
      "('storage_format_version','4'),"
      "('record_payload_version','3');",
      "write_schema_metadata");
  if (!metadata.ok()) return metadata;

  auto generation = prepare(
      database_,
      "INSERT INTO store_generations(store_name,generation) VALUES(?1,0)",
      "initialize_store_generations");
  if (!generation.ok()) {
    return common::Result<common::Unit>::failure(generation.error());
  }
  for (const auto& spec : kStoreSpecs) {
    ::sqlite3_reset(generation.value().get());
    ::sqlite3_clear_bindings(generation.value().get());
    int code = ::sqlite3_bind_text(generation.value().get(), 1,
                                   spec.logical_name, -1, SQLITE_STATIC);
    if (code != SQLITE_OK ||
        ::sqlite3_step(generation.value().get()) != SQLITE_DONE) {
      return common::Result<common::Unit>::failure(sqlite_error(
          database_, "initialize_store_generations",
          code == SQLITE_OK ? ::sqlite3_errcode(database_) : code));
    }
  }
  for (const auto& spec : kLegacyStoreSpecs) {
    ::sqlite3_reset(generation.value().get());
    ::sqlite3_clear_bindings(generation.value().get());
    int code = ::sqlite3_bind_text(generation.value().get(), 1,
                                   spec.logical_name, -1, SQLITE_STATIC);
    if (code != SQLITE_OK ||
        ::sqlite3_step(generation.value().get()) != SQLITE_DONE) {
      return common::Result<common::Unit>::failure(sqlite_error(
          database_, "initialize_legacy_store_generations",
          code == SQLITE_OK ? ::sqlite3_errcode(database_) : code));
    }
  }
  return execute_sql(database_,
                     "PRAGMA application_id=1162035532; PRAGMA user_version=4;",
                     "write_sqlite_version");
}

common::Result<common::Unit> SqliteCalendarDatabase::validate() {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  return validate_locked();
}

common::Result<common::Unit> SqliteCalendarDatabase::validate_locked() {
  auto application_id = query_single_int(database_, "PRAGMA application_id",
                                         "read_application_id");
  if (!application_id.ok()) {
    return common::Result<common::Unit>::failure(application_id.error());
  }
  auto user_version =
      query_single_int(database_, "PRAGMA user_version", "read_user_version");
  if (!user_version.ok()) {
    return common::Result<common::Unit>::failure(user_version.error());
  }
  if (application_id.value() != kApplicationId ||
      user_version.value() != kCalendarCoreSqliteStorageVersion) {
    return common::Result<common::Unit>::failure(
        corrupted("SQLite application id or schema version is unsupported",
                  "user_version"));
  }
  for (const auto* table : kRequiredTables) {
    const auto expected = expected_table_schema(table);
    auto present =
        require_schema_object(database_, "table", table, expected);
    if (!present.ok()) return present;
  }
  for (const auto& index : kRequiredIndexes) {
    auto present =
        require_schema_object(database_, "index", index.name, index.sql);
    if (!present.ok()) return present;
  }
  auto format = query_single_text(
      database_, "SELECT value FROM schema_metadata WHERE key='format_name'",
      "read_format_name");
  auto version = query_single_text(
      database_,
      "SELECT value FROM schema_metadata WHERE key='storage_format_version'",
      "read_storage_version");
  auto payload_version = query_single_text(
      database_,
      "SELECT value FROM schema_metadata WHERE key='record_payload_version'",
      "read_payload_version");
  if (!format.ok())
    return common::Result<common::Unit>::failure(format.error());
  if (!version.ok()) {
    return common::Result<common::Unit>::failure(version.error());
  }
  if (!payload_version.ok()) {
    return common::Result<common::Unit>::failure(payload_version.error());
  }
  if (format.value() != kFormatName || version.value() != "4" ||
      payload_version.value() != "3") {
    return common::Result<common::Unit>::failure(
        corrupted("SQLite schema metadata is unsupported"));
  }
  // Repair only the exact history pair emitted by the pre-fix v1 importer. It
  // always wrote the v3 row from create_schema() and then the real v1 row.
  auto legacy_history = query_single_int(
      database_,
      "SELECT CASE WHEN (SELECT COUNT(*) FROM migration_history)=2 "
      "AND EXISTS(SELECT 1 FROM migration_history WHERE "
      "migration_id='calendar_core_json_v1_compat_to_sqlite_v4' AND "
      "source_format='excellent_calendar_core_json' AND source_version=1 "
      "AND target_version=4) "
      "AND EXISTS(SELECT 1 FROM migration_history WHERE "
      "migration_id='calendar_core_json_v3_to_sqlite_v4' AND "
      "source_format='excellent_calendar_core_json' AND source_version=3 "
      "AND target_version=4) THEN 1 ELSE 0 END",
      "detect_legacy_migration_history");
  if (!legacy_history.ok()) {
    return common::Result<common::Unit>::failure(legacy_history.error());
  }
  if (legacy_history.value() == 1) {
    auto repaired = execute_sql(
        database_,
        "DELETE FROM migration_history WHERE "
        "migration_id='calendar_core_json_v3_to_sqlite_v4'",
        "repair_legacy_migration_history");
    if (!repaired.ok()) return repaired;
  }

  auto legal_history = query_single_int(
      database_,
      "SELECT CASE WHEN "
      "((SELECT COUNT(*) FROM migration_history)=1 AND ("
      "EXISTS(SELECT 1 FROM migration_history WHERE "
      "migration_id='calendar_core_fresh_sqlite_v4' AND "
      "source_format='none' AND source_version=0 AND target_version=4) OR "
      "EXISTS(SELECT 1 FROM migration_history WHERE "
      "migration_id='calendar_core_json_v1_compat_to_sqlite_v4' AND "
      "source_format='excellent_calendar_core_json' AND source_version=1 "
      "AND target_version=4) OR "
      "EXISTS(SELECT 1 FROM migration_history WHERE "
      "migration_id='calendar_core_json_v3_to_sqlite_v4' AND "
      "source_format='excellent_calendar_core_json' AND source_version=3 "
      "AND target_version=4))) OR "
      "((SELECT COUNT(*) FROM migration_history)=2 AND "
      "EXISTS(SELECT 1 FROM migration_history WHERE "
      "migration_id='calendar_core_json_v2_to_v3_anniversary_reminder_r1' "
      "AND source_format='excellent_calendar_core_json' AND "
      "source_version=2 AND target_version=3) AND "
      "EXISTS(SELECT 1 FROM migration_history WHERE "
      "migration_id='calendar_core_json_v3_to_sqlite_v4' AND "
      "source_format='excellent_calendar_core_json' AND source_version=3 "
      "AND target_version=4)) THEN 1 ELSE 0 END",
      "validate_migration_history");
  if (!legal_history.ok()) {
    return common::Result<common::Unit>::failure(legal_history.error());
  }
  if (legal_history.value() != 1) {
    return common::Result<common::Unit>::failure(
        corrupted("SQLite migration history combination is invalid"));
  }
  auto quick_check =
      query_single_text(database_, "PRAGMA quick_check", "sqlite_quick_check");
  if (!quick_check.ok()) {
    return common::Result<common::Unit>::failure(quick_check.error());
  }
  if (quick_check.value() != "ok") {
    return common::Result<common::Unit>::failure(
        corrupted("SQLite quick_check failed: " + quick_check.value()));
  }
  for (const auto& spec : kStoreSpecs) {
    auto generation = generation_for(database_, spec.logical_name);
    if (!generation.ok()) {
      return common::Result<common::Unit>::failure(generation.error());
    }
  }
  for (const auto& spec : kLegacyStoreSpecs) {
    auto generation = generation_for(database_, spec.logical_name);
    if (!generation.ok()) {
      return common::Result<common::Unit>::failure(generation.error());
    }
  }
  auto recurring = load_recurring_state_locked();
  if (!recurring.ok()) {
    return common::Result<common::Unit>::failure(recurring.error());
  }
  auto categories = load_category_state_locked();
  if (!categories.ok()) {
    return common::Result<common::Unit>::failure(categories.error());
  }
  auto legacy_events = load_legacy_events_locked();
  if (!legacy_events.ok()) {
    return common::Result<common::Unit>::failure(legacy_events.error());
  }
  auto legacy_reminders = load_legacy_reminders_locked();
  if (!legacy_reminders.ok()) {
    return common::Result<common::Unit>::failure(legacy_reminders.error());
  }
  auto legacy_notifications = load_legacy_notifications_locked();
  return legacy_notifications.ok()
             ? common::Result<common::Unit>::success(common::Unit{})
             : common::Result<common::Unit>::failure(
                   legacy_notifications.error());
}

common::Result<common::Unit> SqliteCalendarDatabase::transaction(
    const Operation& operation) {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  if (!operation) {
    return common::Result<common::Unit>::failure(common::make_error(
        "NATIVE_INTERNAL_ERROR", "Native internal error",
        {{"reason", "SQLite transaction operation is missing"}}));
  }
  if (transaction_depth_ != 0U) {
    ++transaction_depth_;
    auto result = operation();
    --transaction_depth_;
    return result;
  }
  auto begun = execute_sql(database_, "BEGIN IMMEDIATE", "begin_transaction");
  if (!begun.ok()) return begun;
  transaction_depth_ = 1U;
  auto result = operation();
  transaction_depth_ = 0U;
  if (!result.ok()) {
    execute_sql(database_, "ROLLBACK", "rollback_transaction");
    return result;
  }
  auto committed = execute_sql(database_, "COMMIT", "commit_transaction");
  if (!committed.ok()) {
    execute_sql(database_, "ROLLBACK", "rollback_failed_commit");
    return committed;
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<repository::RecurringEventState>
SqliteCalendarDatabase::load_recurring_state() {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  return load_recurring_state_locked();
}

common::Result<repository::RecurringEventState>
SqliteCalendarDatabase::load_recurring_state_locked() {
  repository::RecurringEventState state;
  for (const auto* file_name : kRecurringStoreFiles) {
    const auto* spec = find_store(file_name);
    if (spec == nullptr) {
      return common::Result<repository::RecurringEventState>::failure(
          corrupted("SQLite Store mapping is missing", file_name));
    }
    auto root = read_store_root(database_, *spec);
    if (!root.ok()) {
      return common::Result<repository::RecurringEventState>::failure(
          root.error());
    }
    auto decoded = storage::json::decode_recurring_event_store(
        file_name, root.value(), state);
    if (!decoded.ok()) {
      return common::Result<repository::RecurringEventState>::failure(
          decoded.error());
    }
  }
  auto valid = storage::json::validate_recurring_event_state(state);
  return valid.ok() ? common::Result<repository::RecurringEventState>::success(
                          std::move(state))
                    : common::Result<repository::RecurringEventState>::failure(
                          valid.error());
}

common::Result<repository::AnniversaryState>
SqliteCalendarDatabase::load_anniversary_state() {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  return load_anniversary_state_locked();
}

common::Result<repository::AnniversaryState>
SqliteCalendarDatabase::load_anniversary_state_locked() {
  repository::AnniversaryState state;
  for (const auto* file_name : kAnniversaryStoreFiles) {
    const auto* spec = find_store(file_name);
    if (spec == nullptr) {
      return common::Result<repository::AnniversaryState>::failure(
          corrupted("SQLite Store mapping is missing", file_name));
    }
    auto root = read_store_root(database_, *spec);
    if (!root.ok()) {
      return common::Result<repository::AnniversaryState>::failure(
          root.error());
    }
    auto decoded =
        storage::json::decode_anniversary_store(file_name, root.value(), state);
    if (!decoded.ok()) {
      return common::Result<repository::AnniversaryState>::failure(
          decoded.error());
    }
  }
  auto valid = storage::json::validate_anniversary_state(state);
  return valid.ok() ? common::Result<repository::AnniversaryState>::success(
                          std::move(state))
                    : common::Result<repository::AnniversaryState>::failure(
                          valid.error());
}

common::Result<repository::AnniversaryOccurrenceSnapshot>
SqliteCalendarDatabase::load_anniversary_occurrence_snapshot() {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  auto state = load_anniversary_state_locked();
  if (!state.ok()) {
    return common::Result<repository::AnniversaryOccurrenceSnapshot>::failure(
        state.error());
  }
  auto anniversaries = generation_for(database_, "anniversaries");
  auto recurrences = generation_for(database_, "anniversary_recurrences");
  auto templates = generation_for(database_, "anniversary_reminder_templates");
  if (!anniversaries.ok()) {
    return common::Result<repository::AnniversaryOccurrenceSnapshot>::failure(
        anniversaries.error());
  }
  if (!recurrences.ok()) {
    return common::Result<repository::AnniversaryOccurrenceSnapshot>::failure(
        recurrences.error());
  }
  if (!templates.ok()) {
    return common::Result<repository::AnniversaryOccurrenceSnapshot>::failure(
        templates.error());
  }
  repository::AnniversaryOccurrenceSnapshot snapshot;
  snapshot.state = std::move(state.value());
  snapshot.generation = std::to_string(anniversaries.value()) + "-" +
                        std::to_string(recurrences.value()) + "-" +
                        std::to_string(templates.value());
  return common::Result<repository::AnniversaryOccurrenceSnapshot>::success(
      std::move(snapshot));
}

common::Result<repository::CategoryState>
SqliteCalendarDatabase::load_category_state() {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  return load_category_state_locked();
}

common::Result<repository::CategoryState>
SqliteCalendarDatabase::load_category_state_locked() {
  const auto* spec = find_store("categories.json");
  if (spec == nullptr) {
    return common::Result<repository::CategoryState>::failure(
        corrupted("SQLite Category Store mapping is missing"));
  }
  auto root = read_store_root(database_, *spec);
  if (!root.ok()) {
    return common::Result<repository::CategoryState>::failure(root.error());
  }
  auto records = storage::json::decode_category_store(root.value(), 3);
  return records.ok() ? storage::json::category_state_from_storage_records(
                            records.value())
                      : common::Result<repository::CategoryState>::failure(
                            records.error());
}

common::Result<std::vector<domain::Event>>
SqliteCalendarDatabase::load_legacy_events() {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  return load_legacy_events_locked();
}

common::Result<std::vector<domain::Event>>
SqliteCalendarDatabase::load_legacy_events_locked() {
  const auto* spec = find_legacy_store("legacy_events");
  if (spec == nullptr) {
    return common::Result<std::vector<domain::Event>>::failure(
        corrupted("SQLite legacy Event Store mapping is missing"));
  }
  auto root = read_store_root(database_, *spec);
  return root.ok() ? storage::json::decode_legacy_event_store(root.value())
                   : common::Result<std::vector<domain::Event>>::failure(
                         root.error());
}

common::Result<std::vector<domain::Reminder>>
SqliteCalendarDatabase::load_legacy_reminders() {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  return load_legacy_reminders_locked();
}

common::Result<std::vector<domain::Reminder>>
SqliteCalendarDatabase::load_legacy_reminders_locked() {
  const auto* spec = find_legacy_store("legacy_reminders");
  if (spec == nullptr) {
    return common::Result<std::vector<domain::Reminder>>::failure(
        corrupted("SQLite legacy Reminder Store mapping is missing"));
  }
  auto root = read_store_root(database_, *spec);
  return root.ok() ? storage::json::decode_legacy_reminder_store(root.value())
                   : common::Result<std::vector<domain::Reminder>>::failure(
                         root.error());
}

common::Result<std::vector<domain::Notification>>
SqliteCalendarDatabase::load_legacy_notifications() {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  return load_legacy_notifications_locked();
}

common::Result<std::vector<domain::Notification>>
SqliteCalendarDatabase::load_legacy_notifications_locked() {
  const auto* spec = find_legacy_store("legacy_notifications");
  if (spec == nullptr) {
    return common::Result<std::vector<domain::Notification>>::failure(
        corrupted("SQLite legacy Notification Store mapping is missing"));
  }
  auto root = read_store_root(database_, *spec);
  return root.ok()
             ? storage::json::decode_legacy_notification_store(root.value())
             : common::Result<std::vector<domain::Notification>>::failure(
                   root.error());
}

common::Result<common::Unit> SqliteCalendarDatabase::write_legacy_events(
    const std::vector<domain::Event>& events) {
  return transaction([&]() { return write_legacy_events_locked(events); });
}

common::Result<common::Unit> SqliteCalendarDatabase::write_legacy_events_locked(
    const std::vector<domain::Event>& events) {
  const auto* spec = find_legacy_store("legacy_events");
  if (spec == nullptr) {
    return common::Result<common::Unit>::failure(
        corrupted("SQLite legacy Event Store mapping is missing"));
  }
  return replace_store_root(database_, *spec,
                            storage::json::encode_legacy_event_store(events));
}

common::Result<common::Unit> SqliteCalendarDatabase::write_legacy_reminders(
    const std::vector<domain::Reminder>& reminders) {
  return transaction(
      [&]() { return write_legacy_reminders_locked(reminders); });
}

common::Result<common::Unit>
SqliteCalendarDatabase::write_legacy_reminders_locked(
    const std::vector<domain::Reminder>& reminders) {
  const auto* spec = find_legacy_store("legacy_reminders");
  if (spec == nullptr) {
    return common::Result<common::Unit>::failure(
        corrupted("SQLite legacy Reminder Store mapping is missing"));
  }
  return replace_store_root(
      database_, *spec, storage::json::encode_legacy_reminder_store(reminders));
}

common::Result<common::Unit> SqliteCalendarDatabase::write_legacy_notifications(
    const std::vector<domain::Notification>& notifications) {
  return transaction(
      [&]() { return write_legacy_notifications_locked(notifications); });
}

common::Result<common::Unit>
SqliteCalendarDatabase::write_legacy_notifications_locked(
    const std::vector<domain::Notification>& notifications) {
  const auto* spec = find_legacy_store("legacy_notifications");
  if (spec == nullptr) {
    return common::Result<common::Unit>::failure(
        corrupted("SQLite legacy Notification Store mapping is missing"));
  }
  return replace_store_root(
      database_, *spec,
      storage::json::encode_legacy_notification_store(notifications));
}

common::Result<common::Unit> SqliteCalendarDatabase::write_recurring_changes(
    const repository::RecurringEventState& before,
    const repository::RecurringEventState& after) {
  return transaction(
      [&]() { return write_recurring_changes_locked(before, after); });
}

common::Result<common::Unit>
SqliteCalendarDatabase::write_recurring_changes_locked(
    const repository::RecurringEventState& before,
    const repository::RecurringEventState& after) {
  auto valid = storage::json::validate_recurring_event_state(after);
  if (!valid.ok()) return valid;
  for (const auto* file_name : kRecurringStoreFiles) {
    const auto* spec = find_store(file_name);
    if (spec == nullptr) {
      return common::Result<common::Unit>::failure(
          corrupted("SQLite Store mapping is missing", file_name));
    }
    auto previous =
        storage::json::encode_recurring_event_store(file_name, before);
    if (!previous.ok())
      return common::Result<common::Unit>::failure(previous.error());
    auto next = storage::json::encode_recurring_event_store(file_name, after);
    if (!next.ok()) return common::Result<common::Unit>::failure(next.error());
    if (previous.value().serialize() == next.value().serialize()) continue;
    auto replaced = replace_store_root(database_, *spec, next.value());
    if (!replaced.ok()) return replaced;
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<common::Unit> SqliteCalendarDatabase::write_anniversary_changes(
    const repository::AnniversaryState& before,
    const repository::AnniversaryState& after) {
  return transaction(
      [&]() { return write_anniversary_changes_locked(before, after); });
}

common::Result<common::Unit>
SqliteCalendarDatabase::write_anniversary_changes_locked(
    const repository::AnniversaryState& before,
    const repository::AnniversaryState& after) {
  auto valid = storage::json::validate_anniversary_state(after);
  if (!valid.ok()) return valid;
  for (const auto* file_name : kAnniversaryStoreFiles) {
    const auto* spec = find_store(file_name);
    if (spec == nullptr) {
      return common::Result<common::Unit>::failure(
          corrupted("SQLite Store mapping is missing", file_name));
    }
    auto previous = storage::json::encode_anniversary_store(file_name, before);
    if (!previous.ok())
      return common::Result<common::Unit>::failure(previous.error());
    auto next = storage::json::encode_anniversary_store(file_name, after);
    if (!next.ok()) return common::Result<common::Unit>::failure(next.error());
    if (previous.value().serialize() == next.value().serialize()) continue;
    auto replaced = replace_store_root(database_, *spec, next.value());
    if (!replaced.ok()) return replaced;
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<common::Unit> SqliteCalendarDatabase::write_category_changes(
    const repository::CategoryState& before,
    const repository::CategoryState& after) {
  return transaction(
      [&]() { return write_category_changes_locked(before, after); });
}

common::Result<common::Unit>
SqliteCalendarDatabase::write_category_changes_locked(
    const repository::CategoryState& before,
    const repository::CategoryState& after) {
  auto previous_records =
      storage::json::category_storage_records_from_state(before);
  if (!previous_records.ok()) {
    return common::Result<common::Unit>::failure(previous_records.error());
  }
  auto next_records = storage::json::category_storage_records_from_state(after);
  if (!next_records.ok()) {
    return common::Result<common::Unit>::failure(next_records.error());
  }
  auto previous =
      storage::json::encode_category_store(previous_records.value(), 3);
  if (!previous.ok())
    return common::Result<common::Unit>::failure(previous.error());
  auto next = storage::json::encode_category_store(next_records.value(), 3);
  if (!next.ok()) return common::Result<common::Unit>::failure(next.error());
  if (previous.value().serialize() == next.value().serialize()) {
    return common::Result<common::Unit>::success(common::Unit{});
  }
  const auto* spec = find_store("categories.json");
  if (spec == nullptr) {
    return common::Result<common::Unit>::failure(
        corrupted("SQLite Category Store mapping is missing"));
  }
  return replace_store_root(database_, *spec, next.value());
}

}  // namespace excellent_calendar::storage::sqlite
