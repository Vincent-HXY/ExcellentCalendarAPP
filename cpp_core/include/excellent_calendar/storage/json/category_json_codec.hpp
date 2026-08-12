#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

#include <picojson/picojson.h>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/repository/category_repository.hpp"

namespace excellent_calendar::storage::json {

struct CategoryStorageRecord {
  std::string id;
  std::string name;
  std::optional<std::string> description;
  std::string color;
  std::optional<std::string> icon;
  std::int64_t sort_order = 0;
  std::string created_at;
  std::string updated_at;
  std::optional<std::string> deleted_at;
};

common::Result<std::vector<CategoryStorageRecord>>
category_storage_records_from_state(const repository::CategoryState &state);

common::Result<repository::CategoryState> category_state_from_storage_records(
    const std::vector<CategoryStorageRecord> &records);

common::Result<picojson::value>
encode_category_store(const std::vector<CategoryStorageRecord> &records);

common::Result<std::vector<CategoryStorageRecord>>
decode_category_store(const picojson::value &root);

picojson::value empty_category_store();

} // namespace excellent_calendar::storage::json
