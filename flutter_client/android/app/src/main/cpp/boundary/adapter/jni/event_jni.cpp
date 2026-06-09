#include <jni.h>

#include <exception>
#include <string>
#include <string_view>

#include "excellent_calendar/boundary/api/event_api.hpp"
#include "excellent_calendar/boundary/contract/native_result.hpp"
#include "excellent_calendar/common/id_generator.hpp"
#include "excellent_calendar/common/result.hpp"

namespace {

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

jstring to_jstring(JNIEnv* env, const std::string& value) {
  return env->NewStringUTF(value.c_str());
}

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

extern "C" JNIEXPORT jstring JNICALL
Java_com_excellentcalendar_excellent_1calendar_bridge_native_JniNativeEventBridge_nativeInitializeStorage(
    JNIEnv* env,
    jobject /* this */,
    jstring storage_directory) {
  return call_boundary(env, storage_directory, excellent_calendar::boundary::api::initialize_storage);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_excellentcalendar_excellent_1calendar_bridge_native_JniNativeEventBridge_nativeCreateEvent(
    JNIEnv* env,
    jobject /* this */,
    jstring request_json) {
  return call_boundary(env, request_json, excellent_calendar::boundary::api::create_event);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_excellentcalendar_excellent_1calendar_bridge_native_JniNativeEventBridge_nativeSearchEvents(
    JNIEnv* env,
    jobject /* this */,
    jstring request_json) {
  return call_boundary(env, request_json, excellent_calendar::boundary::api::search_events);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_excellentcalendar_excellent_1calendar_bridge_native_JniNativeEventBridge_nativeCompleteEvent(
    JNIEnv* env,
    jobject /* this */,
    jstring request_json) {
  return call_boundary(env, request_json, excellent_calendar::boundary::api::complete_event);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_excellentcalendar_excellent_1calendar_bridge_native_JniNativeEventBridge_nativeReopenEvent(
    JNIEnv* env,
    jobject /* this */,
    jstring request_json) {
  return call_boundary(env, request_json, excellent_calendar::boundary::api::reopen_event);
}
