#include "excellent_calendar/storage/json/anniversary_json_codec.hpp"

#include <cmath>
#include <exception>
#include <map>
#include <limits>
#include <optional>
#include <set>
#include <stdexcept>
#include <string>
#include <utility>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/string_utils.hpp"
#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/domain/importance.hpp"
#include "excellent_calendar/domain/local_time_resolver.hpp"
#include "excellent_calendar/storage/json/atomic_json_file_store.hpp"

namespace excellent_calendar::storage::json {
namespace {

constexpr std::string_view kAnniversariesFile = "anniversaries.json";
constexpr std::string_view kRecurrencesFile = "anniversary_recurrences.json";

class DecodeFailure : public std::runtime_error {
 public:
  using std::runtime_error::runtime_error;
};

common::Error corrupted(std::string reason, std::string field = "anniversary_storage") {
  return storage_data_corrupted(std::move(reason), std::move(field));
}

const picojson::value& required(
    const picojson::object& object,
    const std::string& key,
    const std::string& context) {
  const auto found = object.find(key);
  if (found == object.end()) throw DecodeFailure(context + "." + key + " is missing");
  return found->second;
}

std::string string_field(
    const picojson::object& object,
    const std::string& key,
    const std::string& context) {
  const auto& value = required(object, key, context);
  if (!value.is<std::string>()) throw DecodeFailure(context + "." + key + " must be string");
  return value.get<std::string>();
}

std::optional<std::string> nullable_string_field(
    const picojson::object& object,
    const std::string& key,
    const std::string& context) {
  const auto& value = required(object, key, context);
  if (value.is<picojson::null>()) return std::nullopt;
  if (!value.is<std::string>()) {
    throw DecodeFailure(context + "." + key + " must be string or null");
  }
  return value.get<std::string>();
}

int int_field(
    const picojson::object& object,
    const std::string& key,
    const std::string& context) {
  const auto& value = required(object, key, context);
  if (!value.is<double>() || !std::isfinite(value.get<double>()) ||
      std::floor(value.get<double>()) != value.get<double>() ||
      value.get<double>() < static_cast<double>(std::numeric_limits<int>::min()) ||
      value.get<double>() > static_cast<double>(std::numeric_limits<int>::max())) {
    throw DecodeFailure(context + "." + key + " must be integer");
  }
  return static_cast<int>(value.get<double>());
}

void exact_fields(
    const picojson::object& object,
    const std::set<std::string>& fields,
    const std::string& context) {
  if (object.size() != fields.size()) {
    throw DecodeFailure(context + " fields are invalid");
  }
  for (const auto& field : fields) {
    if (object.find(field) == object.end()) {
      throw DecodeFailure(context + "." + field + " is missing");
    }
  }
}

bool valid_instant_order(
    const std::string& created_at,
    const std::string& updated_at,
    const std::optional<std::string>& deleted_at) {
  const auto created = common::parse_iso8601_utc_epoch_seconds(created_at);
  const auto updated = common::parse_iso8601_utc_epoch_seconds(updated_at);
  if (!created.has_value() || !updated.has_value() || *created > *updated) return false;
  if (!deleted_at.has_value()) return true;
  const auto deleted = common::parse_iso8601_utc_epoch_seconds(*deleted_at);
  return deleted.has_value() && *updated <= *deleted;
}

picojson::value nullable(const std::optional<std::string>& value) {
  return value.has_value() ? picojson::value(*value) : picojson::value();
}

picojson::value anniversary_json(const domain::Anniversary& value) {
  picojson::object item;
  item["id"] = picojson::value(value.id);
  item["title"] = picojson::value(value.title);
  item["date"] = picojson::value(domain::format_local_date(value.date));
  item["calendar_type"] = picojson::value(value.calendar_type);
  item["category_id"] = nullable(value.category_id);
  item["recurrence_id"] = nullable(value.recurrence_id);
  item["note"] = nullable(value.note);
  item["importance"] = nullable(value.importance);
  item["created_at"] = picojson::value(value.created_at);
  item["updated_at"] = picojson::value(value.updated_at);
  item["deleted_at"] = nullable(value.deleted_at);
  return picojson::value(std::move(item));
}

picojson::value recurrence_json(const domain::AnniversaryRecurrence& value) {
  picojson::object item;
  item["recurrence_id"] = picojson::value(value.id);
  item["frequency"] = picojson::value(value.frequency);
  item["interval"] = picojson::value(static_cast<double>(value.interval));
  item["created_at"] = picojson::value(value.created_at);
  item["deleted_at"] = nullable(value.deleted_at);
  return picojson::value(std::move(item));
}

domain::Anniversary decode_anniversary(
    const picojson::value& value,
    const std::string& context) {
  if (!value.is<picojson::object>()) throw DecodeFailure(context + " must be object");
  const auto& item = value.get<picojson::object>();
  exact_fields(
      item,
      {"id", "title", "date", "calendar_type", "category_id", "recurrence_id",
       "note", "importance", "created_at", "updated_at", "deleted_at"},
      context);
  auto date = domain::parse_local_date(string_field(item, "date", context));
  if (!date.ok()) throw DecodeFailure(context + ".date is invalid");
  return domain::Anniversary{
      string_field(item, "id", context),
      string_field(item, "title", context),
      date.value(),
      string_field(item, "calendar_type", context),
      nullable_string_field(item, "category_id", context),
      nullable_string_field(item, "recurrence_id", context),
      nullable_string_field(item, "note", context),
      nullable_string_field(item, "importance", context),
      string_field(item, "created_at", context),
      string_field(item, "updated_at", context),
      nullable_string_field(item, "deleted_at", context)};
}

domain::AnniversaryRecurrence decode_recurrence(
    const picojson::value& value,
    const std::string& context) {
  if (!value.is<picojson::object>()) throw DecodeFailure(context + " must be object");
  const auto& item = value.get<picojson::object>();
  exact_fields(
      item, {"recurrence_id", "frequency", "interval", "created_at", "deleted_at"},
      context);
  return domain::AnniversaryRecurrence{
      string_field(item, "recurrence_id", context),
      string_field(item, "frequency", context),
      int_field(item, "interval", context),
      string_field(item, "created_at", context),
      nullable_string_field(item, "deleted_at", context)};
}

}  // namespace

common::Result<common::Unit> validate_anniversary_state(
    const repository::AnniversaryState& state) {
  try {
    std::set<std::string> recurrence_ids;
    std::map<std::string, const domain::AnniversaryRecurrence*> recurrence_by_id;
    for (const auto& recurrence : state.recurrences) {
      if (!common::is_uuid(recurrence.id) ||
          recurrence.frequency != domain::kAnniversaryRecurrenceYearly ||
          recurrence.interval != 1 ||
          !common::is_iso8601_utc_datetime(recurrence.created_at) ||
          (recurrence.deleted_at.has_value() &&
           (!common::is_iso8601_utc_datetime(*recurrence.deleted_at) ||
            common::parse_iso8601_utc_epoch_seconds(recurrence.created_at) >
                common::parse_iso8601_utc_epoch_seconds(*recurrence.deleted_at))) ||
          !recurrence_ids.insert(recurrence.id).second) {
        throw DecodeFailure("AnniversaryRecurrence invariant is invalid");
      }
      recurrence_by_id.emplace(recurrence.id, &recurrence);
    }

    std::set<std::string> anniversary_ids;
    std::set<std::string> referenced_recurrences;
    std::set<std::string> active_recurrences;
    for (const auto& anniversary : state.anniversaries) {
      if (!common::is_uuid(anniversary.id) ||
          common::trim_ascii(anniversary.title).empty() ||
          !domain::is_valid_local_date(anniversary.date) ||
          anniversary.calendar_type != domain::kAnniversaryCalendarSolar ||
          (anniversary.category_id.has_value() &&
           !common::is_uuid(*anniversary.category_id)) ||
          (anniversary.recurrence_id.has_value() &&
           !common::is_uuid(*anniversary.recurrence_id)) ||
          (anniversary.importance.has_value() &&
           !domain::is_valid_importance(*anniversary.importance)) ||
          !valid_instant_order(
              anniversary.created_at, anniversary.updated_at, anniversary.deleted_at) ||
          !anniversary_ids.insert(anniversary.id).second) {
        throw DecodeFailure("Anniversary invariant is invalid");
      }
      if (!anniversary.recurrence_id.has_value()) continue;
      const auto recurrence = recurrence_by_id.find(*anniversary.recurrence_id);
      if (recurrence == recurrence_by_id.end() ||
          !referenced_recurrences.insert(*anniversary.recurrence_id).second) {
        throw DecodeFailure("Anniversary recurrence reference is invalid");
      }
      const bool anniversary_deleted = anniversary.deleted_at.has_value();
      const bool recurrence_deleted = recurrence->second->deleted_at.has_value();
      if (anniversary_deleted != recurrence_deleted) {
        throw DecodeFailure("Anniversary recurrence lifecycle is inconsistent");
      }
      if (!anniversary_deleted) active_recurrences.insert(*anniversary.recurrence_id);
    }
    for (const auto& recurrence : state.recurrences) {
      if (!recurrence.deleted_at.has_value() &&
          active_recurrences.count(recurrence.id) != 1U) {
        throw DecodeFailure("Active AnniversaryRecurrence must have one active owner");
      }
    }
    return common::Result<common::Unit>::success(common::Unit{});
  } catch (const std::exception& error) {
    return common::Result<common::Unit>::failure(corrupted(error.what()));
  }
}

common::Result<picojson::value> encode_anniversary_store(
    std::string_view file_name,
    const repository::AnniversaryState& state) {
  auto valid = validate_anniversary_state(state);
  if (!valid.ok()) return common::Result<picojson::value>::failure(valid.error());
  picojson::array values;
  std::string collection;
  if (file_name == kAnniversariesFile) {
    collection = "anniversaries";
    values.reserve(state.anniversaries.size());
    for (const auto& item : state.anniversaries) values.push_back(anniversary_json(item));
  } else if (file_name == kRecurrencesFile) {
    collection = "anniversary_recurrences";
    values.reserve(state.recurrences.size());
    for (const auto& item : state.recurrences) values.push_back(recurrence_json(item));
  } else {
    return common::Result<picojson::value>::failure(
        corrupted("Unknown Anniversary store", std::string(file_name)));
  }
  picojson::object root;
  root["storage_version"] = picojson::value(2.0);
  root[collection] = picojson::value(std::move(values));
  return common::Result<picojson::value>::success(picojson::value(std::move(root)));
}

common::Result<common::Unit> decode_anniversary_store(
    std::string_view file_name,
    const picojson::value& root,
    repository::AnniversaryState& state) {
  try {
    if (!root.is<picojson::object>()) throw DecodeFailure("Store root must be object");
    const auto& object = root.get<picojson::object>();
    const std::string collection = file_name == kAnniversariesFile
                                       ? "anniversaries"
                                       : file_name == kRecurrencesFile
                                             ? "anniversary_recurrences"
                                             : "";
    if (collection.empty()) throw DecodeFailure("Unknown Anniversary store");
    exact_fields(object, {"storage_version", collection}, std::string(file_name));
    const auto& version = required(object, "storage_version", std::string(file_name));
    const auto& values = required(object, collection, std::string(file_name));
    if (!version.is<double>() || version.get<double>() != 2.0 ||
        !values.is<picojson::array>()) {
      throw DecodeFailure("Anniversary store envelope is invalid");
    }
    if (file_name == kAnniversariesFile) {
      state.anniversaries.clear();
      const auto& array = values.get<picojson::array>();
      state.anniversaries.reserve(array.size());
      for (std::size_t index = 0; index < array.size(); ++index) {
        state.anniversaries.push_back(
            decode_anniversary(array[index], "anniversaries[" + std::to_string(index) + "]"));
      }
    } else {
      state.recurrences.clear();
      const auto& array = values.get<picojson::array>();
      state.recurrences.reserve(array.size());
      for (std::size_t index = 0; index < array.size(); ++index) {
        state.recurrences.push_back(
            decode_recurrence(
                array[index], "anniversary_recurrences[" + std::to_string(index) + "]"));
      }
    }
    return common::Result<common::Unit>::success(common::Unit{});
  } catch (const std::exception& error) {
    return common::Result<common::Unit>::failure(
        corrupted(error.what(), std::string(file_name)));
  }
}

picojson::value empty_anniversary_store(std::string_view file_name) {
  picojson::object root;
  root["storage_version"] = picojson::value(2.0);
  if (file_name == kAnniversariesFile) {
    root["anniversaries"] = picojson::value(picojson::array{});
  } else if (file_name == kRecurrencesFile) {
    root["anniversary_recurrences"] = picojson::value(picojson::array{});
  }
  return picojson::value(std::move(root));
}

}  // namespace excellent_calendar::storage::json
