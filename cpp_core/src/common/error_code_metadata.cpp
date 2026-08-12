#include "excellent_calendar/common/error_code_metadata.hpp"

#include <array>
#include <string_view>
#include <utility>

namespace excellent_calendar::common {
namespace {

// Contract v2 snapshot of contracts/error_codes.yaml. Keeping an explicit
// allow-list is intentional: a newly added cross-layer error code must not be
// accepted by an older Core until its retryability semantics are understood.
constexpr std::array<std::pair<std::string_view, bool>, 79> kErrorCodeMetadata{{
    {"NATIVE_INTERNAL_ERROR", false},
    {"CONTRACT_VALIDATION_FAILED", false},
    {"CONTRACT_VERSION_UNSUPPORTED", false},
    {"FEATURE_NOT_IMPLEMENTED", false},
    {"STORAGE_NOT_INITIALIZED", false},
    {"STORAGE_PATH_INVALID", false},
    {"STORAGE_IO_ERROR", true},
    {"STORAGE_DATA_CORRUPTED", false},
    {"TIMEZONE_ID_INVALID", false},
    {"TIMEZONE_DATABASE_UNAVAILABLE", false},
    {"EVENT_TITLE_EMPTY", false},
    {"EVENT_TIME_INVALID", false},
    {"EVENT_NOT_FOUND", false},
    {"EVENT_DELETE_SCOPE_INVALID", false},
    {"RECURRENCE_RULE_INVALID", false},
    {"RECURRENCE_TARGET_INVALID", false},
    {"ALL_DAY_RECURRING_REMINDER_NOT_SUPPORTED", false},
    {"OCCURRENCE_NOT_FOUND", false},
    {"OCCURRENCE_OPERATION_INVALID", false},
    {"RECURRENCE_REVISION_CONFLICT", false},
    {"REMINDER_TIME_INVALID", false},
    {"REMINDER_TARGET_NOT_FOUND", false},
    {"REMINDER_NOT_FOUND", false},
    {"REMINDER_METHOD_INVALID", false},
    {"REMINDER_IDEMPOTENCY_CONFLICT", false},
    {"REMINDER_SCHEDULE_CONFLICT", true},
    {"DELIVERY_ATTEMPT_INVALID", false},
    {"RECOVERY_BATCH_CONFLICT", true},
    {"NOTIFICATION_DELIVERY_FAILED", true},
    {"NOTIFICATION_INITIALIZATION_FAILED", true},
    {"HABIT_TITLE_EMPTY", false},
    {"HABIT_NOT_FOUND", false},
    {"HABIT_CHECK_IN_DUPLICATED", false},
    {"CATEGORY_NAME_EMPTY", false},
    {"CATEGORY_NOT_FOUND", false},
    {"CATEGORY_SORT_ORDER_EXHAUSTED", false},
    {"ANNIVERSARY_TITLE_EMPTY", false},
    {"ANNIVERSARY_DATE_INVALID", false},
    {"ANNIVERSARY_CALENDAR_UNSUPPORTED", false},
    {"ANNIVERSARY_NOT_FOUND", false},
    {"SEARCH_QUERY_INVALID", false},
    {"AI_EXTRACTION_FAILED", true},
    {"SYNC_CONFLICT", false},
    {"SYNC_OPERATION_INVALID", false},
    {"API_VALIDATION_FAILED", false},
    {"API_UNAUTHENTICATED", false},
    {"API_FORBIDDEN", false},
    {"API_RATE_LIMITED", true},
    {"API_INTERNAL_ERROR", true},
    {"AUTH_INVALID_CREDENTIALS", false},
    {"AUTH_EMAIL_UNVERIFIED", false},
    {"AUTH_ACCOUNT_DISABLED", false},
    {"AUTH_EMAIL_ALREADY_EXISTS", false},
    {"AUTH_USERNAME_ALREADY_EXISTS", false},
    {"AUTH_VERIFICATION_INVALID", false},
    {"AUTH_VERIFICATION_EXPIRED", false},
    {"AUTH_VERIFICATION_USED", false},
    {"AUTH_PASSWORD_POLICY_VIOLATION", false},
    {"AUTH_CURRENT_PASSWORD_INVALID", false},
    {"AUTH_PASSWORD_UNCHANGED", false},
    {"AUTH_REFRESH_TOKEN_INVALID", false},
    {"AUTH_REFRESH_TOKEN_REUSED", false},
    {"AUTH_SESSION_EXPIRED", false},
    {"USER_PROFILE_INVALID", false},
    {"AVATAR_TYPE_UNSUPPORTED", false},
    {"AVATAR_TOO_LARGE", false},
    {"AVATAR_UPLOAD_FAILED", true},
    {"SECURE_TOKEN_NOT_FOUND", false},
    {"SECURE_TOKEN_STORAGE_FAILED", true},
    {"SECURE_TOKEN_CORRUPTED", false},
    {"PERMISSION_DENIED", true},
    {"ALARM_SCHEDULE_FAILED", true},
    {"ALARM_CANCEL_FAILED", true},
    {"NOTIFICATION_PERMISSION_DENIED", true},
    {"EXACT_ALARM_PERMISSION_DENIED", true},
    {"UNSUPPORTED_REMINDER_METHOD", false},
    {"REMINDER_ALREADY_CONSUMED", false},
    {"REMINDER_NOT_DUE", true},
    {"REMINDER_NOT_DELIVERABLE", false},
}};

}  // namespace

std::optional<bool> contract_error_retryable(std::string_view error_code) {
  for (const auto& [code, retryable] : kErrorCodeMetadata) {
    if (code == error_code) return retryable;
  }
  return std::nullopt;
}

}  // namespace excellent_calendar::common
