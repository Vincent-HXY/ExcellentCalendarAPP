package com.excellentcalendar.excellent_calendar.bridge.contract

object NativeErrorCodes {
    const val NativeInternalError = "NATIVE_INTERNAL_ERROR"
    const val ContractValidationFailed = "CONTRACT_VALIDATION_FAILED"
    const val ContractVersionUnsupported = "CONTRACT_VERSION_UNSUPPORTED"
    const val FeatureNotImplemented = "FEATURE_NOT_IMPLEMENTED"
    const val StorageNotInitialized = "STORAGE_NOT_INITIALIZED"
    const val StoragePathInvalid = "STORAGE_PATH_INVALID"
    const val StorageIoError = "STORAGE_IO_ERROR"
    const val StorageDataCorrupted = "STORAGE_DATA_CORRUPTED"
    const val EventTitleEmpty = "EVENT_TITLE_EMPTY"
    const val EventTimeInvalid = "EVENT_TIME_INVALID"
    const val EventNotFound = "EVENT_NOT_FOUND"
    const val EventDeleteScopeInvalid = "EVENT_DELETE_SCOPE_INVALID"
    const val RecurrenceRuleInvalid = "RECURRENCE_RULE_INVALID"
    const val RecurrenceTargetInvalid = "RECURRENCE_TARGET_INVALID"
    const val ReminderTimeInvalid = "REMINDER_TIME_INVALID"
    const val ReminderTargetNotFound = "REMINDER_TARGET_NOT_FOUND"
    const val ReminderMethodInvalid = "REMINDER_METHOD_INVALID"
    const val NotificationDeliveryFailed = "NOTIFICATION_DELIVERY_FAILED"
    const val HabitTitleEmpty = "HABIT_TITLE_EMPTY"
    const val HabitNotFound = "HABIT_NOT_FOUND"
    const val HabitCheckInDuplicated = "HABIT_CHECK_IN_DUPLICATED"
    const val CategoryNameEmpty = "CATEGORY_NAME_EMPTY"
    const val CategoryNotFound = "CATEGORY_NOT_FOUND"
    const val AnniversaryTitleEmpty = "ANNIVERSARY_TITLE_EMPTY"
    const val AnniversaryDateInvalid = "ANNIVERSARY_DATE_INVALID"
    const val AnniversaryNotFound = "ANNIVERSARY_NOT_FOUND"
    const val SearchQueryInvalid = "SEARCH_QUERY_INVALID"
    const val AiExtractionFailed = "AI_EXTRACTION_FAILED"
    const val SyncConflict = "SYNC_CONFLICT"
    const val SyncOperationInvalid = "SYNC_OPERATION_INVALID"
    const val UserSettingsInvalid = "USER_SETTINGS_INVALID"
    const val PermissionDenied = "PERMISSION_DENIED"
    const val AlarmScheduleFailed = "ALARM_SCHEDULE_FAILED"

    val All = setOf(
        NativeInternalError,
        ContractValidationFailed,
        ContractVersionUnsupported,
        FeatureNotImplemented,
        StorageNotInitialized,
        StoragePathInvalid,
        StorageIoError,
        StorageDataCorrupted,
        EventTitleEmpty,
        EventTimeInvalid,
        EventNotFound,
        EventDeleteScopeInvalid,
        RecurrenceRuleInvalid,
        RecurrenceTargetInvalid,
        ReminderTimeInvalid,
        ReminderTargetNotFound,
        ReminderMethodInvalid,
        NotificationDeliveryFailed,
        HabitTitleEmpty,
        HabitNotFound,
        HabitCheckInDuplicated,
        CategoryNameEmpty,
        CategoryNotFound,
        AnniversaryTitleEmpty,
        AnniversaryDateInvalid,
        AnniversaryNotFound,
        SearchQueryInvalid,
        AiExtractionFailed,
        SyncConflict,
        SyncOperationInvalid,
        UserSettingsInvalid,
        PermissionDenied,
        AlarmScheduleFailed,
    )
}

data class NativeErrorContract(
    val code: String,
    val message: String,
    val details: Map<String, Any?>?,
    val retryable: Boolean,
) {
    fun toMap(): Map<String, Any?> = linkedMapOf(
        "code" to code,
        "message" to message,
        "details" to details,
        "retryable" to retryable,
    )

    companion object {
        fun fromMap(map: Map<String, Any?>): NativeErrorContract {
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
