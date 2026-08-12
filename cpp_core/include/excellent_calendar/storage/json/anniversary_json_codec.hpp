#pragma once

#include <string_view>

#include <picojson/picojson.h>

#include "excellent_calendar/common/result.hpp"
#include "excellent_calendar/repository/anniversary_transaction.hpp"

namespace excellent_calendar::storage::json {

common::Result<common::Unit> validate_anniversary_state(
    const repository::AnniversaryState& state);

common::Result<picojson::value> encode_anniversary_store(
    std::string_view file_name,
    const repository::AnniversaryState& state);

common::Result<common::Unit> decode_anniversary_store(
    std::string_view file_name,
    const picojson::value& root,
    repository::AnniversaryState& state);

picojson::value empty_anniversary_store(std::string_view file_name);

}  // namespace excellent_calendar::storage::json
