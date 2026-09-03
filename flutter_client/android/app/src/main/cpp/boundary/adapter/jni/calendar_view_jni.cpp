#include <jni.h>

#include <cstdint>
#include <exception>
#include <string>
#include <string_view>
#include <vector>

#include "excellent_calendar/boundary/api/calendar_view_api.hpp"
#include "excellent_calendar/boundary/contract/native_result.hpp"
#include "excellent_calendar/boundary/contract/recurring_v2_json.hpp"
#include "excellent_calendar/common/id_generator.hpp"
#include "excellent_calendar/common/result.hpp"

namespace {

bool jstring_to_utf8(
    JNIEnv* env,
    jstring input,
    std::string& output,
    std::string& reason) {
  if (input == nullptr) {
    output.clear();
    return true;
  }
  const auto length = env->GetStringLength(input);
  const auto* chars = env->GetStringChars(input, nullptr);
  if (chars == nullptr) {
    if (env->ExceptionCheck()) env->ExceptionClear();
    reason = "JNI could not read the Calendar View request string";
    return false;
  }
  output.clear();
  output.reserve(static_cast<std::size_t>(length) * 3U);
  bool valid = true;
  for (jsize index = 0; index < length;) {
    std::uint32_t code_point = chars[index++];
    if (code_point >= 0xd800U && code_point <= 0xdbffU) {
      if (index >= length || chars[index] < 0xdc00U || chars[index] > 0xdfffU) {
        valid = false;
        break;
      }
      code_point = 0x10000U + ((code_point - 0xd800U) << 10U) +
                   (static_cast<std::uint32_t>(chars[index++]) - 0xdc00U);
    } else if (code_point >= 0xdc00U && code_point <= 0xdfffU) {
      valid = false;
      break;
    }
    if (code_point <= 0x7fU) {
      output.push_back(static_cast<char>(code_point));
    } else if (code_point <= 0x7ffU) {
      output.push_back(static_cast<char>(0xc0U | (code_point >> 6U)));
      output.push_back(static_cast<char>(0x80U | (code_point & 0x3fU)));
    } else if (code_point <= 0xffffU) {
      output.push_back(static_cast<char>(0xe0U | (code_point >> 12U)));
      output.push_back(static_cast<char>(0x80U | ((code_point >> 6U) & 0x3fU)));
      output.push_back(static_cast<char>(0x80U | (code_point & 0x3fU)));
    } else {
      output.push_back(static_cast<char>(0xf0U | (code_point >> 18U)));
      output.push_back(static_cast<char>(0x80U | ((code_point >> 12U) & 0x3fU)));
      output.push_back(static_cast<char>(0x80U | ((code_point >> 6U) & 0x3fU)));
      output.push_back(static_cast<char>(0x80U | (code_point & 0x3fU)));
    }
  }
  env->ReleaseStringChars(input, chars);
  if (!valid) {
    output.clear();
    reason = "Calendar View request contains malformed UTF-16";
  }
  return valid;
}

jstring utf8_to_jstring(JNIEnv* env, std::string_view input) {
  std::vector<jchar> output;
  output.reserve(input.size());
  for (std::size_t index = 0; index < input.size();) {
    const auto first = static_cast<unsigned char>(input[index++]);
    std::uint32_t code_point = 0;
    std::size_t continuation_count = 0;
    std::uint32_t minimum = 0;
    if (first <= 0x7fU) {
      code_point = first;
    } else if (first >= 0xc2U && first <= 0xdfU) {
      code_point = first & 0x1fU;
      continuation_count = 1U;
      minimum = 0x80U;
    } else if (first >= 0xe0U && first <= 0xefU) {
      code_point = first & 0x0fU;
      continuation_count = 2U;
      minimum = 0x800U;
    } else if (first >= 0xf0U && first <= 0xf4U) {
      code_point = first & 0x07U;
      continuation_count = 3U;
      minimum = 0x10000U;
    } else {
      return nullptr;
    }
    if (index + continuation_count > input.size()) return nullptr;
    for (std::size_t offset = 0; offset < continuation_count; ++offset) {
      const auto next = static_cast<unsigned char>(input[index++]);
      if ((next & 0xc0U) != 0x80U) return nullptr;
      code_point = (code_point << 6U) | (next & 0x3fU);
    }
    if ((continuation_count != 0U && code_point < minimum) ||
        code_point > 0x10ffffU ||
        (code_point >= 0xd800U && code_point <= 0xdfffU)) {
      return nullptr;
    }
    if (code_point <= 0xffffU) {
      output.push_back(static_cast<jchar>(code_point));
    } else {
      code_point -= 0x10000U;
      output.push_back(static_cast<jchar>(0xd800U + (code_point >> 10U)));
      output.push_back(static_cast<jchar>(0xdc00U + (code_point & 0x3ffU)));
    }
  }
  return env->NewString(
      output.empty() ? nullptr : output.data(),
      static_cast<jsize>(output.size()));
}

jstring emergency_failure_result(JNIEnv* env) noexcept {
  constexpr const char* fallback =
      R"({"contract_version":2,"data":null,"error":{"code":"NATIVE_INTERNAL_ERROR","details":{"reason":"Calendar View JNI failure serialization failed"},"message":"Native internal error","retryable":false},"ok":false,"request_id":"00000000-0000-4000-8000-000000000000"})";
  if (env->ExceptionCheck()) env->ExceptionClear();
  auto result = env->NewStringUTF(fallback);
  if (result == nullptr && env->ExceptionCheck()) env->ExceptionClear();
  return result;
}

jstring failure_result(
    JNIEnv* env,
    const char* code,
    const char* message,
    const char* reason) noexcept {
  try {
    const auto json = excellent_calendar::boundary::contract::native_failure_json_v2(
        excellent_calendar::common::make_error(
            code,
            message,
            {{"reason", reason == nullptr ? "unknown error" : reason}}),
        excellent_calendar::common::generate_uuid_v4());
    auto result = utf8_to_jstring(env, json);
    if (result != nullptr) return result;
  } catch (...) {
  }
  return emergency_failure_result(env);
}

jstring call_calendar_boundary(
    JNIEnv* env,
    jstring input,
    std::string (*function)(std::string_view)) noexcept {
  try {
    std::string request;
    std::string reason;
    if (!jstring_to_utf8(env, input, request, reason)) {
      return failure_result(
          env,
          "CONTRACT_VALIDATION_FAILED",
          "Request does not match contract schema",
          reason.c_str());
    }
    const auto response = function(request);
    auto result = utf8_to_jstring(env, response);
    if (result != nullptr) return result;
    if (env->ExceptionCheck()) env->ExceptionClear();
    return failure_result(
        env,
        "NATIVE_INTERNAL_ERROR",
        "Native internal error",
        "Calendar View response is not valid UTF-8");
  } catch (const std::exception& error) {
    return failure_result(
        env, "NATIVE_INTERNAL_ERROR", "Native internal error", error.what());
  } catch (...) {
    return failure_result(
        env, "NATIVE_INTERNAL_ERROR", "Native internal error", "unknown exception");
  }
}

}  // namespace

extern "C" JNIEXPORT jstring JNICALL
Java_com_excellentcalendar_excellent_1calendar_bridge_native_JniNativeCalendarCoreBridge_nativeCalendarRangeSummaryV2(
    JNIEnv* env,
    jobject /* this */,
    jstring request_json) {
  return call_calendar_boundary(
      env,
      request_json,
      excellent_calendar::boundary::api::calendar_range_summary_v2);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_excellentcalendar_excellent_1calendar_bridge_native_JniNativeCalendarCoreBridge_nativeCalendarListDayItemsV2(
    JNIEnv* env,
    jobject /* this */,
    jstring request_json) {
  return call_calendar_boundary(
      env,
      request_json,
      excellent_calendar::boundary::api::calendar_list_day_items_v2);
}
