#include "excellent_calendar/common/search_token_crypto.hpp"

#include <algorithm>
#include <array>
#include <cstring>
#include <fstream>

#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <bcrypt.h>
#endif

namespace excellent_calendar::common {
namespace {

constexpr std::array<std::uint32_t, 64> kSha256Constants{{
    0x428a2f98U, 0x71374491U, 0xb5c0fbcfU, 0xe9b5dba5U, 0x3956c25bU,
    0x59f111f1U, 0x923f82a4U, 0xab1c5ed5U, 0xd807aa98U, 0x12835b01U,
    0x243185beU, 0x550c7dc3U, 0x72be5d74U, 0x80deb1feU, 0x9bdc06a7U,
    0xc19bf174U, 0xe49b69c1U, 0xefbe4786U, 0x0fc19dc6U, 0x240ca1ccU,
    0x2de92c6fU, 0x4a7484aaU, 0x5cb0a9dcU, 0x76f988daU, 0x983e5152U,
    0xa831c66dU, 0xb00327c8U, 0xbf597fc7U, 0xc6e00bf3U, 0xd5a79147U,
    0x06ca6351U, 0x14292967U, 0x27b70a85U, 0x2e1b2138U, 0x4d2c6dfcU,
    0x53380d13U, 0x650a7354U, 0x766a0abbU, 0x81c2c92eU, 0x92722c85U,
    0xa2bfe8a1U, 0xa81a664bU, 0xc24b8b70U, 0xc76c51a3U, 0xd192e819U,
    0xd6990624U, 0xf40e3585U, 0x106aa070U, 0x19a4c116U, 0x1e376c08U,
    0x2748774cU, 0x34b0bcb5U, 0x391c0cb3U, 0x4ed8aa4aU, 0x5b9cca4fU,
    0x682e6ff3U, 0x748f82eeU, 0x78a5636fU, 0x84c87814U, 0x8cc70208U,
    0x90befffaU, 0xa4506cebU, 0xbef9a3f7U, 0xc67178f2U,
}};

std::uint32_t rotate_right(std::uint32_t value, unsigned amount) {
  return (value >> amount) | (value << (32U - amount));
}

class Sha256 {
 public:
  void update(const std::uint8_t* data, std::size_t size) {
    total_size_ += size;
    while (size > 0U) {
      const auto copied = std::min(size, block_.size() - block_size_);
      std::memcpy(block_.data() + block_size_, data, copied);
      block_size_ += copied;
      data += copied;
      size -= copied;
      if (block_size_ == block_.size()) {
        transform(block_.data());
        block_size_ = 0U;
      }
    }
  }

  std::array<std::uint8_t, 32> finish() {
    const auto bit_size = static_cast<std::uint64_t>(total_size_) * 8U;
    block_[block_size_++] = 0x80U;
    if (block_size_ > 56U) {
      std::fill(block_.begin() + static_cast<std::ptrdiff_t>(block_size_),
                block_.end(), 0U);
      transform(block_.data());
      block_size_ = 0U;
    }
    std::fill(block_.begin() + static_cast<std::ptrdiff_t>(block_size_),
              block_.begin() + 56, 0U);
    for (int index = 0; index < 8; ++index) {
      block_[63 - index] =
          static_cast<std::uint8_t>(bit_size >> (index * 8));
    }
    transform(block_.data());
    std::array<std::uint8_t, 32> output{};
    for (std::size_t index = 0; index < state_.size(); ++index) {
      output[index * 4U] = static_cast<std::uint8_t>(state_[index] >> 24U);
      output[index * 4U + 1U] =
          static_cast<std::uint8_t>(state_[index] >> 16U);
      output[index * 4U + 2U] =
          static_cast<std::uint8_t>(state_[index] >> 8U);
      output[index * 4U + 3U] = static_cast<std::uint8_t>(state_[index]);
    }
    return output;
  }

 private:
  void transform(const std::uint8_t* data) {
    std::array<std::uint32_t, 64> words{};
    for (std::size_t index = 0; index < 16U; ++index) {
      words[index] = (static_cast<std::uint32_t>(data[index * 4U]) << 24U) |
                     (static_cast<std::uint32_t>(data[index * 4U + 1U]) << 16U) |
                     (static_cast<std::uint32_t>(data[index * 4U + 2U]) << 8U) |
                     static_cast<std::uint32_t>(data[index * 4U + 3U]);
    }
    for (std::size_t index = 16U; index < words.size(); ++index) {
      const auto s0 = rotate_right(words[index - 15U], 7U) ^
                      rotate_right(words[index - 15U], 18U) ^
                      (words[index - 15U] >> 3U);
      const auto s1 = rotate_right(words[index - 2U], 17U) ^
                      rotate_right(words[index - 2U], 19U) ^
                      (words[index - 2U] >> 10U);
      words[index] = words[index - 16U] + s0 + words[index - 7U] + s1;
    }
    auto a = state_[0];
    auto b = state_[1];
    auto c = state_[2];
    auto d = state_[3];
    auto e = state_[4];
    auto f = state_[5];
    auto g = state_[6];
    auto h = state_[7];
    for (std::size_t index = 0; index < words.size(); ++index) {
      const auto s1 = rotate_right(e, 6U) ^ rotate_right(e, 11U) ^
                      rotate_right(e, 25U);
      const auto choose = (e & f) ^ ((~e) & g);
      const auto temp1 = h + s1 + choose + kSha256Constants[index] +
                         words[index];
      const auto s0 = rotate_right(a, 2U) ^ rotate_right(a, 13U) ^
                      rotate_right(a, 22U);
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
    state_[0] += a;
    state_[1] += b;
    state_[2] += c;
    state_[3] += d;
    state_[4] += e;
    state_[5] += f;
    state_[6] += g;
    state_[7] += h;
  }

  std::array<std::uint32_t, 8> state_{{
      0x6a09e667U, 0xbb67ae85U, 0x3c6ef372U, 0xa54ff53aU,
      0x510e527fU, 0x9b05688cU, 0x1f83d9abU, 0x5be0cd19U,
  }};
  std::array<std::uint8_t, 64> block_{};
  std::size_t block_size_ = 0U;
  std::size_t total_size_ = 0U;
};

std::array<std::uint8_t, 32> hmac_sha256(
    const SearchHmacKey& key, std::string_view domain,
    const std::vector<std::uint8_t>& payload) {
  std::array<std::uint8_t, 64> inner{};
  std::array<std::uint8_t, 64> outer{};
  for (std::size_t index = 0; index < key.size(); ++index) {
    inner[index] = static_cast<std::uint8_t>(key[index] ^ 0x36U);
    outer[index] = static_cast<std::uint8_t>(key[index] ^ 0x5cU);
  }
  std::fill(inner.begin() + static_cast<std::ptrdiff_t>(key.size()),
            inner.end(), 0x36U);
  std::fill(outer.begin() + static_cast<std::ptrdiff_t>(key.size()),
            outer.end(), 0x5cU);
  Sha256 first;
  first.update(inner.data(), inner.size());
  first.update(reinterpret_cast<const std::uint8_t*>(domain.data()),
               domain.size());
  const std::uint8_t separator = 0;
  first.update(&separator, 1U);
  first.update(payload.data(), payload.size());
  const auto inner_hash = first.finish();
  Sha256 second;
  second.update(outer.data(), outer.size());
  second.update(inner_hash.data(), inner_hash.size());
  return second.finish();
}

std::string base64url_encode(const std::vector<std::uint8_t>& bytes) {
  constexpr char alphabet[] =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
  std::string output;
  output.reserve((bytes.size() * 4U + 2U) / 3U);
  std::uint32_t buffer = 0;
  int bits = 0;
  for (const auto byte : bytes) {
    buffer = (buffer << 8U) | byte;
    bits += 8;
    while (bits >= 6) {
      bits -= 6;
      output.push_back(alphabet[(buffer >> bits) & 0x3FU]);
    }
  }
  if (bits > 0) output.push_back(alphabet[(buffer << (6 - bits)) & 0x3FU]);
  return output;
}

int base64url_value(char value) {
  if (value >= 'A' && value <= 'Z') return value - 'A';
  if (value >= 'a' && value <= 'z') return value - 'a' + 26;
  if (value >= '0' && value <= '9') return value - '0' + 52;
  if (value == '-') return 62;
  if (value == '_') return 63;
  return -1;
}

common::Result<std::vector<std::uint8_t>> invalid_cursor() {
  return common::Result<std::vector<std::uint8_t>>::failure(
      common::make_error("SEARCH_CURSOR_INVALID", "Search cursor is invalid"));
}

common::Result<std::vector<std::uint8_t>> base64url_decode(
    std::string_view encoded) {
  if (encoded.empty() || encoded.find('=') != std::string_view::npos ||
      encoded.size() % 4U == 1U) {
    return invalid_cursor();
  }
  std::vector<std::uint8_t> output;
  output.reserve(encoded.size() * 3U / 4U);
  std::uint32_t buffer = 0;
  int bits = 0;
  for (const auto character : encoded) {
    const int value = base64url_value(character);
    if (value < 0) return invalid_cursor();
    buffer = (buffer << 6U) | static_cast<std::uint32_t>(value);
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      output.push_back(static_cast<std::uint8_t>((buffer >> bits) & 0xFFU));
    }
  }
  if (bits > 0 && (buffer & ((1U << bits) - 1U)) != 0U) {
    return invalid_cursor();
  }
  if (base64url_encode(output) != encoded) return invalid_cursor();
  return common::Result<std::vector<std::uint8_t>>::success(std::move(output));
}

}  // namespace

common::Result<SearchHmacKey> generate_search_hmac_key() {
  SearchHmacKey key{};
#if defined(_WIN32)
  const auto status = BCryptGenRandom(nullptr, key.data(),
                                      static_cast<ULONG>(key.size()),
                                      BCRYPT_USE_SYSTEM_PREFERRED_RNG);
  if (status < 0) {
    return common::Result<SearchHmacKey>::failure(common::make_error(
        "NATIVE_INTERNAL_ERROR", "Search runtime key generation failed"));
  }
#else
  std::ifstream input("/dev/urandom", std::ios::binary);
  input.read(reinterpret_cast<char*>(key.data()),
             static_cast<std::streamsize>(key.size()));
  if (!input || input.gcount() != static_cast<std::streamsize>(key.size())) {
    return common::Result<SearchHmacKey>::failure(common::make_error(
        "NATIVE_INTERNAL_ERROR", "Search runtime key generation failed"));
  }
#endif
  return common::Result<SearchHmacKey>::success(key);
}

std::string search_binding_digest(std::string_view binding,
                                  const SearchHmacKey& key) {
  const std::vector<std::uint8_t> bytes(binding.begin(), binding.end());
  const auto digest = hmac_sha256(
      key, "excellent-calendar/search-binding/v1", bytes);
  constexpr char hex[] = "0123456789abcdef";
  std::string output;
  output.reserve(64U);
  for (const auto byte : digest) {
    output.push_back(hex[byte >> 4U]);
    output.push_back(hex[byte & 0x0FU]);
  }
  return output;
}

std::string encode_authenticated_search_token(
    std::string_view prefix, std::string_view domain,
    const std::vector<std::uint8_t>& payload, const SearchHmacKey& key) {
  auto bytes = payload;
  const auto tag = hmac_sha256(key, domain, payload);
  bytes.insert(bytes.end(), tag.begin(), tag.end());
  return std::string(prefix) + "." + base64url_encode(bytes);
}

common::Result<std::vector<std::uint8_t>> decode_authenticated_search_token(
    std::string_view token, std::string_view prefix, std::string_view domain,
    std::size_t maximum_token_length, const SearchHmacKey& key) {
  const auto expected_prefix = std::string(prefix) + ".";
  if (token.size() > maximum_token_length ||
      token.rfind(expected_prefix, 0U) != 0U) {
    return invalid_cursor();
  }
  auto decoded = base64url_decode(token.substr(expected_prefix.size()));
  if (!decoded.ok() || decoded.value().size() <= 32U) return invalid_cursor();
  std::vector<std::uint8_t> payload(decoded.value().begin(),
                                    decoded.value().end() - 32);
  const auto expected = hmac_sha256(key, domain, payload);
  std::uint8_t difference = 0;
  for (std::size_t index = 0; index < expected.size(); ++index) {
    difference |= static_cast<std::uint8_t>(
        expected[index] ^ decoded.value()[payload.size() + index]);
  }
  if (difference != 0U) return invalid_cursor();
  return common::Result<std::vector<std::uint8_t>>::success(std::move(payload));
}

}  // namespace excellent_calendar::common
