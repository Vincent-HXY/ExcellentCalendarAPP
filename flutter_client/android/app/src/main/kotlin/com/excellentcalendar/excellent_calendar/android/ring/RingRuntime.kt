package com.excellentcalendar.excellent_calendar.android.ring

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.excellentcalendar.excellent_calendar.android.notification.AndroidNotificationChannelManager
import com.excellentcalendar.excellent_calendar.android.notification.AndroidNotificationRuntime
import com.excellentcalendar.excellent_calendar.android.alarm.ReminderCoordinatorFactory
import com.excellentcalendar.excellent_calendar.android.alarm.ReminderWorkScheduler
import com.excellentcalendar.excellent_calendar.bridge.contract.ActiveRingItemsContract
import com.excellentcalendar.excellent_calendar.bridge.contract.CompleteRingItemContract
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReconcileReminderScheduleContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderScheduleTrigger
import com.excellentcalendar.excellent_calendar.bridge.contract.V2FinalizeDelivery
import com.excellentcalendar.excellent_calendar.bridge.contract.V2PreparedDelivery
import com.excellentcalendar.excellent_calendar.bridge.native.AndroidNativeBridgeFactory
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderDeliveryAttemptClient
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderOrchestrationLogger
import com.excellentcalendar.excellent_calendar.bridge.ring.PreparedRingItem
import com.excellentcalendar.excellent_calendar.bridge.ring.RingNativeWorkflowClient
import com.excellentcalendar.excellent_calendar.bridge.ring.RingSessionManager
import com.excellentcalendar.excellent_calendar.bridge.ring.RingSnoozeWorkflowCoordinator
import com.excellentcalendar.excellent_calendar.bridge.ring.RingStateEventHub

class RingRuntime internal constructor(
    private val appContext: Context,
    private val manager: RingSessionManager,
    private val output: RingOutputController,
    private val attemptClient: ReminderDeliveryAttemptClient,
    private val workflows: RingNativeWorkflowClient,
    afterSnoozeCommitted: () -> Boolean,
) {
    private val handler = Handler(Looper.getMainLooper())
    private var service: ReminderRingService? = null
    private var outputActive = false
    private var retryScheduled = false
    private val snoozeWorkflow = RingSnoozeWorkflowCoordinator(manager, workflows::snooze, afterSnoozeCommitted)

    fun state(): NativeResultContract = manager.getState()
    fun activeSession(): RingSessionRecord? = manager.activeSession()

    fun recoverIfNeeded() {
        var session = manager.activeSession() ?: return
        if (session.phase == "audible" && session.items.any { it.finalizeOutcome?.endsWith("_pending") == true }) {
            manager.enterQuiet()
            session = manager.activeSession() ?: return
        }
        manager.emitRecovered()
        refreshNotification()
        if (session.phase != "quiet_pending" || session.items.any { it.finalizeOutcome?.endsWith("_pending") == true }) {
            RingServiceStarter.startOrSchedule(appContext)
        }
    }

    fun enqueue(prepared: V2PreparedDelivery): NativeResultContract {
        if (manager.currentSnapshot()["test_state"] == "audible") {
            output.stop()
            outputActive = false
            manager.setTestState(manager.settings().revision, false)
        }
        @Suppress("UNCHECKED_CAST")
        val capability = manager.currentSnapshot()["capability"] as Map<String, Any?>
        if (capability["can_enable_ring"] != true) {
            attemptClient.finalize(
                prepared,
                "failed",
                NativeErrorCodes.RingCapabilityUnavailable,
                failureRetryable = true,
            )
            return NativeResultContract.failure(
                NativeErrorCodes.RingCapabilityUnavailable,
                "Required Android ring capability is unavailable.",
                details = linkedMapOf("blocking_reasons" to capability["blocking_reasons"]),
                retryable = true,
                contractVersion = 2,
            )
        }
        val added = manager.addPrepared(
            PreparedRingItem(
                prepared.notificationId,
                prepared.deliveryId,
                prepared.attemptId,
                prepared.reminderId,
                prepared.eventId,
                prepared.recoveryBatchId,
                prepared.plannedAt,
            ),
        )
        if (!added.ok) return added
        refreshNotification()
        if (!RingServiceStarter.startOrSchedule(appContext)) {
            manager.markFinalizeOutcome(prepared.deliveryId, "failed_pending")
            val finalized = attemptClient.finalize(
                prepared,
                "failed",
                NativeErrorCodes.RingControlNotificationFailed,
                failureRetryable = true,
            )
            if (finalized.ok) manager.remove(listOf(prepared.deliveryId))
            return NativeResultContract.failure(
                NativeErrorCodes.RingControlNotificationFailed,
                "Ring foreground service could not be scheduled.",
                retryable = true,
                contractVersion = 2,
            )
        }
        return NativeResultContract.success(
            linkedMapOf("delivery_id" to prepared.deliveryId, "ring_start_queued" to true),
            contractVersion = 2,
        )
    }

    fun onForegroundShown(owner: ReminderRingService) {
        service = owner
        manager.markControlVisible()
        val session = manager.activeSession() ?: return owner.stopRingService(removeNotification = true)
        retryPendingFinalizations()
        val freshItems = manager.activeSession()?.items?.filter { it.finalizeOutcome == null }.orEmpty()
        if (freshItems.isNotEmpty()) {
            val result = if (outputActive) {
                RingOutputStartResult(
                    soundStarted = session.soundActive,
                    vibrationStarted = session.vibrationActive,
                )
            } else {
                output.start(manager.settings()).also { outputActive = it.anyStarted }
            }
            if (result.anyStarted) {
                manager.beginAudible(result.soundStarted, result.vibrationStarted, MaxAudibleMillis)
                freshItems.forEach { manager.markFinalizeOutcome(it.deliveryId, "sent_pending") }
                retryPendingFinalizations()
                scheduleDeadline()
            } else {
                freshItems.forEach { manager.markFinalizeOutcome(it.deliveryId, "failed_pending") }
                retryPendingFinalizations()
                if (manager.activeSession() != null) owner.detachQuietNotification()
            }
        } else if (session.phase == "audible") {
            val deadlineStillOpen = session.audibleDeadlineAt?.let { ringUtcToMillis(it) > System.currentTimeMillis() } == true
            if (!deadlineStillOpen) {
                manager.enterQuiet()
            } else if (!outputActive && manager.activeSession()?.items?.all { it.finalizeOutcome == "sent" } == true) {
                val resumed = output.start(manager.settings())
                outputActive = resumed.anyStarted
                if (resumed.anyStarted) manager.beginAudible(resumed.soundStarted, resumed.vibrationStarted, MaxAudibleMillis)
                else manager.enterQuiet()
            }
            scheduleDeadline()
        } else if (session.phase == "quiet_pending") {
            owner.detachQuietNotification()
        }
        refreshNotification()
    }

    fun onServiceDestroyed(owner: ReminderRingService) {
        if (service === owner) service = null
    }

    fun onControlNotificationFailed() {
        manager.activeSession()?.items
            ?.filter { it.finalizeOutcome == null }
            ?.forEach { manager.markFinalizeOutcome(it.deliveryId, "failed_pending") }
        retryPendingFinalizations()
    }

    fun stopActive(request: ActiveRingItemsContract): NativeResultContract {
        manager.validate(request)?.let { return it }
        val result = manager.remove(request.deliveryIds)
        afterItemsRemoved()
        return result
    }

    fun snoozeActive(request: ActiveRingItemsContract): NativeResultContract {
        val result = snoozeWorkflow.snooze(request)
        afterItemsRemoved()
        return result
    }

    fun completeItem(request: CompleteRingItemContract): NativeResultContract {
        manager.validate(request)?.let { return it }
        val item = manager.items(listOf(request.deliveryId)).single()
        val completed = workflows.complete(item)
        if (!completed.ok) return completed
        val result = manager.remove(listOf(request.deliveryId))
        afterItemsRemoved()
        return result
    }

    fun stopFromNotification(deliveryIds: List<String>) {
        manager.remove(deliveryIds)
        afterItemsRemoved()
    }

    fun snoozeFromNotification(deliveryIds: List<String>): NativeResultContract {
        val result = snoozeWorkflow.snoozeFromNotification(deliveryIds)
        afterItemsRemoved()
        return result
    }

    fun completeFromNotification(deliveryId: String) {
        val item = manager.items(listOf(deliveryId)).firstOrNull() ?: return
        if (workflows.complete(item).ok) manager.remove(listOf(deliveryId))
        afterItemsRemoved()
    }

    fun updateSettings(expectedRevision: Long, enabled: Boolean): NativeResultContract =
        manager.updateSettings(expectedRevision, enabled)

    fun updateRingtone(expectedRevision: Long, uri: String, name: String, available: Boolean): NativeResultContract =
        manager.updateRingtone(expectedRevision, uri, name, available)

    fun test(expectedRevision: Long, start: Boolean): NativeResultContract {
        if (!start) {
            output.stop()
            outputActive = false
            return manager.setTestState(expectedRevision, false)
        }
        if (manager.activeSession() != null) {
            return NativeResultContract.failure(
                NativeErrorCodes.RingSessionConflict,
                "A live ring session is already active.",
                retryable = true,
                contractVersion = 2,
            )
        }
        val started = output.start(manager.settings())
        if (!started.anyStarted) {
            return NativeResultContract.failure(
                NativeErrorCodes.RingOutputUnavailable,
                "Neither ring sound nor vibration could be started.",
                retryable = false,
                contractVersion = 2,
            )
        }
        outputActive = true
        return manager.setTestState(expectedRevision, true)
    }

    fun buildControlNotification(): android.app.Notification? {
        val session = manager.activeSession() ?: return null
        AndroidNotificationChannelManager(appContext).ensureChannels()
        val capability = manager.currentSnapshot()["capability"] as Map<*, *>
        val allowFullScreen = manager.settings().strongReminderEnabled && capability["can_use_full_screen_intent"] == true
        return RingControlNotificationFactory(appContext).build(session, allowFullScreen)
    }

    private fun retryPendingFinalizations() {
        var failed = false
        val pending = manager.activeSession()?.items?.filter { it.finalizeOutcome?.endsWith("_pending") == true }.orEmpty()
        pending.forEach { item ->
            val sent = item.finalizeOutcome == "sent_pending"
            val prepared = syntheticPrepared(item)
            val result = attemptClient.finalize(
                prepared,
                if (sent) "sent" else "failed",
                if (sent) null else NativeErrorCodes.RingOutputUnavailable,
                failureRetryable = false,
                reminderId = item.reminderId,
            )
            if (result.ok) {
                val finalized = V2FinalizeDelivery.fromData(result.data)
                if (sent) {
                    manager.markFinalizeOutcome(item.deliveryId, "sent")
                    if (!finalized.idempotentReplay) AndroidNotificationRuntime.eventHub.emitDelivered(finalized.notification)
                } else {
                    manager.markFinalizeOutcome(item.deliveryId, "failed")
                    manager.remove(listOf(item.deliveryId))
                }
            } else {
                failed = true
            }
        }
        if (failed && !retryScheduled) {
            retryScheduled = true
            handler.postDelayed({
                retryScheduled = false
                retryPendingFinalizations()
                refreshNotification()
            }, FinalizeRetryMillis)
        }
        afterItemsRemoved()
    }

    private fun syntheticPrepared(item: RingItemRecord): V2PreparedDelivery = V2PreparedDelivery(
        notification = linkedMapOf(
            "notification_id" to item.notificationId,
            "delivery_id" to item.deliveryId,
            "delivery_attempt_id" to item.deliveryAttemptId,
            "reminder_id" to item.reminderId,
        ),
        tapPayload = emptyMap(),
        idempotentReplay = true,
    )

    private fun scheduleDeadline() {
        val session = manager.activeSession() ?: return
        if (session.phase != "audible") return
        val wallRemaining = session.audibleDeadlineAt?.let { ringUtcToMillis(it) - System.currentTimeMillis() }
            ?: MaxAudibleMillis
        val elapsedRemaining = session.elapsedDeadlineMillis?.minus(SystemClock.elapsedRealtime()) ?: wallRemaining
        val remaining = minOf(wallRemaining, elapsedRemaining).coerceAtLeast(0)
        handler.removeCallbacks(DeadlineAction)
        handler.postDelayed(DeadlineAction, remaining)
    }

    private val DeadlineAction = Runnable {
        output.stop()
        outputActive = false
        manager.enterQuiet()
        refreshNotification()
        service?.detachQuietNotification()
    }

    private fun afterItemsRemoved() {
        if (manager.activeSession() == null) {
            handler.removeCallbacks(DeadlineAction)
            output.stop()
            outputActive = false
            appContext.getSystemService(NotificationManager::class.java).cancel(RingControlNotificationFactory.NotificationId)
            service?.stopRingService(removeNotification = true)
        } else {
            refreshNotification()
        }
    }

    private fun refreshNotification() {
        val notification = buildControlNotification() ?: return
        runCatching {
            appContext.getSystemService(NotificationManager::class.java)
                .notify(RingControlNotificationFactory.NotificationId, notification)
        }
    }

    companion object {
        const val MaxAudibleMillis = 5 * 60 * 1000L
        private const val FinalizeRetryMillis = 30_000L
    }
}

internal fun ringSnoozeFeedback(result: NativeResultContract): String? {
    if (!result.ok) {
        return if (result.error?.details?.get("snooze_committed") == true) {
            if (result.error.details?.get("session_cleanup_pending") == true) {
                "稍后提醒已创建，但当前响铃尚未关闭，请重试"
            } else {
                "稍后提醒已创建且当前响铃已停止，系统调度正在恢复"
            }
        } else {
            "稍后提醒失败，请重试"
        }
    }
    @Suppress("UNCHECKED_CAST")
    val data = result.data as? Map<String, Any?> ?: return null
    val failedCount = (data["failed_count"] as? Number)?.toInt() ?: 0
    return if (failedCount > 0) "$failedCount 个提醒稍后失败，失败项已保留" else null
}

object RingRuntimeProvider {
    val eventHub = RingStateEventHub()
    @Volatile private var runtime: RingRuntime? = null

    fun get(context: Context): RingRuntime = runtime ?: synchronized(this) {
        runtime ?: create(context.applicationContext).also { runtime = it }
    }

    private fun create(context: Context): RingRuntime {
        val bridge = AndroidNativeBridgeFactory.create(context)
        val logger = ReminderOrchestrationLogger { operation, reminderId, message ->
            android.util.Log.d("ExcellentCalendarRing", "operation=$operation reminder_id=${reminderId ?: "null"} $message")
        }
        val manager = RingSessionManager(
            store = AndroidRingPersistentStore(context),
            capabilities = AndroidRingCapabilityProvider(context),
            elapsedRealtime = SystemClock::elapsedRealtime,
        )
        manager.setListener(eventHub)
        return RingRuntime(
            context,
            manager,
            AndroidRingOutputController(context),
            ReminderDeliveryAttemptClient(bridge, logger),
            RingNativeWorkflowClient(bridge),
            afterSnoozeCommitted = { reconcileAfterSnooze(context) },
        ).also { it.recoverIfNeeded() }
    }

    private fun reconcileAfterSnooze(context: Context): Boolean {
        return try {
            val reconciled = ReminderCoordinatorFactory.create(context).reconcile(
                ReconcileReminderScheduleContract(ReminderScheduleTrigger.Mutation, force = true),
            )
            if (!reconciled.ok) {
                ReminderWorkScheduler.enqueue(context, ReminderScheduleTrigger.Mutation)
                false
            } else {
                true
            }
        } catch (_: Throwable) {
            runCatching { ReminderWorkScheduler.enqueue(context, ReminderScheduleTrigger.Mutation) }
            false
        }
    }
}

object RingServiceStarter {
    fun startOrSchedule(context: Context): Boolean {
        val appContext = context.applicationContext
        val intent = Intent(appContext, ReminderRingService::class.java).setAction(ReminderRingService.ActionStart)
        return try {
            if (Build.VERSION.SDK_INT >= 31) {
                val alarm = appContext.getSystemService(AlarmManager::class.java)
                if (!alarm.canScheduleExactAlarms()) return false
                val pending = PendingIntent.getForegroundService(
                    appContext,
                    ServiceRequestCode,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                alarm.setExactAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, SystemClock.elapsedRealtime() + 100, pending)
            } else if (Build.VERSION.SDK_INT >= 26) {
                appContext.startForegroundService(intent)
            } else {
                appContext.startService(intent)
            }
            true
        } catch (_: RuntimeException) {
            false
        }
    }

    private const val ServiceRequestCode = 7303
}
