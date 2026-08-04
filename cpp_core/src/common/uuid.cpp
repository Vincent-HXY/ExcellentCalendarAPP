#include "excellent_calendar/common/uuid.hpp"

#include <array>
#include <cstdint>
#include <iomanip>
#include <sstream>
#include <vector>

namespace excellent_calendar::common {
namespace {

std::uint32_t rotate_left(std::uint32_t value, unsigned bits) {
  return (value << bits) | (value >> (32U - bits));
}

std::array<std::uint8_t, 20> sha1(const std::vector<std::uint8_t>& input) {
  std::vector<std::uint8_t> bytes = input;
  const auto bit_length = static_cast<std::uint64_t>(bytes.size()) * 8U;
  bytes.push_back(0x80U);
  while ((bytes.size() % 64U) != 56U) {
    bytes.push_back(0U);
  }
  for (int shift = 56; shift >= 0; shift -= 8) {
    bytes.push_back(static_cast<std::uint8_t>((bit_length >> shift) & 0xffU));
  }

  std::uint32_t h0 = 0x67452301U;
  std::uint32_t h1 = 0xefcdab89U;
  std::uint32_t h2 = 0x98badcfeU;
  std::uint32_t h3 = 0x10325476U;
  std::uint32_t h4 = 0xc3d2e1f0U;

  for (std::size_t offset = 0; offset < bytes.size(); offset += 64U) {
    std::array<std::uint32_t, 80> words{};
    for (std::size_t index = 0; index < 16U; ++index) {
      const auto base = offset + index * 4U;
      words[index] = (static_cast<std::uint32_t>(bytes[base]) << 24U) |
                     (static_cast<std::uint32_t>(bytes[base + 1U]) << 16U) |
                     (static_cast<std::uint32_t>(bytes[base + 2U]) << 8U) |
                     static_cast<std::uint32_t>(bytes[base + 3U]);
    }
    for (std::size_t index = 16U; index < 80U; ++index) {
      words[index] = rotate_left(
          words[index - 3U] ^ words[index - 8U] ^ words[index - 14U] ^ words[index - 16U],
          1U);
    }

    auto a = h0;
    auto b = h1;
    auto c = h2;
    auto d = h3;
    auto e = h4;
    for (std::size_t index = 0; index < 80U; ++index) {
      std::uint32_t f = 0;
      std::uint32_t k = 0;
      if (index < 20U) {
        f = (b & c) | ((~b) & d);
        k = 0x5a827999U;
      } else if (index < 40U) {
        f = b ^ c ^ d;
        k = 0x6ed9eba1U;
      } else if (index < 60U) {
        f = (b & c) | (b & d) | (c & d);
        k = 0x8f1bbcdcU;
      } else {
        f = b ^ c ^ d;
        k = 0xca62c1d6U;
      }
      const auto temp = rotate_left(a, 5U) + f + e + k + words[index];
      e = d;
      d = c;
      c = rotate_left(b, 30U);
      b = a;
      a = temp;
    }
    h0 += a;
    h1 += b;
    h2 += c;
    h3 += d;
    h4 += e;
  }

  std::array<std::uint8_t, 20> digest{};
  const std::array<std::uint32_t, 5> state{h0, h1, h2, h3, h4};
  for (std::size_t index = 0; index < state.size(); ++index) {
    digest[index * 4U] = static_cast<std::uint8_t>((state[index] >> 24U) & 0xffU);
    digest[index * 4U + 1U] = static_cast<std::uint8_t>((state[index] >> 16U) & 0xffU);
    digest[index * 4U + 2U] = static_cast<std::uint8_t>((state[index] >> 8U) & 0xffU);
    digest[index * 4U + 3U] = static_cast<std::uint8_t>(state[index] & 0xffU);
  }
  return digest;
}

int hex_value(char value) {
  if (value >= '0' && value <= '9') return value - '0';
  if (value >= 'a' && value <= 'f') return value - 'a' + 10;
  if (value >= 'A' && value <= 'F') return value - 'A' + 10;
  return -1;
}

Result<std::array<std::uint8_t, 16>> parse_uuid(std::string_view value) {
  if (value.size() != 36U || value[8] != '-' || value[13] != '-' ||
      value[18] != '-' || value[23] != '-') {
    return Result<std::array<std::uint8_t, 16>>::failure(make_error(
        "CONTRACT_VALIDATION_FAILED", "UUID value is invalid", {{"field", "uuid"}}));
  }
  std::array<std::uint8_t, 16> bytes{};
  std::size_t output = 0;
  for (std::size_t index = 0; index < value.size();) {
    if (value[index] == '-') {
      ++index;
      continue;
    }
    if (index + 1U >= value.size() || output >= bytes.size()) {
      return Result<std::array<std::uint8_t, 16>>::failure(make_error(
          "CONTRACT_VALIDATION_FAILED", "UUID value is invalid", {{"field", "uuid"}}));
    }
    const int high = hex_value(value[index]);
    const int low = hex_value(value[index + 1U]);
    if (high < 0 || low < 0) {
      return Result<std::array<std::uint8_t, 16>>::failure(make_error(
          "CONTRACT_VALIDATION_FAILED", "UUID value is invalid", {{"field", "uuid"}}));
    }
    bytes[output++] = static_cast<std::uint8_t>((high << 4) | low);
    index += 2U;
  }
  if (output != bytes.size()) {
    return Result<std::array<std::uint8_t, 16>>::failure(make_error(
        "CONTRACT_VALIDATION_FAILED", "UUID value is invalid", {{"field", "uuid"}}));
  }
  return Result<std::array<std::uint8_t, 16>>::success(bytes);
}

std::string format_uuid(const std::array<std::uint8_t, 16>& bytes) {
  std::ostringstream output;
  output << std::hex << std::nouppercase << std::setfill('0');
  for (std::size_t index = 0; index < bytes.size(); ++index) {
    if (index == 4U || index == 6U || index == 8U || index == 10U) output << '-';
    output << std::setw(2) << static_cast<unsigned>(bytes[index]);
  }
  return output.str();
}

}  // namespace

bool is_uuid(std::string_view value) {
  return parse_uuid(value).ok();
}

Result<std::string> generate_uuid_v5(std::string_view namespace_uuid,
                                    std::string_view name) {
  auto parsed = parse_uuid(namespace_uuid);
  if (!parsed.ok()) return Result<std::string>::failure(parsed.error());
  std::vector<std::uint8_t> input(parsed.value().begin(), parsed.value().end());
  input.insert(input.end(), name.begin(), name.end());
  const auto digest = sha1(input);
  std::array<std::uint8_t, 16> uuid{};
  for (std::size_t index = 0; index < uuid.size(); ++index) uuid[index] = digest[index];
  uuid[6] = static_cast<std::uint8_t>((uuid[6] & 0x0fU) | 0x50U);
  uuid[8] = static_cast<std::uint8_t>((uuid[8] & 0x3fU) | 0x80U);
  return Result<std::string>::success(format_uuid(uuid));
}

}  // namespace excellent_calendar::common
