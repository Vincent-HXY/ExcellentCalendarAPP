package com.excellentcalendar.excellent_calendar.bridge.contract

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec

data class UpdateEventRequestContract(
    private val payload: Map<String, Any?>,
) {
    fun toJson(): String = NativeContractJsonCodec.encodeObject(payload)

    fun toMap(): Map<String, Any?> = payload

    companion object {
        private val AllowedFields = setOf(
            "id",
            "title",
            "content",
            "start_at",
            "end_at",
            "is_all_day",
            "category_id",
            "importance",
            "location",
            "timezone",
            "source",
            "recurrence",
            "reminders",
        )

        fun fromMethodArguments(arguments: Any?): UpdateEventRequestContract {
            val map = try {
                NativeContractJsonCodec.normalizeMap(arguments)
            } catch (error: IllegalArgumentException) {
                throw NativeContractViolation(error.message ?: "Invalid MethodChannel arguments.", cause = error)
            }
            validate(map)
            return UpdateEventRequestContract(map)
        }

        private fun validate(map: Map<String, Any?>) {
            val parent = "UpdateEventRequest"
            ContractValidators.rejectUnknownFields(map, AllowedFields, parent)
            ContractValidators.requireString(map, "id", parent, nonEmpty = true)
            if (map.containsKey("title")) {
                ContractValidators.requireString(map, "title", parent, nonEmpty = true)
            }
            ContractValidators.optionalString(map, "content", parent)
            ContractValidators.optionalString(map, "start_at", parent)
            ContractValidators.optionalString(map, "end_at", parent)
            ContractValidators.optionalBoolean(map, "is_all_day", parent)
            ContractValidators.optionalString(map, "category_id", parent)
            ContractValidators.optionalEnum(map, "importance", parent, ContractEnums.Importance)
            ContractValidators.optionalString(map, "location", parent)
            ContractValidators.optionalString(map, "timezone", parent)
            ContractValidators.optionalEnum(map, "source", parent, ContractEnums.CreateEventSource)
            ContractValidators.optionalObject(map, "recurrence", parent)?.let {
                validateRecurrenceRule(it, "$parent.recurrence")
            }
            ContractValidators.optionalObjectArray(map, "reminders", parent).forEachIndexed { index, reminder ->
                validateReminderDraft(reminder, "$parent.reminders[$index]")
            }
        }

        private fun validateRecurrenceRule(map: Map<String, Any?>, parent: String) {
            ContractValidators.rejectUnknownFields(
                map,
                setOf(
                    "frequency",
                    "interval",
                    "days_of_week",
                    "day_of_month",
                    "month_of_year",
                    "start_at",
                    "end_at",
                    "count",
                    "timezone",
                    "rrule",
                ),
                parent,
            )
            ContractValidators.requireEnum(map, "frequency", parent, ContractEnums.RecurrenceFrequency)
            ContractValidators.requireInteger(map, "interval", parent)
            val daysOfWeek = map["days_of_week"]
            if (daysOfWeek != null) {
                if (daysOfWeek !is List<*>) {
                    throw NativeContractViolation("$parent.days_of_week must be an array.", "$parent.days_of_week")
                }
                daysOfWeek.forEachIndexed { index, value ->
                    if (value !is Int && value !is Long) {
                        throw NativeContractViolation(
                            "$parent.days_of_week item must be integer.",
                            "$parent.days_of_week[$index]",
                        )
                    }
                }
            }
            ContractValidators.optionalInteger(map, "day_of_month", parent)
            ContractValidators.optionalInteger(map, "month_of_year", parent)
            ContractValidators.requireString(map, "start_at", parent, nonEmpty = true)
            ContractValidators.optionalString(map, "end_at", parent)
            ContractValidators.optionalInteger(map, "count", parent)
            if (!map.containsKey("timezone")) {
                throw NativeContractViolation("$parent.timezone is required.", "$parent.timezone")
            }
            ContractValidators.optionalString(map, "timezone", parent)
            ContractValidators.optionalString(map, "rrule", parent)
        }

        private fun validateReminderDraft(map: Map<String, Any?>, parent: String) {
            ContractValidators.rejectUnknownFields(
                map,
                setOf(
                    "target_type",
                    "target_id",
                    "remind_at",
                    "advance_minutes",
                    "methods",
                    "message",
                    "is_enabled",
                    "source",
                ),
                parent,
            )
            ContractValidators.requireEnum(map, "target_type", parent, setOf("event", "anniversary"))
            ContractValidators.optionalString(map, "target_id", parent)
            ContractValidators.optionalString(map, "remind_at", parent)
            ContractValidators.optionalInteger(map, "advance_minutes", parent)
            val remindAt = map["remind_at"]
            val advanceMinutes = map["advance_minutes"]
            if (remindAt == null && advanceMinutes == null) {
                throw NativeContractViolation("$parent requires remind_at or advance_minutes.", "$parent.remind_at")
            }
            when (advanceMinutes) {
                is Int -> if (advanceMinutes < 0) {
                    throw NativeContractViolation("$parent.advance_minutes must be >= 0.", "$parent.advance_minutes")
                }
                is Long -> if (advanceMinutes < 0L) {
                    throw NativeContractViolation("$parent.advance_minutes must be >= 0.", "$parent.advance_minutes")
                }
            }
            ContractValidators.optionalStringArray(map, "methods", parent, ContractEnums.ReminderMethods)
            val methods = map["methods"]
            if (methods !is List<*> || methods.isEmpty()) {
                throw NativeContractViolation("$parent.methods must be a non-empty array.", "$parent.methods")
            }
            if (methods.toSet().size != methods.size) {
                throw NativeContractViolation("$parent.methods must not contain duplicates.", "$parent.methods")
            }
            ContractValidators.optionalString(map, "message", parent)
            ContractValidators.requireBoolean(map, "is_enabled", parent)
            ContractValidators.requireEnum(map, "source", parent, ContractEnums.ReminderSource)
        }
    }
}
