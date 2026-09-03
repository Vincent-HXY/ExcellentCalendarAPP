#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

#include "excellent_calendar/common/result.hpp"

namespace excellent_calendar::common {

using SearchHmacKey = std::array<std::uint8_t, 32>;

common::Result<SearchHmacKey> generate_search_hmac_key();

std::string search_binding_digest(std::string_view binding,
                                  const SearchHmacKey& key);

std::string encode_authenticated_search_token(
    std::string_view prefix, std::string_view domain,
    const std::vector<std::uint8_t>& payload, const SearchHmacKey& key);

common::Result<std::vector<std::uint8_t>> decode_authenticated_search_token(
    std::string_view token, std::string_view prefix, std::string_view domain,
    std::size_t maximum_token_length, const SearchHmacKey& key);

}  // namespace excellent_calendar::common
