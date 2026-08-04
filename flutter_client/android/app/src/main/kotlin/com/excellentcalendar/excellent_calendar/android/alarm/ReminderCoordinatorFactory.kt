package com.excellentcalendar.excellent_calendar.android.alarm

import android.content.Context
import android.util.Log
import com.excellentcalendar.excellent_calendar.android.notification.AndroidNotificationDisplayService
import com.excellentcalendar.excellent_calendar.android.notification.AndroidNotificationRuntime
import com.excellentcalendar.excellent_calendar.bridge.native.AndroidNativeBridgeFactory
import com.excellentcalendar.excellent_calendar.bridge.native.NativeContractProfile
import com.excellentcalendar.excellent_calendar.bridge.native.NativeContractRuntimeProfile
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderRecoveryCoordinator
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderDeliveryService
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderScheduleCoordinator
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderScheduleReconciler
import com.excellentcalendar.excellent_calendar.bridge.reminder.SharedPreferencesRecoveryRequestStore
import com.excellentcalendar.excellent_calendar.bridge.reminder.V2ReminderDeliveryService
import com.excellentcalendar.excellent_calendar.bridge.reminder.V2ReminderScheduleCoordinator

object ReminderCoordinatorFactory {
    fun create(context: Context): ReminderScheduleReconciler {
        val appContext = context.applicationContext
        val bridge = AndroidNativeBridgeFactory.create(appContext)
        val logger = { operation: String, reminderId: String?, message: String ->
            Log.d(LogTag, "operation=$operation reminder_id=${reminderId ?: "null"} $message")
            Unit
        }
        if (NativeContractRuntimeProfile.current == NativeContractProfile.V2) {
            val notifications = AndroidNotificationDisplayService(appContext)
            val delivery = V2ReminderDeliveryService(
                nativeBridge = bridge,
                notifications = notifications,
                eventHub = AndroidNotificationRuntime.eventHub,
                logger = logger,
            )
            val recovery = ReminderRecoveryCoordinator(
                nativeBridge = bridge,
                deliveryService = delivery,
                notifications = notifications,
                requestStore = SharedPreferencesRecoveryRequestStore(appContext),
                logger = logger,
            )
            return V2ReminderScheduleCoordinator(
                nativeBridge = bridge,
                alarmScheduler = ReminderDispatchAlarmScheduler(appContext),
                deliveryService = delivery,
                recoveryCoordinator = recovery,
                continuationEnqueuer = { ReminderWorkScheduler.enqueueContinuation(appContext) },
                logger = logger,
            )
        }
        LegacyReminderAlarmMigration.runIfNeeded(appContext, bridge)
        return ReminderScheduleCoordinator(
            nativeBridge = bridge,
            alarmScheduler = ReminderDispatchAlarmScheduler(appContext),
            deliveryService = ReminderDeliveryService(
                nativeReminderBridge = bridge,
                nativeNotificationBridge = bridge,
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
