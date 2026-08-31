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
import com.excellentcalendar.excellent_calendar.bridge.reminder.HabitAwareReminderScheduleReconciler
import com.excellentcalendar.excellent_calendar.bridge.reminder.HabitReconcileContinuation
import com.excellentcalendar.excellent_calendar.bridge.reminder.HabitReminderReconciler
import com.excellentcalendar.excellent_calendar.bridge.runtime.AndroidDeviceTimezoneProvider
import com.excellentcalendar.excellent_calendar.android.ring.RingRuntimeProvider

object ReminderCoordinatorFactory {
    fun create(
        context: Context,
        initialHabitCursor: String? = null,
    ): ReminderScheduleReconciler {
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
                ringRuntime = RingRuntimeProvider.get(appContext),
                timezoneProvider = AndroidDeviceTimezoneProvider,
            )
            val recovery = ReminderRecoveryCoordinator(
                nativeBridge = bridge,
                deliveryService = delivery,
                notifications = notifications,
                requestStore = SharedPreferencesRecoveryRequestStore(appContext),
                logger = logger,
                timezoneProvider = AndroidDeviceTimezoneProvider,
            )
            val shared = V2ReminderScheduleCoordinator(
                nativeBridge = bridge,
                alarmScheduler = ReminderDispatchAlarmScheduler(appContext),
                deliveryService = delivery,
                recoveryCoordinator = recovery,
                continuationEnqueuer = { enqueueConfirmedContinuation(appContext) },
                logger = logger,
            )
            return HabitAwareReminderScheduleReconciler(
                habit = HabitReminderReconciler(
                    bridge = bridge,
                    timezoneProvider = AndroidDeviceTimezoneProvider,
                    continuationEnqueuer = {
                        enqueueConfirmedHabitContinuation(appContext, it)
                    },
                    logger = logger,
                ),
                shared = shared,
                initialHabitCursor = initialHabitCursor,
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
            continuationEnqueuer = { enqueueConfirmedContinuation(appContext) },
            logger = logger,
        )
    }

    private fun enqueueConfirmedContinuation(context: Context) {
        check(ReminderWorkScheduler.enqueueConfirmedContinuation(context)) {
            "Reminder continuation could not be persisted"
        }
    }

    private fun enqueueConfirmedHabitContinuation(
        context: Context,
        continuation: HabitReconcileContinuation,
    ) {
        check(
            ReminderWorkScheduler.enqueueConfirmedHabitContinuation(
                context,
                continuation,
            ),
        ) {
            "Habit reminder continuation could not be persisted"
        }
    }

    private const val LogTag = "ExcellentCalendarQueue"
}
