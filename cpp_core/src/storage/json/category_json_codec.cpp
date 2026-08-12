#include "excellent_calendar/storage/json/category_json_codec.hpp"

#include <algorithm>
#include <cmath>
#include <exception>
#include <set>
#include <stdexcept>
#include <string>
#include <utility>

#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/domain/category.hpp"
#include "excellent_calendar/storage/json/atomic_json_file_store.hpp"

namespace excellent_calendar::storage::json {
namespace {

class DecodeFailure final : public std::runtime_error {
public:
  using std::runtime_error::runtime_error;
};

common::Error corrupted(std::string reason,
                        std::string field = "categories.json") {
  return storage_data_corrupted(std::move(reason), std::move(field));
}

const picojson::value &required(const picojson::object &object,
                                const std::string &key,
                                const std::string &context) {
  const auto found = object.find(key);
  if (found == object.end())
    throw DecodeFailure(context + "." + key + " is missing");
  return found->second;
}

void exact_fields(const picojson::object &object,
                  const std::set<std::string> &expected,
                  const std::string &context) {
  if (object.size() != expected.size()) {
    throw DecodeFailure(context + " contains unknown or missing fields");
  }
  for (const auto &name : expected) {
    if (object.find(name) == object.end()) {
      throw DecodeFailure(context + "." + name + " is missing");
    }
  }
}

std::string string_field(const picojson::object &object, const std::string &key,
                         const std::string &context) {
  const auto &value = required(object, key, context);
  if (!value.is<std::string>())
    throw DecodeFailure(context + "." + key + " must be string");
  return value.get<std::string>();
}

std::optional<std::string> nullable_string_field(const picojson::object &object,
                                                 const std::string &key,
                                                 const std::string &context) {
  const auto &value = required(object, key, context);
  if (value.is<picojson::null>())
    return std::nullopt;
  if (!value.is<std::string>()) {
    throw DecodeFailure(context + "." + key + " must be string or null");
  }
  return value.get<std::string>();
}

std::int64_t non_negative_integer_field(const picojson::object &object,
                                        const std::string &key,
                                        const std::string &context) {
  const auto &value = required(object, key, context);
  if (!value.is<double>() || !std::isfinite(value.get<double>()) ||
      std::floor(value.get<double>()) != value.get<double>() ||
      value.get<double>() < 0.0 ||
      value.get<double>() >
          static_cast<double>(domain::kMaximumCategorySortOrder)) {
    throw DecodeFailure(context + "." + key +
                        " must be an integer from 0 through 9007199254740991");
  }
  return static_cast<std::int64_t>(value.get<double>());
}

bool valid_trimmed_text(std::string_view value, std::size_t maximum_length) {
  const auto count = domain::utf8_code_point_count(value);
  const auto trimmed = domain::trim_unicode_whitespace(value);
  return count.has_value() && *count >= 1U && *count <= maximum_length &&
         trimmed.has_value() && *trimmed == value;
}

bool valid_timestamp_order(const CategoryStorageRecord &record) {
  if (!domain::is_whole_second_utc(record.created_at) ||
      !domain::is_whole_second_utc(record.updated_at)) {
    return false;
  }
  const auto created =
      common::parse_iso8601_utc_epoch_seconds(record.created_at);
  const auto updated =
      common::parse_iso8601_utc_epoch_seconds(record.updated_at);
  if (!created.has_value() || !updated.has_value() || *created > *updated)
    return false;
  if (!record.deleted_at.has_value())
    return true;
  if (!domain::is_whole_second_utc(*record.deleted_at))
    return false;
  const auto deleted =
      common::parse_iso8601_utc_epoch_seconds(*record.deleted_at);
  return deleted.has_value() && *created <= *deleted;
}

void validate_record(const CategoryStorageRecord &record,
                     const std::string &context) {
  if (!domain::is_canonical_category_uuid_v4(record.id)) {
    throw DecodeFailure(context + ".id must be a canonical lowercase UUIDv4");
  }
  if (!valid_trimmed_text(record.name, 40U)) {
    throw DecodeFailure(context + ".name is invalid");
  }
  if (record.description.has_value() &&
      !valid_trimmed_text(*record.description, 200U)) {
    throw DecodeFailure(context + ".description is invalid");
  }
  if (!domain::is_category_color(record.color, true)) {
    throw DecodeFailure(context + ".color must be canonical uppercase #RRGGBB");
  }
  if (record.icon.has_value() && !valid_trimmed_text(*record.icon, 64U)) {
    throw DecodeFailure(context + ".icon is invalid");
  }
  if (record.sort_order < 0 ||
      record.sort_order > domain::kMaximumCategorySortOrder) {
    throw DecodeFailure(
        context +
        ".sort_order must be from 0 through 9007199254740991");
  }
  if (!valid_timestamp_order(record)) {
    throw DecodeFailure(context + " timestamps are invalid");
  }
}

picojson::value nullable(const std::optional<std::string> &value) {
  return value.has_value() ? picojson::value(*value) : picojson::value();
}

picojson::value record_json(const CategoryStorageRecord &record) {
  picojson::object object;
  object["id"] = picojson::value(record.id);
  object["name"] = picojson::value(record.name);
  object["description"] = nullable(record.description);
  object["color"] = picojson::value(record.color);
  object["icon"] = nullable(record.icon);
  object["sort_order"] =
      picojson::value(static_cast<double>(record.sort_order));
  object["created_at"] = picojson::value(record.created_at);
  object["updated_at"] = picojson::value(record.updated_at);
  object["deleted_at"] = nullable(record.deleted_at);
  return picojson::value(std::move(object));
}

CategoryStorageRecord decode_record(const picojson::value &value,
                                    const std::string &context) {
  if (!value.is<picojson::object>())
    throw DecodeFailure(context + " must be object");
  const auto &object = value.get<picojson::object>();
  exact_fields(object,
               {"id", "name", "description", "color", "icon", "sort_order",
                "created_at", "updated_at", "deleted_at"},
               context);
  CategoryStorageRecord record{
      string_field(object, "id", context),
      string_field(object, "name", context),
      nullable_string_field(object, "description", context),
      string_field(object, "color", context),
      nullable_string_field(object, "icon", context),
      non_negative_integer_field(object, "sort_order", context),
      string_field(object, "created_at", context),
      string_field(object, "updated_at", context),
      nullable_string_field(object, "deleted_at", context)};
  validate_record(record, context);
  return record;
}

void validate_records(const std::vector<CategoryStorageRecord> &records) {
  std::set<std::string> ids;
  std::string previous_id;
  for (std::size_t index = 0; index < records.size(); ++index) {
    const auto context = "categories[" + std::to_string(index) + "]";
    validate_record(records[index], context);
    if (!ids.insert(records[index].id).second) {
      throw DecodeFailure(context + ".id is duplicated");
    }
    if (index != 0U && previous_id >= records[index].id) {
      throw DecodeFailure("categories must be serialized by id ascending");
    }
    previous_id = records[index].id;
  }
}

} // namespace

common::Result<std::vector<CategoryStorageRecord>>
category_storage_records_from_state(const repository::CategoryState &state) {
  try {
    std::vector<CategoryStorageRecord> records;
    records.reserve(state.categories.size());
    for (const auto &category : state.categories) {
      auto valid = domain::validate_category(category);
      if (!valid.ok() || !category.color.has_value() ||
          !category.sort_order.has_value()) {
        throw DecodeFailure("Category domain state cannot be persisted");
      }
      records.push_back(CategoryStorageRecord{
          category.id, category.name, category.description, *category.color,
          category.icon, *category.sort_order, category.created_at,
          category.updated_at, category.deleted_at});
    }
    std::sort(
        records.begin(), records.end(),
        [](const auto &left, const auto &right) { return left.id < right.id; });
    validate_records(records);
    return common::Result<std::vector<CategoryStorageRecord>>::success(
        std::move(records));
  } catch (const std::exception &error) {
    return common::Result<std::vector<CategoryStorageRecord>>::failure(
        corrupted(error.what()));
  }
}

common::Result<repository::CategoryState> category_state_from_storage_records(
    const std::vector<CategoryStorageRecord> &records) {
  try {
    validate_records(records);
    repository::CategoryState state;
    state.categories.reserve(records.size());
    for (const auto &record : records) {
      state.categories.push_back(domain::Category{
          record.id, record.name, record.description, record.color, record.icon,
          record.sort_order, record.created_at, record.updated_at,
          record.deleted_at});
    }
    return common::Result<repository::CategoryState>::success(std::move(state));
  } catch (const std::exception &error) {
    return common::Result<repository::CategoryState>::failure(
        corrupted(error.what()));
  }
}

common::Result<picojson::value>
encode_category_store(const std::vector<CategoryStorageRecord> &records) {
  try {
    validate_records(records);
    picojson::array categories;
    categories.reserve(records.size());
    for (const auto &record : records)
      categories.push_back(record_json(record));
    picojson::object root;
    root["storage_version"] = picojson::value(2.0);
    root["categories"] = picojson::value(std::move(categories));
    return common::Result<picojson::value>::success(
        picojson::value(std::move(root)));
  } catch (const std::exception &error) {
    return common::Result<picojson::value>::failure(corrupted(error.what()));
  }
}

common::Result<std::vector<CategoryStorageRecord>>
decode_category_store(const picojson::value &root) {
  try {
    if (!root.is<picojson::object>())
      throw DecodeFailure("categories.json root must be object");
    const auto &object = root.get<picojson::object>();
    exact_fields(object, {"storage_version", "categories"}, "categories.json");
    const auto &version =
        required(object, "storage_version", "categories.json");
    const auto &categories = required(object, "categories", "categories.json");
    if (!version.is<double>() || version.get<double>() != 2.0) {
      throw DecodeFailure("categories.json.storage_version must equal 2");
    }
    if (!categories.is<picojson::array>()) {
      throw DecodeFailure("categories.json.categories must be array");
    }
    std::vector<CategoryStorageRecord> records;
    const auto &values = categories.get<picojson::array>();
    records.reserve(values.size());
    for (std::size_t index = 0; index < values.size(); ++index) {
      records.push_back(decode_record(
          values[index], "categories[" + std::to_string(index) + "]"));
    }
    validate_records(records);
    return common::Result<std::vector<CategoryStorageRecord>>::success(
        std::move(records));
  } catch (const std::exception &error) {
    return common::Result<std::vector<CategoryStorageRecord>>::failure(
        corrupted(error.what()));
  }
}

picojson::value empty_category_store() {
  picojson::object root;
  root["storage_version"] = picojson::value(2.0);
  root["categories"] = picojson::value(picojson::array{});
  return picojson::value(std::move(root));
}

} // namespace excellent_calendar::storage::json
