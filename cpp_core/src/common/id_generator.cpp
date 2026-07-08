#include "excellent_calendar/common/id_generator.hpp"

#include <array>
#include <cstdint>
#include <iomanip>
#include <mutex>
#include <random>
#include <sstream>

namespace excellent_calendar::common {
namespace {

/**
 * 生成一个随机字节。
 *
 * random_device/mt19937_64/distribution 是静态对象，多次调用复用同一个随机引擎。
 * 因为随机引擎不是线程安全的，所以用 mutex 保护。
 */
std::uint8_t random_byte() {
  static std::mutex mutex;
  static std::random_device random_device;
  static std::mt19937_64 engine(random_device());
  static std::uniform_int_distribution<int> distribution(0, 255);

  std::lock_guard<std::mutex> lock(mutex);
  return static_cast<std::uint8_t>(distribution(engine));
}

}  // namespace

/** 生成 UUID v4，并设置 RFC 4122 要求的 version 和 variant 位。 */
std::string generate_uuid_v4() {
  std::array<std::uint8_t, 16> bytes{};
  for (auto& byte : bytes) {
    byte = random_byte();
  }

  // 第 6 字节高 4 位设为 0100，表示 UUID version 4。
  bytes[6] = static_cast<std::uint8_t>((bytes[6] & 0x0F) | 0x40);
  // 第 8 字节高 2 位设为 10，表示 RFC 4122 variant。
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
