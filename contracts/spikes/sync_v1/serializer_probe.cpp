// CT0 audit only: this executable is never linked into an application.
// Including the existing translation unit lets the KAT exercise its private
// SHA-256 implementation without extracting or changing production crypto.
#include "common/search_token_crypto.cpp"
#include <picojson/picojson.h>

#include <iostream>
#include <string>

std::string hex_bytes(const std::string& value) {
  static constexpr char digits[] = "0123456789abcdef";
  std::string out;
  for (unsigned char byte : value) {
    out += digits[byte >> 4U];
    out += digits[byte & 15U];
  }
  return out;
}

int main(int argc, char** argv) {
  std::string line;
  const bool hash_mode = argc == 2 && std::string(argv[1]) == "--sha256";
  while (std::getline(std::cin, line)) {
    if (hash_mode) {
      excellent_calendar::common::Sha256 hash;
      // Chunking deliberately crosses SHA-256 block boundaries.
      for (std::size_t start = 0; start < line.size(); start += 17U) {
        hash.update(reinterpret_cast<const std::uint8_t*>(line.data() + start),
                    std::min<std::size_t>(17U, line.size() - start));
      }
      auto bytes = hash.finish();
      std::cout << hex_bytes(std::string(bytes.begin(), bytes.end())) << '\n';
      continue;
    }
    picojson::value value;
    const auto error = picojson::parse(value, line);
    if (!error.empty()) {
      std::cout << "ERROR\n";
    } else {
      std::cout << "OK\t" << hex_bytes(value.serialize()) << '\n';
    }
  }
}
