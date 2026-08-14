package com.excellentcalendar.excellent_calendar.bridge.contract

/**
 * native 层允许返回的错误码全集。
 *
 * 用常量集中管理错误码可以避免各层手写字符串时拼错，也方便 Dart 根据 code 做用户提示、
 * 重试策略或埋点统计。
 */
object NativeErrorCodes {
    const val NativeInternalError = "NATIVE_INTERNAL_ERROR"
    const val ContractValidationFailed = "CONTRACT_VALIDATION_FAILED"
    const val ContractVersionUnsupported = "CONTRACT_VERSION_UNSUPPORTED"
    const val FeatureNotImplemented = "FEATURE_NOT_IMPLEMENTED"
    const val StorageNotInitialized = "STORAGE_NOT_INITIALIZED"
    const val StoragePathInvalid = "STORAGE_PATH_INVALID"
    const val StorageIoError = "STORAGE_IO_ERROR"
    const val StorageDataCorrupted = "STORAGE_DATA_CORRUPTED"
    const val TimezoneIdInvalid = "TIMEZONE_ID_INVALID"
    const val TimezoneDatabaseUnavailable = "TIMEZONE_DATABASE_UNAVAILABLE"
    const val EventTitleEmpty = "EVENT_TITLE_EMPTY"
    const val EventTimeInvalid = "EVENT_TIME_INVALID"
    const val EventNotFound = "EVENT_NOT_FOUND"
    const val EventDeleteScopeInvalid = "EVENT_DELETE_SCOPE_INVALID"
    const val RecurrenceRuleInvalid = "RECURRENCE_RULE_INVALID"
    const val RecurrenceTargetInvalid = "RECURRENCE_TARGET_INVALID"
    const val AllDayRecurringReminderNotSupported = "ALL_DAY_RECURRING_REMINDER_NOT_SUPPORTED"
    const val OccurrenceNotFound = "OCCURRENCE_NOT_FOUND"
    const val OccurrenceOperationInvalid = "OCCURRENCE_OPERATION_INVALID"
    const val RecurrenceRevisionConflict = "RECURRENCE_REVISION_CONFLICT"
    const val ReminderTimeInvalid = "REMINDER_TIME_INVALID"
    const val ReminderTargetNotFound = "REMINDER_TARGET_NOT_FOUND"
    const val ReminderNotFound = "REMINDER_NOT_FOUND"
    const val ReminderMethodInvalid = "REMINDER_METHOD_INVALID"
    const val ReminderIdempotencyConflict = "REMINDER_IDEMPOTENCY_CONFLICT"
    const val ReminderScheduleConflict = "REMINDER_SCHEDULE_CONFLICT"
    const val DeliveryAttemptInvalid = "DELIVERY_ATTEMPT_INVALID"
    const val RecoveryBatchConflict = "RECOVERY_BATCH_CONFLICT"
    const val NotificationDeliveryFailed = "NOTIFICATION_DELIVERY_FAILED"
    const val HabitTitleEmpty = "HABIT_TITLE_EMPTY"
    const val HabitNotFound = "HABIT_NOT_FOUND"
    const val HabitCheckInDuplicated = "HABIT_CHECK_IN_DUPLICATED"
    const val CategoryNameEmpty = "CATEGORY_NAME_EMPTY"
    const val CategoryNotFound = "CATEGORY_NOT_FOUND"
    const val CategorySortOrderExhausted = "CATEGORY_SORT_ORDER_EXHAUSTED"
    const val AnniversaryTitleEmpty = "ANNIVERSARY_TITLE_EMPTY"
    const val AnniversaryDateInvalid = "ANNIVERSARY_DATE_INVALID"
    const val AnniversaryCalendarUnsupported = "ANNIVERSARY_CALENDAR_UNSUPPORTED"
    const val AnniversaryNotFound = "ANNIVERSARY_NOT_FOUND"
    const val SearchQueryInvalid = "SEARCH_QUERY_INVALID"
    const val AiExtractionFailed = "AI_EXTRACTION_FAILED"
    const val SyncConflict = "SYNC_CONFLICT"
    const val SyncOperationInvalid = "SYNC_OPERATION_INVALID"
    const val SecureTokenNotFound = "SECURE_TOKEN_NOT_FOUND"
    const val SecureTokenStorageFailed = "SECURE_TOKEN_STORAGE_FAILED"
    const val SecureTokenCorrupted = "SECURE_TOKEN_CORRUPTED"
    const val PermissionDenied = "PERMISSION_DENIED"
    const val AlarmScheduleFailed = "ALARM_SCHEDULE_FAILED"
    const val AlarmCancelFailed = "ALARM_CANCEL_FAILED"
    const val NotificationPermissionDenied = "NOTIFICATION_PERMISSION_DENIED"
    const val ExactAlarmPermissionDenied = "EXACT_ALARM_PERMISSION_DENIED"
    const val UnsupportedReminderMethod = "UNSUPPORTED_REMINDER_METHOD"
    const val ReminderAlreadyConsumed = "REMINDER_ALREADY_CONSUMED"
    const val ReminderNotDue = "REMINDER_NOT_DUE"
    const val ReminderNotDeliverable = "REMINDER_NOT_DELIVERABLE"
    const val NotificationInitializationFailed = "NOTIFICATION_INITIALIZATION_FAILED"

    /** 用于校验 native 返回的错误码是否是协议中声明过的值。 */
    val All = setOf(
        NativeInternalError,
        ContractValidationFailed,
        ContractVersionUnsupported,
        FeatureNotImplemented,
        StorageNotInitialized,
        StoragePathInvalid,
        StorageIoError,
        StorageDataCorrupted,
        TimezoneIdInvalid,
        TimezoneDatabaseUnavailable,
        EventTitleEmpty,
        EventTimeInvalid,
        EventNotFound,
        EventDeleteScopeInvalid,
        RecurrenceRuleInvalid,
        RecurrenceTargetInvalid,
        AllDayRecurringReminderNotSupported,
        OccurrenceNotFound,
        OccurrenceOperationInvalid,
        RecurrenceRevisionConflict,
        ReminderTimeInvalid,
        ReminderTargetNotFound,
        ReminderNotFound,
        ReminderMethodInvalid,
        ReminderIdempotencyConflict,
        ReminderScheduleConflict,
        DeliveryAttemptInvalid,
        RecoveryBatchConflict,
        NotificationDeliveryFailed,
        HabitTitleEmpty,
        HabitNotFound,
        HabitCheckInDuplicated,
        CategoryNameEmpty,
        CategoryNotFound,
        CategorySortOrderExhausted,
        AnniversaryTitleEmpty,
        AnniversaryDateInvalid,
        AnniversaryCalendarUnsupported,
        AnniversaryNotFound,
        SearchQueryInvalid,
        AiExtractionFailed,
        SyncConflict,
        SyncOperationInvalid,
        SecureTokenNotFound,
        SecureTokenStorageFailed,
        SecureTokenCorrupted,
        PermissionDenied,
        AlarmScheduleFailed,
        AlarmCancelFailed,
        NotificationPermissionDenied,
        ExactAlarmPermissionDenied,
        UnsupportedReminderMethod,
        ReminderAlreadyConsumed,
        ReminderNotDue,
        ReminderNotDeliverable,
        NotificationInitializationFailed,
    )
}

/**
 * NativeResult 中的错误对象。
 *
 * 字段意义：
 * - `code`：机器可读错误码，适合分支判断。
 * - `message`：人类可读说明，适合日志或调试。
 * - `details`：补充上下文，例如出错字段、操作名。
 * - `retryable`：调用方是否可以稍后重试。
 */
data class NativeErrorContract(
    val code: String,
    val message: String,
    val details: Map<String, Any?>?,
    val retryable: Boolean,
) {
    /** 转成 MethodChannel 可返回的 Map。 */
    fun toMap(): Map<String, Any?> = linkedMapOf(
        "code" to code,
        "message" to message,
        "details" to details,
        "retryable" to retryable,
    )

    companion object {
        /** 从 native 返回的 Map 构造错误对象，并校验字段类型和值域。 */
        fun fromMap(map: Map<String, Any?>, strict: Boolean = false): NativeErrorContract {
            if (strict) {
                ContractValidators.rejectUnknownFields(
                    map,
                    setOf("code", "message", "details", "retryable"),
                    "NativeError",
                )
            }
            val code = map["code"]
            val message = map["message"]
            val details = map["details"]
            val retryable = map["retryable"]

            if (code !is String || code.isBlank()) {
                throw NativeContractViolation("NativeError.code must be a non-empty string.", "error.code")
            }
            if (code !in NativeErrorCodes.All) {
                throw NativeContractViolation("NativeError.code is not declared in error_codes.yaml.", "error.code")
            }
            if (message !is String || message.isBlank()) {
                throw NativeContractViolation("NativeError.message must be a non-empty string.", "error.message")
            }
            if (details != null && details !is Map<*, *>) {
                throw NativeContractViolation("NativeError.details must be an object or null.", "error.details")
            }
            if (retryable != null && retryable !is Boolean) {
                throw NativeContractViolation("NativeError.retryable must be boolean.", "error.retryable")
            }

            // 泛型类型在 JVM 运行时会被擦除，因此 Map<String, Any?> 需要在边界处显式 suppress。
            @Suppress("UNCHECKED_CAST")
            return NativeErrorContract(
                code = code,
                message = message,
                details = details as Map<String, Any?>?,
                retryable = retryable as Boolean? ?: false,
            )
        }
    }
}
