package com.excellentcalendar.excellent_calendar.android.alarm

import android.content.Context
import android.util.Log
import com.excellentcalendar.excellent_calendar.android.notification.AndroidNotificationDisplayService
import com.excellentcalendar.excellent_calendar.android.notification.AndroidNotificationRuntime
import com.excellentcalendar.excellent_calendar.bridge.native.AndroidNativeBridgeFactory
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderDeliveryService
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderScheduleCoordinator

object ReminderCoordinatorFactory {
    fun create(context: Context): ReminderScheduleCoordinator {
        val appContext = context.applicationContext
        val bridge = AndroidNativeBridgeFactory.create(appContext)
        LegacyReminderAlarmMigration.runIfNeeded(appContext, bridge)
        val logger = { operation: String, reminderId: String?, message: String ->
            Log.d(LogTag, "operation=$operation reminder_id=${reminderId ?: "null"} $message")
            Unit
        }
        return ReminderScheduleCoordinator(
            nativeBridge = bridge,
            alarmScheduler = ReminderDispatchAlarmScheduler(appContext),
            deliveryService = ReminderDeliveryService(
                nativeBridge = bridge,
                notifications = AndroidNotificationDisplayService(appContext),
                eventHub = AndroidNotificationRuntime.eventHub,
                logger = logger,
            ),
            continuationEnqueuer = { ReminderWorkScheduler.enqueueContinuation(appContext) },
            logger = logger,
        )
    }

    private const val LogTag = "ExcellentCalendarQueue"
}
