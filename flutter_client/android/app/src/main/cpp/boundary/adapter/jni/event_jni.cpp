#include <jni.h>

#include <exception>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

#include "excellent_calendar/boundary/api/event_api.hpp"
#include "excellent_calendar/boundary/api/anniversary_api.hpp"
#include "excellent_calendar/boundary/api/category_api.hpp"
#include "excellent_calendar/boundary/api/notification_api.hpp"
#include "excellent_calendar/boundary/api/reminder_api.hpp"
#include "excellent_calendar/boundary/api/recurring_v2_api.hpp"
#include "excellent_calendar/boundary/contract/native_result.hpp"
#include "excellent_calendar/boundary/contract/recurring_v2_json.hpp"
#include "excellent_calendar/common/id_generator.hpp"
#include "excellent_calendar/common/result.hpp"

namespace {

/**
 * 把 Java/Kotlin 的 jstring 转成 C++ std::string。
 *
 * GetStringUTFChars 可能因为内存不足返回 nullptr，所以这里做空指针保护。
 * 取到 chars 后必须调用 ReleaseStringUTFChars，否则 JVM 资源可能泄漏。
 */
std::string from_jstring(JNIEnv* env, jstring value) {
  if (value == nullptr) {
    return {};
  }
  const char* chars = env->GetStringUTFChars(value, nullptr);
  if (chars == nullptr) {
    return {};
  }
  std::string result(chars);
  env->ReleaseStringUTFChars(value, chars);
  return result;
}

/** 把 C++ std::string 转回 Java/Kotlin jstring。 */
jstring to_jstring(JNIEnv* env, const std::string& value) {
  return env->NewStringUTF(value.c_str());
}

/** JNI 层兜底错误：即使 C++ 抛异常，也返回符合 NativeResult 合约的 JSON。 */
jstring internal_error_result(JNIEnv* env, const char* reason) {
  const auto request_id = excellent_calendar::common::generate_uuid_v4();
  return to_jstring(
      env,
      excellent_calendar::boundary::contract::native_failure_json(
          excellent_calendar::common::make_error(
              "NATIVE_INTERNAL_ERROR",
              "Native internal error",
              {{"reason", reason == nullptr ? "unknown exception" : reason}}),
          request_id));
}

/**
 * JNI 方法的通用调用模板。
 *
 * function 是 C++ boundary API 函数指针，签名为 `std::string(std::string_view)`。
 * 这里统一做字符串转换和异常捕获，下面每个 JNI 导出函数就非常薄。
 */
jstring call_boundary(JNIEnv* env, jstring input, std::string (*function)(std::string_view)) {
  try {
    return to_jstring(env, function(from_jstring(env, input)));
  } catch (const std::exception& error) {
    return internal_error_result(env, error.what());
  } catch (...) {
    return internal_error_result(env, "unknown exception");
  }
}

}  // namespace

// extern "C" 禁止 C++ 名字改编；JNIEXPORT/JNICALL 是 JNI 要求的导出宏和调用约定。
extern "C" JNIEXPORT jstring JNICALL
Java_com_excellentcalendar_excellent_1calendar_bridge_native_JniNativeCalendarCoreBridge_nativeInitializeStorage(
    JNIEnv* env,
    jobject /* this */,
    jstring storage_directory) {
  return call_boundary(env, storage_directory, excellent_calendar::boundary::api::initialize_storage);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_excellentcalendar_excellent_1calendar_bridge_native_JniNativeCalendarCoreBridge_nativeCreateEvent(
    JNIEnv* env,
    jobject /* this */,
    jstring request_json) {
  return call_boundary(env, request_json, excellent_calendar::boundary::api::create_event);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_excellentcalendar_excellent_1calendar_bridge_native_JniNativeCalendarCoreBridge_nativeUpdateEvent(
    JNIEnv* env,
    jobject /* this */,
    jstring request_json) {
  return call_boundary(env, request_json, excellent_calendar::boundary::api::update_event);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_excellentcalendar_excellent_1calendar_bridge_native_JniNativeCalendarCoreBridge_nativeDeleteEvent(
    JNIEnv* env,
    jobject /* this */,
    jstring request_json) {
  return call_boundary(env, request_json, excellent_calendar::boundary::api::delete_event);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_excellentcalendar_excellent_1calendar_bridge_native_JniNativeCalendarCoreBridge_nativeSearchEvents(
    JNIEnv* env,
    jobject /* this */,
    jstring request_json) {
  return call_boundary(env, request_json, excellent_calendar::boundary::api::search_events);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_excellentcalendar_excellent_1calendar_bridge_native_JniNativeCalendarCoreBridge_nativeCompleteEvent(
    JNIEnv* env,
    jobject /* this */,
    jstring request_json) {
  return call_boundary(env, request_json, excellent_calendar::boundary::api::complete_event);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_excellentcalendar_excellent_1calendar_bridge_native_JniNativeCalendarCoreBridge_nativeReopenEvent(
    JNIEnv* env,
    jobject /* this */,
    jstring request_json) {
  return call_boundary(env, request_json, excellent_calendar::boundary::api::reopen_event);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_excellentcalendar_excellent_1calendar_bridge_native_JniNativeCalendarCoreBridge_nativeCreateReminder(
    JNIEnv* env,
    jobject /* this */,
    jstring request_json) {
  return call_boundary(env, request_json, excellent_calendar::boundary::api::create_reminder);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_excellentcalendar_excellent_1calendar_bridge_native_JniNativeCalendarCoreBridge_nativeUpdateReminder(
    JNIEnv* env,
    jobject /* this */,
    jstring request_json) {
  return call_boundary(env, request_json, excellent_calendar::boundary::api::update_reminder);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_excellentcalendar_excellent_1calendar_bridge_native_JniNativeCalendarCoreBridge_nativeCancelReminder(
    JNIEnv* env,
    jobject /* this */,
    jstring request_json) {
  return call_boundary(env, request_json, excellent_calendar::boundary::api::cancel_reminder);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_excellentcalendar_excellent_1calendar_bridge_native_JniNativeCalendarCoreBridge_nativeListReminders(
    JNIEnv* env,
    jobject /* this */,
    jstring request_json) {
  return call_boundary(env, request_json, excellent_calendar::boundary::api::list_reminders);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_excellentcalendar_excellent_1calendar_bridge_native_JniNativeCalendarCoreBridge_nativeGetReminder(
    JNIEnv* env,
    jobject /* this */,
    jstring request_json) {
  return call_boundary(env, request_json, excellent_calendar::boundary::api::get_reminder);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_excellentcalendar_excellent_1calendar_bridge_native_JniNativeCalendarCoreBridge_nativeListSchedulableReminders(
    JNIEnv* env,
    jobject /* this */,
    jstring request_json) {
  return call_boundary(
      env, request_json, excellent_calendar::boundary::api::list_schedulable_reminders);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_excellentcalendar_excellent_1calendar_bridge_native_JniNativeCalendarCoreBridge_nativeMarkReminderScheduled(
    JNIEnv* env,
    jobject /* this */,
    jstring request_json) {
  return call_boundary(env, request_json, excellent_calendar::boundary::api::mark_reminder_scheduled);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_excellentcalendar_excellent_1calendar_bridge_native_JniNativeCalendarCoreBridge_nativeMarkReminderSent(
    JNIEnv* env,
    jobject /* this */,
    jstring request_json) {
  return call_boundary(env, request_json, excellent_calendar::boundary::api::mark_reminder_sent);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_excellentcalendar_excellent_1calendar_bridge_native_JniNativeCalendarCoreBridge_nativeMarkReminderFailed(
    JNIEnv* env,
    jobject /* this */,
    jstring request_json) {
  return call_boundary(env, request_json, excellent_calendar::boundary::api::mark_reminder_failed);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_excellentcalendar_excellent_1calendar_bridge_native_JniNativeCalendarCoreBridge_nativeEnableReminder(
    JNIEnv* env,
    jobject /* this */,
    jstring request_json) {
  return call_boundary(env, request_json, excellent_calendar::boundary::api::enable_reminder);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_excellentcalendar_excellent_1calendar_bridge_native_JniNativeCalendarCoreBridge_nativeDisableReminder(
    JNIEnv* env,
    jobject /* this */,
    jstring request_json) {
  return call_boundary(env, request_json, excellent_calendar::boundary::api::disable_reminder);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_excellentcalendar_excellent_1calendar_bridge_native_JniNativeCalendarCoreBridge_nativeCreateNotification(
    JNIEnv* env,
    jobject /* this */,
    jstring request_json) {
  return call_boundary(env, request_json, excellent_calendar::boundary::api::create_notification);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_excellentcalendar_excellent_1calendar_bridge_native_JniNativeCalendarCoreBridge_nativeConsumeReminderAfterDelivery(
    JNIEnv* env,
    jobject /* this */,
    jstring request_json) {
  return call_boundary(
      env, request_json, excellent_calendar::boundary::api::consume_reminder_after_delivery);
}

jstring internal_error_result_v2(JNIEnv* env, const char* reason) {
  const auto request_id = excellent_calendar::common::generate_uuid_v4();
  return to_jstring(
      env,
      excellent_calendar::boundary::contract::native_failure_json_v2(
          excellent_calendar::common::make_error(
              "NATIVE_INTERNAL_ERROR",
              "Native internal error",
              {{"reason", reason == nullptr ? "unknown exception" : reason}}),
          request_id));
}

jstring call_boundary_v2(JNIEnv* env, jstring input, std::string (*function)(std::string_view)) {
  try {
    return to_jstring(env, function(from_jstring(env, input)));
  } catch (const std::exception& error) {
    return internal_error_result_v2(env, error.what());
  } catch (...) {
    return internal_error_result_v2(env, "unknown exception");
  }
}

bool category_jstring_to_utf8(
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
    reason = "JNI could not read the Category request string";
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
    reason = "Category request contains malformed UTF-16";
  }
  return valid;
}

jstring category_utf8_to_jstring(JNIEnv* env, std::string_view input) {
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
  return env->NewString(output.empty() ? nullptr : output.data(),
                        static_cast<jsize>(output.size()));
}

jstring category_emergency_failure_result_v2(JNIEnv* env) noexcept {
  constexpr const char* fallback =
      R"({"contract_version":2,"data":null,"error":{"code":"NATIVE_INTERNAL_ERROR","details":{"reason":"Category JNI failure serialization failed"},"message":"Native internal error","retryable":false},"ok":false,"request_id":"00000000-0000-4000-8000-000000000000"})";
  if (env->ExceptionCheck()) env->ExceptionClear();
  auto result = env->NewStringUTF(fallback);
  if (result == nullptr && env->ExceptionCheck()) env->ExceptionClear();
  return result;
}

jstring category_failure_result_v2(
    JNIEnv* env,
    const char* code,
    const char* message,
    const char* reason) noexcept {
  try {
    const auto json = excellent_calendar::boundary::contract::native_failure_json_v2(
        excellent_calendar::common::make_error(
            code, message, {{"reason", reason == nullptr ? "unknown error" : reason}}),
        excellent_calendar::common::generate_uuid_v4());
    auto result = category_utf8_to_jstring(env, json);
    if (result != nullptr) return result;
  } catch (...) {
  }
  return category_emergency_failure_result_v2(env);
}

jstring call_category_boundary_v2(
    JNIEnv* env,
    jstring input,
    std::string (*function)(std::string_view)) noexcept {
  try {
    std::string request;
    std::string reason;
    if (!category_jstring_to_utf8(env, input, request, reason)) {
      return category_failure_result_v2(
          env, "CONTRACT_VALIDATION_FAILED", "Request does not match contract schema",
          reason.c_str());
    }
    const auto response = function(request);
    auto result = category_utf8_to_jstring(env, response);
    if (result != nullptr) return result;
    if (env->ExceptionCheck()) env->ExceptionClear();
    return category_failure_result_v2(
        env, "NATIVE_INTERNAL_ERROR", "Native internal error",
        "Category response is not valid UTF-8");
  } catch (const std::exception& error) {
    return category_failure_result_v2(
        env, "NATIVE_INTERNAL_ERROR", "Native internal error", error.what());
  } catch (...) {
    return category_failure_result_v2(
        env, "NATIVE_INTERNAL_ERROR", "Native internal error", "unknown exception");
  }
}

#define CALENDAR_V2_JNI(kotlin_name, cpp_name)                                              \
  extern "C" JNIEXPORT jstring JNICALL                                                     \
      Java_com_excellentcalendar_excellent_1calendar_bridge_native_JniNativeCalendarCoreBridge_##kotlin_name( \
          JNIEnv* env, jobject /* this */, jstring request_json) {                          \
    return call_boundary_v2(env, request_json, excellent_calendar::boundary::api::cpp_name); \
  }

CALENDAR_V2_JNI(nativeInitializeRuntimeV2, initialize_runtime_v2_json)
CALENDAR_V2_JNI(nativeResolveLocalDateTimeV2, resolve_local_datetime_v2)
CALENDAR_V2_JNI(nativeLocalizeInstantsV2, localize_instants_v2)
CALENDAR_V2_JNI(nativeCreateEventV2, create_event_v2)
CALENDAR_V2_JNI(nativeUpdateEventV2, update_event_v2)
CALENDAR_V2_JNI(nativeDeleteEventV2, delete_event_v2)
CALENDAR_V2_JNI(nativeSearchEventsV2, search_events_v2)
CALENDAR_V2_JNI(nativeGetEventDetailV2, get_event_detail_v2)
CALENDAR_V2_JNI(nativeCompleteEventV2, complete_event_v2)
CALENDAR_V2_JNI(nativeReopenEventV2, reopen_event_v2)
CALENDAR_V2_JNI(nativeListEventOccurrencesV2, list_event_occurrences_v2)
CALENDAR_V2_JNI(nativeCompleteEventOccurrenceV2, complete_event_occurrence_v2)
CALENDAR_V2_JNI(nativeReopenEventOccurrenceV2, reopen_event_occurrence_v2)
CALENDAR_V2_JNI(nativeSkipEventOccurrenceV2, skip_event_occurrence_v2)
CALENDAR_V2_JNI(nativeCancelEventOccurrenceV2, cancel_event_occurrence_v2)
CALENDAR_V2_JNI(nativeCompleteEventSeriesV2, complete_event_series_v2)
CALENDAR_V2_JNI(nativeReopenEventSeriesV2, reopen_event_series_v2)
CALENDAR_V2_JNI(nativeCancelEventSeriesV2, cancel_event_series_v2)
CALENDAR_V2_JNI(nativeCreateAnniversaryV2, create_anniversary_v2)
CALENDAR_V2_JNI(nativeUpdateAnniversaryV2, update_anniversary_v2)
CALENDAR_V2_JNI(nativeDeleteAnniversaryV2, delete_anniversary_v2)
CALENDAR_V2_JNI(nativeGetAnniversaryDetailV2, get_anniversary_detail_v2)
CALENDAR_V2_JNI(nativeListAnniversariesV2, list_anniversaries_v2)
CALENDAR_V2_JNI(nativePreviewAnniversaryCountdownV2, preview_anniversary_countdown_v2)
extern "C" JNIEXPORT jstring JNICALL
Java_com_excellentcalendar_excellent_1calendar_bridge_native_JniNativeCalendarCoreBridge_nativeListCategoriesV2(
    JNIEnv* env,
    jobject /* this */,
    jstring request_json) {
  return call_category_boundary_v2(
      env, request_json, excellent_calendar::boundary::api::list_categories_v2);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_excellentcalendar_excellent_1calendar_bridge_native_JniNativeCalendarCoreBridge_nativeCreateCategoryV2(
    JNIEnv* env,
    jobject /* this */,
    jstring request_json) {
  return call_category_boundary_v2(
      env, request_json, excellent_calendar::boundary::api::create_category_v2);
}
CALENDAR_V2_JNI(nativeCreateReminderV2, create_reminder_v2)
CALENDAR_V2_JNI(nativeUpdateReminderV2, update_reminder_v2)
CALENDAR_V2_JNI(nativeCancelReminderV2, cancel_reminder_v2)
CALENDAR_V2_JNI(nativeListRemindersV2, list_reminders_v2)
CALENDAR_V2_JNI(nativeGetReminderV2, get_reminder_v2)
CALENDAR_V2_JNI(nativeListSchedulableRemindersV2, list_schedulable_reminders_v2)
CALENDAR_V2_JNI(nativeMarkReminderScheduledV2, mark_reminder_scheduled_v2)
CALENDAR_V2_JNI(nativeEnableReminderV2, enable_reminder_v2)
CALENDAR_V2_JNI(nativeDisableReminderV2, disable_reminder_v2)
CALENDAR_V2_JNI(nativePrepareReminderDeliveryV2, prepare_reminder_delivery_v2)
CALENDAR_V2_JNI(nativeFinalizeReminderDeliveryV2, finalize_reminder_delivery_v2)
CALENDAR_V2_JNI(nativePlanReminderRecoveryV2, plan_reminder_recovery_v2)

#undef CALENDAR_V2_JNI
