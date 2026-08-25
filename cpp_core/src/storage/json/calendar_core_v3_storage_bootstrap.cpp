#include "excellent_calendar/storage/json/calendar_core_v3_storage_bootstrap.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <iomanip>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

#include "excellent_calendar/common/clock.hpp"
#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/storage/json/anniversary_json_codec.hpp"
#include "excellent_calendar/storage/json/atomic_json_file_store.hpp"
#include "excellent_calendar/storage/json/calendar_core_v2_storage_bootstrap.hpp"
#include "excellent_calendar/storage/json/calendar_workflow_coordinator.hpp"
#include "excellent_calendar/storage/json/category_json_codec.hpp"
#include "excellent_calendar/storage/json/recurring_event_json_codec.hpp"

namespace excellent_calendar::storage::json {
namespace {

constexpr const char* kMigrationFile = "storage_migrations.json";
constexpr const char* kUnifiedJournalFile =
    "calendar_workflow_transactions.json";
constexpr const char* kLegacyWorkflowJournal = "workflow_transactions.json";
constexpr const char* kLegacyAnniversaryJournal =
    "anniversary_workflow_transactions.json";
constexpr const char* kMigrationId =
    "calendar_core_json_v2_to_v3_anniversary_reminder_r1";

struct Sha256 {
  std::array<std::uint32_t, 8> state = {
      0x6a09e667U, 0xbb67ae85U, 0x3c6ef372U, 0xa54ff53aU,
      0x510e527fU, 0x9b05688cU, 0x1f83d9abU, 0x5be0cd19U};
  std::array<std::uint8_t, 64> buffer{};
  std::size_t buffer_size = 0;
  std::uint64_t total_size = 0;
};

constexpr std::array<std::uint32_t, 64> kSha256Constants = {
    0x428a2f98U, 0x71374491U, 0xb5c0fbcfU, 0xe9b5dba5U,
    0x3956c25bU, 0x59f111f1U, 0x923f82a4U, 0xab1c5ed5U,
    0xd807aa98U, 0x12835b01U, 0x243185beU, 0x550c7dc3U,
    0x72be5d74U, 0x80deb1feU, 0x9bdc06a7U, 0xc19bf174U,
    0xe49b69c1U, 0xefbe4786U, 0x0fc19dc6U, 0x240ca1ccU,
    0x2de92c6fU, 0x4a7484aaU, 0x5cb0a9dcU, 0x76f988daU,
    0x983e5152U, 0xa831c66dU, 0xb00327c8U, 0xbf597fc7U,
    0xc6e00bf3U, 0xd5a79147U, 0x06ca6351U, 0x14292967U,
    0x27b70a85U, 0x2e1b2138U, 0x4d2c6dfcU, 0x53380d13U,
    0x650a7354U, 0x766a0abbU, 0x81c2c92eU, 0x92722c85U,
    0xa2bfe8a1U, 0xa81a664bU, 0xc24b8b70U, 0xc76c51a3U,
    0xd192e819U, 0xd6990624U, 0xf40e3585U, 0x106aa070U,
    0x19a4c116U, 0x1e376c08U, 0x2748774cU, 0x34b0bcb5U,
    0x391c0cb3U, 0x4ed8aa4aU, 0x5b9cca4fU, 0x682e6ff3U,
    0x748f82eeU, 0x78a5636fU, 0x84c87814U, 0x8cc70208U,
    0x90befffaU, 0xa4506cebU, 0xbef9a3f7U, 0xc67178f2U};

std::uint32_t rotate_right(std::uint32_t value, int bits) {
  return (value >> bits) | (value << (32 - bits));
}

void sha256_transform(Sha256& hash, const std::uint8_t* block) {
  std::array<std::uint32_t, 64> words{};
  for (std::size_t index = 0; index < 16; ++index) {
    words[index] = (static_cast<std::uint32_t>(block[index * 4]) << 24) |
                   (static_cast<std::uint32_t>(block[index * 4 + 1]) << 16) |
                   (static_cast<std::uint32_t>(block[index * 4 + 2]) << 8) |
                   static_cast<std::uint32_t>(block[index * 4 + 3]);
  }
  for (std::size_t index = 16; index < words.size(); ++index) {
    const auto s0 = rotate_right(words[index - 15], 7) ^
                    rotate_right(words[index - 15], 18) ^
                    (words[index - 15] >> 3);
    const auto s1 = rotate_right(words[index - 2], 17) ^
                    rotate_right(words[index - 2], 19) ^
                    (words[index - 2] >> 10);
    words[index] = words[index - 16] + s0 + words[index - 7] + s1;
  }
  auto a = hash.state[0];
  auto b = hash.state[1];
  auto c = hash.state[2];
  auto d = hash.state[3];
  auto e = hash.state[4];
  auto f = hash.state[5];
  auto g = hash.state[6];
  auto h = hash.state[7];
  for (std::size_t index = 0; index < words.size(); ++index) {
    const auto s1 = rotate_right(e, 6) ^ rotate_right(e, 11) ^
                    rotate_right(e, 25);
    const auto choice = (e & f) ^ ((~e) & g);
    const auto temp1 = h + s1 + choice + kSha256Constants[index] + words[index];
    const auto s0 = rotate_right(a, 2) ^ rotate_right(a, 13) ^
                    rotate_right(a, 22);
    const auto majority = (a & b) ^ (a & c) ^ (b & c);
    const auto temp2 = s0 + majority;
    h = g;
    g = f;
    f = e;
    e = d + temp1;
    d = c;
    c = b;
    b = a;
    a = temp1 + temp2;
  }
  hash.state[0] += a;
  hash.state[1] += b;
  hash.state[2] += c;
  hash.state[3] += d;
  hash.state[4] += e;
  hash.state[5] += f;
  hash.state[6] += g;
  hash.state[7] += h;
}

void sha256_update(Sha256& hash, std::string_view bytes) {
  for (const unsigned char byte : bytes) {
    hash.buffer[hash.buffer_size++] = byte;
    ++hash.total_size;
    if (hash.buffer_size == hash.buffer.size()) {
      sha256_transform(hash, hash.buffer.data());
      hash.buffer_size = 0;
    }
  }
}

std::string sha256_hex(std::string_view bytes) {
  Sha256 hash;
  sha256_update(hash, bytes);
  const auto bit_size = hash.total_size * 8U;
  hash.buffer[hash.buffer_size++] = 0x80U;
  if (hash.buffer_size > 56U) {
    while (hash.buffer_size < 64U) hash.buffer[hash.buffer_size++] = 0;
    sha256_transform(hash, hash.buffer.data());
    hash.buffer_size = 0;
  }
  while (hash.buffer_size < 56U) hash.buffer[hash.buffer_size++] = 0;
  for (int shift = 56; shift >= 0; shift -= 8) {
    hash.buffer[hash.buffer_size++] =
        static_cast<std::uint8_t>((bit_size >> shift) & 0xffU);
  }
  sha256_transform(hash, hash.buffer.data());
  std::ostringstream output;
  output << std::hex << std::setfill('0');
  for (const auto value : hash.state) output << std::setw(8) << value;
  return output.str();
}

common::Error corrupted(std::string reason, std::string field = "storage_directory") {
  return storage_data_corrupted(std::move(reason), std::move(field));
}

common::Result<common::Unit> call_hook(
    const StorageMigrationFailureHook& hook,
    std::string_view phase) {
  return hook ? hook(phase)
              : common::Result<common::Unit>::success(common::Unit{});
}

common::Result<int> storage_version(const picojson::value& root,
                                    std::string_view field) {
  if (!root.is<picojson::object>()) {
    return common::Result<int>::failure(corrupted("Store root must be object",
                                                  std::string(field)));
  }
  const auto& object = root.get<picojson::object>();
  const auto found = object.find("storage_version");
  if (found == object.end() || !found->second.is<double>() ||
      !std::isfinite(found->second.get<double>()) ||
      std::floor(found->second.get<double>()) != found->second.get<double>()) {
    return common::Result<int>::failure(
        corrupted("storage_version must be integer", std::string(field)));
  }
  return common::Result<int>::success(
      static_cast<int>(found->second.get<double>()));
}

picojson::value empty_store(const CalendarCoreV3StoreDefinition& store,
                            int version) {
  picojson::object root;
  root["storage_version"] = picojson::value(static_cast<double>(version));
  root[store.collection_name] = picojson::value(picojson::array{});
  return picojson::value(std::move(root));
}

std::set<std::string> legacy_hash_inputs() {
  std::set<std::string> names;
  for (const auto& store : calendar_core_v3_data_stores()) {
    names.insert(store.file_name);
  }
  names.insert(kLegacyWorkflowJournal);
  names.insert(kLegacyAnniversaryJournal);
  return names;
}

common::Result<picojson::object> parse_legacy_after_stores(
    const picojson::value& root,
    std::string_view journal_file) {
  if (!root.is<picojson::object>()) {
    return common::Result<picojson::object>::failure(
        calendar_workflow_recovery_failed("legacy journal root is invalid"));
  }
  const auto& object = root.get<picojson::object>();
  if (object.size() != 2U || object.find("storage_version") == object.end() ||
      object.find("transactions") == object.end() ||
      !object.at("storage_version").is<double>() ||
      object.at("storage_version").get<double>() != 2.0 ||
      !object.at("transactions").is<picojson::array>()) {
    return common::Result<picojson::object>::failure(
        calendar_workflow_recovery_failed("legacy journal envelope is invalid"));
  }
  const auto& transactions = object.at("transactions").get<picojson::array>();
  if (transactions.empty()) {
    return common::Result<picojson::object>::success(picojson::object{});
  }
  if (transactions.size() != 1U || !transactions.front().is<picojson::object>()) {
    return common::Result<picojson::object>::failure(
        calendar_workflow_recovery_failed("legacy journal transaction is invalid"));
  }
  const auto& item = transactions.front().get<picojson::object>();
  const std::set<std::string> fields = {
      "transaction_id", "operation", "intent_version", "intent",
      "affected_stores", "state", "prepared_at", "committed_at"};
  if (item.size() != fields.size()) {
    return common::Result<picojson::object>::failure(
        calendar_workflow_recovery_failed("legacy transaction fields are invalid"));
  }
  for (const auto& field : fields) {
    if (item.find(field) == item.end()) {
      return common::Result<picojson::object>::failure(
          calendar_workflow_recovery_failed("legacy transaction field is missing"));
    }
  }
  if (!item.at("transaction_id").is<std::string>() ||
      !common::is_uuid(item.at("transaction_id").get<std::string>()) ||
      !item.at("operation").is<std::string>() ||
      !item.at("intent_version").is<double>() ||
      item.at("intent_version").get<double>() != 1.0 ||
      !item.at("intent").is<picojson::object>() ||
      !item.at("affected_stores").is<picojson::array>() ||
      !item.at("state").is<std::string>() ||
      !item.at("prepared_at").is<std::string>() ||
      !common::is_iso8601_utc_datetime(
          item.at("prepared_at").get<std::string>())) {
    return common::Result<picojson::object>::failure(
        calendar_workflow_recovery_failed("legacy transaction values are invalid"));
  }
  const auto state = item.at("state").get<std::string>();
  if ((state == "prepared" && !item.at("committed_at").is<picojson::null>()) ||
      (state == "committed" &&
       (!item.at("committed_at").is<std::string>() ||
        !common::is_iso8601_utc_datetime(
            item.at("committed_at").get<std::string>()))) ||
      (state != "prepared" && state != "committed")) {
    return common::Result<picojson::object>::failure(
        calendar_workflow_recovery_failed("legacy transaction state is invalid"));
  }
  const auto& intent = item.at("intent").get<picojson::object>();
  if (intent.size() != 1U || intent.find("after_stores") == intent.end() ||
      !intent.at("after_stores").is<picojson::object>()) {
    return common::Result<picojson::object>::failure(
        calendar_workflow_recovery_failed("legacy intent is invalid"));
  }
  auto after = intent.at("after_stores").get<picojson::object>();
  std::set<std::string> affected;
  for (const auto& value : item.at("affected_stores").get<picojson::array>()) {
    if (!value.is<std::string>() ||
        !affected.insert(value.get<std::string>()).second) {
      return common::Result<picojson::object>::failure(
          calendar_workflow_recovery_failed("legacy affected stores are invalid"));
    }
  }
  if (after.size() != affected.size()) {
    return common::Result<picojson::object>::failure(
        calendar_workflow_recovery_failed("legacy after-state is incomplete"));
  }
  const bool anniversary_journal =
      journal_file == kLegacyAnniversaryJournal;
  const auto operation = item.at("operation").get<std::string>();
  const std::set<std::string> allowed_operations =
      anniversary_journal
          ? std::set<std::string>{"anniversary_create", "anniversary_update",
                                  "anniversary_delete",
                                  "anniversary_toggle_reminders",
                                  "anniversary_timezone_recalculate"}
          : std::set<std::string>{
                "event_recurrence_and_first_reminder_create_or_update",
                "occurrence_state_and_reminder_transition",
                "delivery_finalize_notification_reminder_and_successor",
                "recovery_batch_reminders_and_summary",
                "series_complete_cancel_delete_or_reopen"};
  if (allowed_operations.count(operation) == 0U) {
    return common::Result<picojson::object>::failure(
        calendar_workflow_recovery_failed("legacy operation is invalid"));
  }
  const std::set<std::string> frozen_v2_stores =
      anniversary_journal
          ? std::set<std::string>{"anniversaries", "anniversary_recurrences"}
          : std::set<std::string>{"events", "recurrence_versions",
                                  "event_occurrence_states", "reminders",
                                  "notifications", "reminder_recovery_batches"};
  const std::set<std::string> allowed = anniversary_journal
                                            ? std::set<std::string>{
                                                  "anniversaries",
                                                  "anniversary_recurrences",
                                                  "anniversary_reminder_templates",
                                                  "reminders"}
                                            : std::set<std::string>{
                                                  "events",
                                                  "recurrence_versions",
                                                  "event_occurrence_states",
                                                  "reminders", "notifications",
                                                  "reminder_recovery_batches",
                                                  "anniversaries",
                                                  "anniversary_recurrences",
                                                  "anniversary_reminder_templates"};
  if (affected != frozen_v2_stores && affected != allowed) {
    return common::Result<picojson::object>::failure(
        calendar_workflow_recovery_failed(
            "legacy affected stores do not match a supported journal version"));
  }
  repository::RecurringEventState validation;
  for (const auto& name : affected) {
    if (allowed.count(name) == 0U || after.find(name) == after.end()) {
      return common::Result<picojson::object>::failure(
          calendar_workflow_recovery_failed("legacy Store set is invalid"));
    }
    const auto found = std::find_if(
        calendar_core_v3_data_stores().begin(),
        calendar_core_v3_data_stores().end(),
        [&](const auto& store) { return name == store.logical_name; });
    if (found == calendar_core_v3_data_stores().end()) {
      return common::Result<picojson::object>::failure(
          calendar_workflow_recovery_failed("legacy Store is unknown"));
    }
    if (name == "categories") {
      auto decoded = decode_category_store(after.at(name), 2);
      if (!decoded.ok()) {
        return common::Result<picojson::object>::failure(decoded.error());
      }
    } else {
      auto decoded = decode_recurring_event_store_v2_for_migration(
          found->file_name, after.at(name), validation);
      if (!decoded.ok()) {
        return common::Result<picojson::object>::failure(decoded.error());
      }
    }
  }
  auto valid = validate_recurring_event_state(validation);
  if (!valid.ok()) {
    return common::Result<picojson::object>::failure(valid.error());
  }
  return common::Result<picojson::object>::success(std::move(after));
}

common::Result<common::Unit> recover_legacy_journal(
    AtomicJsonFileStore& store,
    const std::string& journal_file) {
  auto root = store.read_json_file(journal_file);
  if (!root.ok()) return common::Result<common::Unit>::failure(root.error());
  if (!root.value().has_value()) {
    return common::Result<common::Unit>::success(common::Unit{});
  }
  auto after = parse_legacy_after_stores(*root.value(), journal_file);
  if (!after.ok()) return common::Result<common::Unit>::failure(after.error());
  for (const auto& data_store : calendar_core_v3_data_stores()) {
    const auto found = after.value().find(data_store.logical_name);
    if (found == after.value().end()) continue;
    auto written = store.write_json_file(data_store.file_name, found->second);
    if (!written.ok()) {
      return common::Result<common::Unit>::failure(
          calendar_workflow_recovery_failed(written.error().message));
    }
  }
  picojson::object empty;
  empty["storage_version"] = picojson::value(2.0);
  empty["transactions"] = picojson::value(picojson::array{});
  return store.write_json_file(journal_file, picojson::value(std::move(empty)));
}

common::Result<picojson::object> load_v2_roots(AtomicJsonFileStore& store) {
  picojson::object roots;
  repository::RecurringEventState state;
  for (const auto& data_store : calendar_core_v3_data_stores()) {
    auto root = store.read_json_file(data_store.file_name);
    if (!root.ok()) return common::Result<picojson::object>::failure(root.error());
    if (!root.value().has_value()) continue;
    auto version = storage_version(*root.value(), data_store.file_name);
    if (!version.ok()) return common::Result<picojson::object>::failure(version.error());
    if (version.value() != 2) {
      return common::Result<picojson::object>::failure(
          corrupted("v2 migration input contains a non-v2 Store",
                    data_store.file_name));
    }
    if (std::string_view(data_store.logical_name) == "categories") {
      auto decoded = decode_category_store(*root.value(), 2);
      if (!decoded.ok()) {
        return common::Result<picojson::object>::failure(decoded.error());
      }
    } else {
      auto decoded = decode_recurring_event_store_v2_for_migration(
          data_store.file_name, *root.value(), state);
      if (!decoded.ok()) {
        return common::Result<picojson::object>::failure(decoded.error());
      }
    }
    roots[data_store.logical_name] = std::move(*root.value());
  }
  auto valid = validate_recurring_event_state(state);
  if (!valid.ok()) return common::Result<picojson::object>::failure(valid.error());
  return common::Result<picojson::object>::success(std::move(roots));
}

void add_nullable_if_missing(picojson::object& record, const char* field) {
  if (record.find(field) == record.end()) record[field] = picojson::value();
}

common::Result<picojson::object> build_v3_after_stores(
    const picojson::object& v2_roots) {
  picojson::object after;
  for (const auto& store : calendar_core_v3_data_stores()) {
    const auto source = v2_roots.find(store.logical_name);
    picojson::value target = source == v2_roots.end()
                                 ? empty_store(store, 3)
                                 : source->second;
    auto& root = target.get<picojson::object>();
    root["storage_version"] = picojson::value(3.0);
    auto& records = root.at(store.collection_name).get<picojson::array>();
    if (std::string_view(store.logical_name) == "anniversaries") {
      for (auto& value : records) {
        auto& record = value.get<picojson::object>();
        if (record.find("reminders_enabled") == record.end()) {
          record["reminders_enabled"] = picojson::value(false);
        }
      }
    } else if (std::string_view(store.logical_name) == "reminders") {
      for (auto& value : records) {
        auto& record = value.get<picojson::object>();
        for (const auto* field : {"template_key", "occurrence_date",
                                  "advance_days", "local_time",
                                  "timezone_mode", "fulfillment_delivery_id"}) {
          add_nullable_if_missing(record, field);
        }
      }
    } else if (std::string_view(store.logical_name) == "notifications") {
      for (auto& value : records) {
        auto& record = value.get<picojson::object>();
        if (record.find("covered_reminder_ids") == record.end()) {
          record["covered_reminder_ids"] = picojson::value(picojson::array{});
        }
      }
    } else if (std::string_view(store.logical_name) ==
               "reminder_recovery_batches") {
      for (auto& value : records) {
        auto& record = value.get<picojson::object>();
        if (record.find("anniversary_catch_up_groups") == record.end()) {
          record["anniversary_catch_up_groups"] =
              picojson::value(picojson::array{});
        }
      }
    }
    after[store.logical_name] = std::move(target);
  }
  after["calendar_workflow_transactions"] =
      CalendarWorkflowCoordinator::empty_journal();

  repository::RecurringEventState validation;
  for (const auto& store : calendar_core_v3_data_stores()) {
    if (std::string_view(store.logical_name) == "categories") {
      auto decoded = decode_category_store(after.at(store.logical_name), 3);
      if (!decoded.ok()) {
        return common::Result<picojson::object>::failure(decoded.error());
      }
    } else {
      auto decoded = decode_recurring_event_store(
          store.file_name, after.at(store.logical_name), validation);
      if (!decoded.ok()) {
        return common::Result<picojson::object>::failure(decoded.error());
      }
    }
  }
  auto valid = validate_recurring_event_state(validation);
  return valid.ok() ? common::Result<picojson::object>::success(std::move(after))
                    : common::Result<picojson::object>::failure(valid.error());
}

common::Result<picojson::object> source_hashes(AtomicJsonFileStore& store) {
  picojson::object hashes;
  for (const auto& file : legacy_hash_inputs()) {
    auto root = store.read_json_file(file);
    if (!root.ok()) {
      return common::Result<picojson::object>::failure(root.error());
    }
    if (!root.value().has_value()) {
      hashes[file] = picojson::value("missing");
    } else {
      hashes[file] = picojson::value(sha256_hex(root.value()->serialize()));
    }
  }
  return common::Result<picojson::object>::success(std::move(hashes));
}

picojson::value migration_root(
    std::string state,
    std::string phase,
    const picojson::object& hashes,
    const picojson::object& after_stores,
    const std::vector<std::string>& applied_stores,
    const std::string& prepared_at,
    std::optional<std::string> committed_at) {
  picojson::array applied;
  for (const auto& name : applied_stores) applied.emplace_back(name);
  picojson::object record;
  record["migration_id"] = picojson::value(kMigrationId);
  record["source_version"] = picojson::value(2.0);
  record["target_version"] = picojson::value(3.0);
  record["state"] = picojson::value(std::move(state));
  record["phase"] = picojson::value(std::move(phase));
  record["source_hashes"] = picojson::value(hashes);
  record["after_stores"] = picojson::value(after_stores);
  record["applied_stores"] = picojson::value(std::move(applied));
  record["prepared_at"] = picojson::value(prepared_at);
  record["committed_at"] = committed_at.has_value()
                               ? picojson::value(*committed_at)
                               : picojson::value();
  picojson::array migrations;
  migrations.emplace_back(std::move(record));
  picojson::object root;
  root["storage_version"] = picojson::value(3.0);
  root["migrations"] = picojson::value(std::move(migrations));
  return picojson::value(std::move(root));
}

struct ParsedMigration {
  std::string state;
  std::string phase;
  picojson::object source_hashes;
  picojson::object after_stores;
  std::vector<std::string> applied_stores;
  std::string prepared_at;
  std::optional<std::string> committed_at;
};

common::Result<ParsedMigration> parse_migration_root(
    const picojson::value& root) {
  if (!root.is<picojson::object>()) {
    return common::Result<ParsedMigration>::failure(
        calendar_workflow_recovery_failed("migration root must be object"));
  }
  const auto& object = root.get<picojson::object>();
  if (object.size() != 2U || object.find("storage_version") == object.end() ||
      object.find("migrations") == object.end() ||
      !object.at("storage_version").is<double>() ||
      object.at("storage_version").get<double>() != 3.0 ||
      !object.at("migrations").is<picojson::array>() ||
      object.at("migrations").get<picojson::array>().size() != 1U ||
      !object.at("migrations").get<picojson::array>().front().is<picojson::object>()) {
    return common::Result<ParsedMigration>::failure(
        calendar_workflow_recovery_failed("migration envelope is invalid"));
  }
  const auto& record = object.at("migrations")
                           .get<picojson::array>()
                           .front()
                           .get<picojson::object>();
  const std::set<std::string> fields = {
      "migration_id", "source_version", "target_version", "state", "phase",
      "source_hashes", "after_stores", "applied_stores", "prepared_at",
      "committed_at"};
  if (record.size() != fields.size()) {
    return common::Result<ParsedMigration>::failure(
        calendar_workflow_recovery_failed("migration fields are invalid"));
  }
  for (const auto& field : fields) {
    if (record.find(field) == record.end()) {
      return common::Result<ParsedMigration>::failure(
          calendar_workflow_recovery_failed("migration field is missing"));
    }
  }
  if (!record.at("migration_id").is<std::string>() ||
      record.at("migration_id").get<std::string>() != kMigrationId ||
      !record.at("source_version").is<double>() ||
      record.at("source_version").get<double>() != 2.0 ||
      !record.at("target_version").is<double>() ||
      record.at("target_version").get<double>() != 3.0 ||
      !record.at("state").is<std::string>() ||
      !record.at("phase").is<std::string>() ||
      !record.at("source_hashes").is<picojson::object>() ||
      !record.at("after_stores").is<picojson::object>() ||
      !record.at("applied_stores").is<picojson::array>() ||
      !record.at("prepared_at").is<std::string>() ||
      !common::is_iso8601_utc_datetime(
          record.at("prepared_at").get<std::string>())) {
    return common::Result<ParsedMigration>::failure(
        calendar_workflow_recovery_failed("migration values are invalid"));
  }
  ParsedMigration parsed;
  parsed.state = record.at("state").get<std::string>();
  parsed.phase = record.at("phase").get<std::string>();
  parsed.source_hashes = record.at("source_hashes").get<picojson::object>();
  parsed.after_stores = record.at("after_stores").get<picojson::object>();
  parsed.prepared_at = record.at("prepared_at").get<std::string>();
  const auto expected_hashes = legacy_hash_inputs();
  if (parsed.source_hashes.size() != expected_hashes.size()) {
    return common::Result<ParsedMigration>::failure(
        calendar_workflow_recovery_failed("migration source hashes are incomplete"));
  }
  for (const auto& file : expected_hashes) {
    const auto found = parsed.source_hashes.find(file);
    const auto valid_hash = [](const std::string& value) {
      return value.size() == 64U &&
             std::all_of(value.begin(), value.end(), [](char character) {
               return (character >= '0' && character <= '9') ||
                      (character >= 'a' && character <= 'f');
             });
    };
    if (found == parsed.source_hashes.end() || !found->second.is<std::string>() ||
        (found->second.get<std::string>() != "missing" &&
         !valid_hash(found->second.get<std::string>()))) {
      return common::Result<ParsedMigration>::failure(
          calendar_workflow_recovery_failed("migration source hash is invalid"));
    }
  }
  std::set<std::string> expected_after;
  for (const auto& store : calendar_core_v3_data_stores()) {
    expected_after.insert(store.logical_name);
  }
  expected_after.insert("calendar_workflow_transactions");
  if (parsed.after_stores.size() != expected_after.size()) {
    return common::Result<ParsedMigration>::failure(
        calendar_workflow_recovery_failed("migration after-images are incomplete"));
  }
  for (const auto& name : expected_after) {
    if (parsed.after_stores.find(name) == parsed.after_stores.end()) {
      return common::Result<ParsedMigration>::failure(
          calendar_workflow_recovery_failed("migration after-image is missing"));
    }
  }
  std::set<std::string> applied;
  for (const auto& value : record.at("applied_stores").get<picojson::array>()) {
    if (!value.is<std::string>() || expected_after.count(value.get<std::string>()) == 0U ||
        !applied.insert(value.get<std::string>()).second) {
      return common::Result<ParsedMigration>::failure(
          calendar_workflow_recovery_failed("migration applied Store list is invalid"));
    }
    parsed.applied_stores.push_back(value.get<std::string>());
  }
  if (parsed.state == "prepared") {
    if ((parsed.phase != "prepared" && parsed.phase != "applying") ||
        !record.at("committed_at").is<picojson::null>()) {
      return common::Result<ParsedMigration>::failure(
          calendar_workflow_recovery_failed("prepared migration state is invalid"));
    }
  } else if (parsed.state == "committed") {
    if (parsed.phase != "committed" ||
        !record.at("committed_at").is<std::string>() ||
        !common::is_iso8601_utc_datetime(
            record.at("committed_at").get<std::string>()) ||
        applied != expected_after) {
      return common::Result<ParsedMigration>::failure(
          calendar_workflow_recovery_failed("committed migration state is invalid"));
    }
    parsed.committed_at = record.at("committed_at").get<std::string>();
  } else {
    return common::Result<ParsedMigration>::failure(
        calendar_workflow_recovery_failed("migration state is invalid"));
  }
  return common::Result<ParsedMigration>::success(std::move(parsed));
}

common::Result<common::Unit> validate_v3_after_images(
    const picojson::object& after) {
  repository::RecurringEventState state;
  for (const auto& store : calendar_core_v3_data_stores()) {
    const auto found = after.find(store.logical_name);
    if (found == after.end()) {
      return common::Result<common::Unit>::failure(
          calendar_workflow_recovery_failed("v3 after-image is missing"));
    }
    if (std::string_view(store.logical_name) == "categories") {
      auto decoded = decode_category_store(found->second, 3);
      if (!decoded.ok()) return common::Result<common::Unit>::failure(decoded.error());
    } else {
      auto decoded = decode_recurring_event_store(store.file_name, found->second, state);
      if (!decoded.ok()) return decoded;
    }
  }
  auto valid = validate_recurring_event_state(state);
  if (!valid.ok()) return valid;
  const auto journal = after.find("calendar_workflow_transactions");
  if (journal == after.end() ||
      journal->second.serialize() !=
          CalendarWorkflowCoordinator::empty_journal().serialize()) {
    return common::Result<common::Unit>::failure(
        calendar_workflow_recovery_failed("initial unified journal is invalid"));
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<common::Unit> verify_resume_source(
    AtomicJsonFileStore& store,
    const ParsedMigration& migration) {
  for (const auto& data_store : calendar_core_v3_data_stores()) {
    auto current = store.read_json_file(data_store.file_name);
    if (!current.ok()) return common::Result<common::Unit>::failure(current.error());
    if (!current.value().has_value()) {
      const auto expected = migration.source_hashes.at(data_store.file_name)
                                .get<std::string>();
      if (expected != "missing") {
        return common::Result<common::Unit>::failure(
            calendar_workflow_recovery_failed(
                "migration source Store disappeared"));
      }
      continue;
    }
    auto version = storage_version(*current.value(), data_store.file_name);
    if (!version.ok()) return common::Result<common::Unit>::failure(version.error());
    if (version.value() == 3) {
      if (current.value()->serialize() !=
          migration.after_stores.at(data_store.logical_name).serialize()) {
        return common::Result<common::Unit>::failure(
            calendar_workflow_recovery_failed(
                "partially migrated Store differs from frozen after-image"));
      }
    } else if (version.value() == 2) {
      const auto expected = migration.source_hashes.at(data_store.file_name)
                                .get<std::string>();
      if (expected == "missing" ||
          sha256_hex(current.value()->serialize()) != expected) {
        return common::Result<common::Unit>::failure(
            calendar_workflow_recovery_failed(
                "migration source hash changed"));
      }
    } else {
      return common::Result<common::Unit>::failure(
          calendar_workflow_recovery_failed(
              "migration source has unsupported version"));
    }
  }
  return common::Result<common::Unit>::success(common::Unit{});
}

common::Result<common::Unit> apply_migration(
    AtomicJsonFileStore& store,
    ParsedMigration migration,
    const StorageMigrationFailureHook& failure_hook) {
  auto valid = validate_v3_after_images(migration.after_stores);
  if (!valid.ok()) {
    return common::Result<common::Unit>::failure(
        calendar_workflow_recovery_failed(valid.error().message));
  }
  auto source_valid = verify_resume_source(store, migration);
  if (!source_valid.ok()) return source_valid;

  std::vector<std::pair<std::string, std::string>> order;
  for (const auto& data_store : calendar_core_v3_data_stores()) {
    order.emplace_back(data_store.logical_name, data_store.file_name);
  }
  order.emplace_back("calendar_workflow_transactions", kUnifiedJournalFile);
  std::set<std::string> applied(migration.applied_stores.begin(),
                                migration.applied_stores.end());
  for (const auto& [logical_name, file_name] : order) {
    auto current = store.read_json_file(file_name);
    if (!current.ok()) return common::Result<common::Unit>::failure(current.error());
    if (!current.value().has_value() ||
        current.value()->serialize() !=
            migration.after_stores.at(logical_name).serialize()) {
      auto written = store.write_json_file(file_name,
                                           migration.after_stores.at(logical_name));
      if (!written.ok()) return written;
    }
    auto hook = call_hook(failure_hook,
                          std::string("migration_after_store:") + file_name);
    if (!hook.ok()) return hook;
    applied.insert(logical_name);
    migration.applied_stores.assign(applied.begin(), applied.end());
    auto progress = store.write_json_file(
        kMigrationFile,
        migration_root("prepared", "applying", migration.source_hashes,
                       migration.after_stores, migration.applied_stores,
                       migration.prepared_at, std::nullopt));
    if (!progress.ok()) return progress;
  }
  migration.applied_stores.assign(applied.begin(), applied.end());
  auto committed = store.write_json_file(
      kMigrationFile,
      migration_root("committed", "committed", migration.source_hashes,
                     migration.after_stores, migration.applied_stores,
                     migration.prepared_at, migration.prepared_at));
  if (!committed.ok()) return committed;
  auto hook = call_hook(failure_hook, "migration_after_commit");
  if (!hook.ok()) return hook;
  auto removed = store.remove_file(kLegacyWorkflowJournal);
  if (!removed.ok()) return removed;
  return store.remove_file(kLegacyAnniversaryJournal);
}

common::Result<common::Unit> validate_complete_v3(AtomicJsonFileStore& store) {
  repository::RecurringEventState state;
  for (const auto& data_store : calendar_core_v3_data_stores()) {
    auto root = store.read_json_file(data_store.file_name);
    if (!root.ok()) return common::Result<common::Unit>::failure(root.error());
    if (!root.value().has_value()) {
      return common::Result<common::Unit>::failure(
          corrupted("v3 Store is missing", data_store.file_name));
    }
    if (std::string_view(data_store.logical_name) == "categories") {
      auto decoded = decode_category_store(*root.value(), 3);
      if (!decoded.ok()) return common::Result<common::Unit>::failure(decoded.error());
    } else {
      auto decoded = decode_recurring_event_store(data_store.file_name,
                                                  *root.value(), state);
      if (!decoded.ok()) return decoded;
    }
  }
  return validate_recurring_event_state(state);
}

}  // namespace

common::Result<CalendarCoreV3StoragePreparation>
prepare_calendar_core_v3_storage(
    const std::filesystem::path& active_directory,
    StorageMigrationFailureHook failure_hook) {
  if (active_directory.empty()) {
    return common::Result<CalendarCoreV3StoragePreparation>::failure(
        common::make_error("STORAGE_PATH_INVALID",
                           "Storage path is invalid or not writable",
                           {{"reason", "path is empty"}}));
  }
  AtomicJsonFileStore store(
      active_directory, AtomicJsonFileStore::FailureHook{},
      AtomicJsonFileStore::DirectorySyncFailurePolicy::kRestorePreviousSnapshot);
  auto lock = store.acquire_directory_lock();
  auto initialized = store.initialize();
  if (!initialized.ok()) {
    return common::Result<CalendarCoreV3StoragePreparation>::failure(
        initialized.error());
  }

  auto migration_root_value = store.read_json_file(kMigrationFile);
  if (!migration_root_value.ok()) {
    return common::Result<CalendarCoreV3StoragePreparation>::failure(
        migration_root_value.error());
  }
  if (migration_root_value.value().has_value()) {
    auto parsed = parse_migration_root(*migration_root_value.value());
    if (!parsed.ok()) {
      return common::Result<CalendarCoreV3StoragePreparation>::failure(
          parsed.error());
    }
    if (parsed.value().state == "prepared") {
      auto resumed = apply_migration(store, parsed.value(), failure_hook);
      if (!resumed.ok()) {
        return common::Result<CalendarCoreV3StoragePreparation>::failure(
            resumed.error());
      }
      auto valid = validate_complete_v3(store);
      if (!valid.ok()) {
        return common::Result<CalendarCoreV3StoragePreparation>::failure(
            valid.error());
      }
      return common::Result<CalendarCoreV3StoragePreparation>::success(
          {true, true, false});
    }
    auto valid = validate_complete_v3(store);
    if (!valid.ok()) {
      return common::Result<CalendarCoreV3StoragePreparation>::failure(
          valid.error());
    }
    auto removed = store.remove_file(kLegacyWorkflowJournal);
    if (!removed.ok()) {
      return common::Result<CalendarCoreV3StoragePreparation>::failure(
          removed.error());
    }
    removed = store.remove_file(kLegacyAnniversaryJournal);
    if (!removed.ok()) {
      return common::Result<CalendarCoreV3StoragePreparation>::failure(
          removed.error());
    }
    return common::Result<CalendarCoreV3StoragePreparation>::success(
        {false, false, true});
  }

  bool has_v3 = false;
  for (const auto& data_store : calendar_core_v3_data_stores()) {
    auto root = store.read_json_file(data_store.file_name);
    if (!root.ok()) {
      return common::Result<CalendarCoreV3StoragePreparation>::failure(root.error());
    }
    if (!root.value().has_value()) continue;
    auto version = storage_version(*root.value(), data_store.file_name);
    if (!version.ok()) {
      return common::Result<CalendarCoreV3StoragePreparation>::failure(
          version.error());
    }
    has_v3 = has_v3 || version.value() == 3;
    if (version.value() != 1 && version.value() != 2 &&
        version.value() != 3) {
      return common::Result<CalendarCoreV3StoragePreparation>::failure(
          corrupted("unsupported Calendar Core storage version",
                    data_store.file_name));
    }
  }
  auto unified = store.read_json_file(kUnifiedJournalFile);
  if (!unified.ok()) {
    return common::Result<CalendarCoreV3StoragePreparation>::failure(unified.error());
  }
  if (unified.value().has_value()) has_v3 = true;
  if (has_v3) {
    return common::Result<CalendarCoreV3StoragePreparation>::failure(
        corrupted("mixed v2/v3 directory has no valid migration record"));
  }

  auto legacy_preflight = prepare_calendar_core_v2_storage(active_directory);
  if (!legacy_preflight.ok()) {
    return common::Result<CalendarCoreV3StoragePreparation>::failure(
        legacy_preflight.error());
  }
  initialized = store.initialize();
  if (!initialized.ok()) {
    return common::Result<CalendarCoreV3StoragePreparation>::failure(
        initialized.error());
  }
  auto recovered = recover_legacy_journal(store, kLegacyWorkflowJournal);
  if (!recovered.ok()) {
    return common::Result<CalendarCoreV3StoragePreparation>::failure(
        recovered.error());
  }
  recovered = recover_legacy_journal(store, kLegacyAnniversaryJournal);
  if (!recovered.ok()) {
    return common::Result<CalendarCoreV3StoragePreparation>::failure(
        recovered.error());
  }
  auto v2_roots = load_v2_roots(store);
  if (!v2_roots.ok()) {
    return common::Result<CalendarCoreV3StoragePreparation>::failure(
        v2_roots.error());
  }
  auto after = build_v3_after_stores(v2_roots.value());
  if (!after.ok()) {
    return common::Result<CalendarCoreV3StoragePreparation>::failure(
        after.error());
  }
  ParsedMigration migration;
  migration.state = "prepared";
  migration.phase = "prepared";
  auto hashes = source_hashes(store);
  if (!hashes.ok()) {
    return common::Result<CalendarCoreV3StoragePreparation>::failure(
        hashes.error());
  }
  migration.source_hashes = std::move(hashes.value());
  migration.after_stores = std::move(after.value());
  migration.prepared_at = common::utc_now_iso8601();
  auto prepared = store.write_json_file(
      kMigrationFile,
      migration_root("prepared", "prepared", migration.source_hashes,
                     migration.after_stores, {}, migration.prepared_at,
                     std::nullopt));
  if (!prepared.ok()) {
    return common::Result<CalendarCoreV3StoragePreparation>::failure(
        prepared.error());
  }
  auto hook = call_hook(failure_hook, "migration_after_prepare");
  if (!hook.ok()) {
    return common::Result<CalendarCoreV3StoragePreparation>::failure(
        hook.error());
  }
  auto applied = apply_migration(store, migration, failure_hook);
  if (!applied.ok()) {
    return common::Result<CalendarCoreV3StoragePreparation>::failure(
        applied.error());
  }
  auto valid = validate_complete_v3(store);
  if (!valid.ok()) {
    return common::Result<CalendarCoreV3StoragePreparation>::failure(
        valid.error());
  }
  return common::Result<CalendarCoreV3StoragePreparation>::success(
      {true, false, false});
}

}  // namespace excellent_calendar::storage::json
