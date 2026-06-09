#include "excellent_calendar/common/id_generator.hpp"

#include <array>
#include <cstdint>
#include <iomanip>
#include <mutex>
#include <random>
#include <sstream>

namespace excellent_calendar::common {
namespace {

std::uint8_t random_byte() {
  static std::mutex mutex;
  static std::random_device random_device;
  static std::mt19937_64 engine(random_device());
  static std::uniform_int_distribution<int> distribution(0, 255);

  std::lock_guard<std::mutex> lock(mutex);
  return static_cast<std::uint8_t>(distribution(engine));
}

}  // namespace

std::string generate_uuid_v4() {
  std::array<std::uint8_t, 16> bytes{};
  for (auto& byte : bytes) {
    byte = random_byte();
  }

  bytes[6] = static_cast<std::uint8_t>((bytes[6] & 0x0F) | 0x40);
  bytes[8] = static_cast<std::uint8_t>((bytes[8] & 0x3F) | 0x80);

  std::ostringstream output;
  output << std::hex << std::setfill('0');
  for (std::size_t index = 0; index < bytes.size(); ++index) {
    output << std::setw(2) << static_cast<int>(bytes[index]);
    if (index == 3 || index == 5 || index == 7 || index == 9) {
      output << '-';
    }
  }
  return output.str();
}

}  // namespace excellent_calendar::common
