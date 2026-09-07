#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>

#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/common/id_generator.hpp"
#include "excellent_calendar/storage/runtime_storage_lease.hpp"
#include "excellent_calendar/storage/sqlite/sqlite_calendar_database.hpp"

namespace {
using namespace excellent_calendar;
using storage::sqlite::SqliteCalendarDatabase;

void require(bool condition, const std::string& message) {
  if (!condition) throw std::runtime_error(message);
}

struct TempDirectory {
  std::filesystem::path path = std::filesystem::temp_directory_path() /
      ("calendar_sync_c0_" + common::generate_uuid_v4());
  TempDirectory() { std::filesystem::create_directories(path); }
  ~TempDirectory() {
    std::error_code error;
    std::filesystem::remove_all(path, error);
  }
};

repository::CategoryState category_state(const std::string& name) {
  repository::CategoryState state;
  domain::Category category;
  category.id = "11111111-1111-4111-8111-111111111111";
  category.name = name;
  category.color = "#008080";
  category.sort_order = 0;
  category.created_at = "2026-09-07T00:00:00Z";
  category.updated_at = category.created_at;
  state.categories.push_back(category);
  return state;
}

// Given two independent v5 databases with the SAME entity identity, successful
// writes and reopen must preserve each database's distinct value. This is a
// storage prerequisite, not evidence of a multi-workspace runtime registry.
void test_two_databases_preserve_identical_ids_independently() {
  TempDirectory first_dir, second_dir;
  auto first = SqliteCalendarDatabase::open(first_dir.path);
  auto second = SqliteCalendarDatabase::open(second_dir.path);
  require(first.ok() && second.ok(), "both real SQLite databases must open");
  const auto written = first.value()->write_category_changes({}, category_state("first"));
  require(written.ok(), "first database write must commit" +
      (written.ok() ? std::string{} : ": " + written.error().code + " " + written.error().message));
  require(second.value()->write_category_changes({}, category_state("second")).ok(),
          "second database write must commit");
  first.value().reset();
  second.value().reset();
  first = SqliteCalendarDatabase::open(first_dir.path);
  second = SqliteCalendarDatabase::open(second_dir.path);
  require(first.ok() && second.ok(), "both databases must pass checker on reopen");
  auto a = first.value()->load_category_state();
  auto b = second.value()->load_category_state();
  require(a.ok() && b.ok(), "both snapshots must load");
  require(a.value().categories.size() == 1 && b.value().categories.size() == 1,
          "no missing or duplicated entities");
  require(a.value().categories.front().name == "first" &&
              b.value().categories.front().name == "second",
          "identical IDs in different databases must not alias");
}

// Given a failed transaction in A and an independent committed transaction in B,
// A must be empty after reopen and B must retain its committed row.
void test_rollback_is_local_to_its_database() {
  TempDirectory first_dir, second_dir;
  auto first = SqliteCalendarDatabase::open(first_dir.path);
  auto second = SqliteCalendarDatabase::open(second_dir.path);
  require(first.ok() && second.ok(), "rollback fixtures must open");
  const auto result = first.value()->transaction([&]() {
    auto written = first.value()->write_category_changes({}, category_state("rollback"));
    if (!written.ok()) return written;
    auto independent = second.value()->write_category_changes({}, category_state("commit"));
    if (!independent.ok()) return independent;
    return common::Result<common::Unit>::failure(
        common::make_error("STORAGE_IO_ERROR", "injected before outer commit"));
  });
  require(!result.ok() && result.error().code == "STORAGE_IO_ERROR",
          "injected failure must reach caller");
  first.value().reset();
  second.value().reset();
  first = SqliteCalendarDatabase::open(first_dir.path);
  second = SqliteCalendarDatabase::open(second_dir.path);
  require(first.ok() && second.ok(), "both databases must reopen after rollback");
  auto a = first.value()->load_category_state();
  auto b = second.value()->load_category_state();
  require(a.ok() && a.value().categories.empty(), "failed database must have zero facts");
  require(b.ok() && b.value().categories.size() == 1 &&
              b.value().categories.front().name == "commit",
          "another database's commit must survive the failure");
}

// Revocation must be per-instance and repeatable. It must not poison a newly
// constructed lease or an unrelated live lease. No timing/sleep assumptions.
void test_writer_lease_revocation_is_per_instance() {
  storage::RuntimeStorageLease first, second;
  {
    auto outer = first.acquire();
    auto inner = first.acquire();
    require(outer.has_value() && inner.has_value(), "nested transaction lease must work");
  }
  first.revoke();
  first.revoke();
  require(!first.acquire().has_value(), "late writer must fail after repeated revoke");
  require(second.acquire().has_value(), "unrelated runtime writer must remain usable");
  storage::RuntimeStorageLease reopened;
  require(reopened.acquire().has_value(), "new runtime lease must be independent");
}
}  // namespace

int main() {
  try {
    test_two_databases_preserve_identical_ids_independently();
    test_rollback_is_local_to_its_database();
    test_writer_lease_revocation_is_per_instance();
    std::cout << "sync_v1_storage_baseline: 3 C0 scenarios passed; v6/sync NOT certified\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "sync_v1_storage_baseline failed: " << error.what() << '\n';
    return 1;
  }
}
