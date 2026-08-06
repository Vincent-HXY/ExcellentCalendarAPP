package com.excellentcalendar.excellent_calendar.bridge.contract

enum class ReminderScheduleTrigger(val wireValue: String) {
    AppStart("app_start"),
    AppResume("app_resume"),
    Mutation("mutation"),
    BootCompleted("boot_completed"),
    PackageReplaced("package_replaced"),
    TimeChanged("time_changed"),
    TimezoneChanged("timezone_changed"),
    PeriodicWorker("periodic_worker"),
    AlarmFired("alarm_fired"),
    ManualRetry("manual_retry");

    companion object {
        fun fromWire(value: String): ReminderScheduleTrigger = entries.firstOrNull { it.wireValue == value }
            ?: throw NativeContractViolation("Unsupported reminder schedule trigger_source.", "trigger_source")
    }
}

data class ReconcileReminderScheduleContract(
    val trigger: ReminderScheduleTrigger,
    val force: Boolean,
) {
    companion object {
        fun fromMethodArguments(arguments: Any?): ReconcileReminderScheduleContract {
            val map = NativeArguments.normalize(arguments)
            val parent = "ReconcileReminderScheduleRequest"
            ContractValidators.rejectUnknownFields(map, setOf("trigger_source", "force"), parent)
            ContractValidators.requireString(map, "trigger_source", parent, nonEmpty = true)
            ContractValidators.optionalBoolean(map, "force", parent)
            return ReconcileReminderScheduleContract(
                trigger = ReminderScheduleTrigger.fromWire(map["trigger_source"] as String),
                force = map["force"] as Boolean? ?: false,
            )
        }
    }
}

object ReconcileReminderScheduleResponseContract {
    fun validate(data: Any?) {
        if (data !is Map<*, *>) throw NativeContractViolation("Reconcile response must be an object.", "data")
        @Suppress("UNCHECKED_CAST")
        val map = data as Map<String, Any?>
        val parent = "ReconcileReminderScheduleResponse"
        ContractValidators.rejectUnknownFields(
            map,
            setOf(
                "action", "next_remind_at", "processed_due_count", "failed_count",
                "continuation_enqueued", "failed_reminder_ids",
            ),
            parent,
        )
        ContractValidators.requireEnum(map, "action", parent, setOf("scheduled", "cancelled", "unchanged"))
        ContractValidators.optionalString(map, "next_remind_at", parent)
        ContractValidators.requireInteger(map, "processed_due_count", parent)
        ContractValidators.requireInteger(map, "failed_count", parent)
        ContractValidators.requireBoolean(map, "continuation_enqueued", parent)
        val failures = map["failed_reminder_ids"]
        if (failures !is List<*> || failures.any { it !is String || it.isBlank() }) {
            throw NativeContractViolation("$parent.failed_reminder_ids must be a string array.", "$parent.failed_reminder_ids")
        }
    }
}

private object NativeArguments {
    fun normalize(arguments: Any?): Map<String, Any?> = try {
        com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec.normalizeMap(arguments)
    } catch (error: IllegalArgumentException) {
        throw NativeContractViolation(error.message ?: "Invalid MethodChannel arguments.", cause = error)
    }
}
