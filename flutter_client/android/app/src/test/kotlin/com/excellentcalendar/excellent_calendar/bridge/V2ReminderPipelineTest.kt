package com.excellentcalendar.excellent_calendar.bridge

import com.excellentcalendar.excellent_calendar.android.alarm.CancelResult
import com.excellentcalendar.excellent_calendar.android.alarm.DispatchAlarmScheduler
import com.excellentcalendar.excellent_calendar.android.alarm.ScheduleResult
import com.excellentcalendar.excellent_calendar.android.notification.AndroidNotificationIdentity
import com.excellentcalendar.excellent_calendar.android.notification.NotificationDisplayService
import com.excellentcalendar.excellent_calendar.android.notification.NotificationEventHub
import com.excellentcalendar.excellent_calendar.android.notification.NotificationPostResult
import com.excellentcalendar.excellent_calendar.android.notification.PreparedNotificationContent
import com.excellentcalendar.excellent_calendar.android.notification.ReminderNotificationContent
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReconcileReminderScheduleContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReminderScheduleTrigger
import com.excellentcalendar.excellent_calendar.bridge.contract.V2PreparedDelivery
import com.excellentcalendar.excellent_calendar.bridge.native.NativeReminderBridge
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderDeliveryAttemptClient
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderRecoveryRunner
import com.excellentcalendar.excellent_calendar.bridge.reminder.PendingRecoveryRequest
import com.excellentcalendar.excellent_calendar.bridge.reminder.RecoveryRequestStore
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderRecoveryCoordinator
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderScheduleMode
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderScheduleReconciliation
import com.excellentcalendar.excellent_calendar.bridge.reminder.V2ReminderDeliverer
import com.excellentcalendar.excellent_calendar.bridge.reminder.V2ReminderDeliveryService
import com.excellentcalendar.excellent_calendar.bridge.reminder.V2ReminderScheduleCoordinator
import com.excellentcalendar.excellent_calendar.bridge.runtime.DeviceTimezoneProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class V2ReminderPipelineTest {
    @Test
    fun anniversaryAggregatePostsOnePreparedNotificationAndFinalizesOneAttempt() {
        val bridge = AnniversaryAggregateDeliveryBridge()
        val display = RecordingDisplay()
        val service = V2ReminderDeliveryService(
            nativeBridge = bridge,
            notifications = display,
            eventHub = NotificationEventHub(),
            logger = { _, _, _ -> },
            timezoneProvider = DeviceTimezoneProvider { "Asia/Shanghai" },
        )

        val result = service.deliverAnniversaryCatchUp(AggregateBatchId, AggregateDeliveryId)

        assertTrue(result.ok)
        assertEquals(listOf(AggregateDeliveryId), display.deliveryIds)
        assertEquals(1, bridge.prepareRequests.size)
        assertEquals("anniversary_catch_up", bridge.prepareRequests.single()["kind"])
        assertEquals(AggregateDeliveryId, bridge.prepareRequests.single()["delivery_id"])
        assertFalse(bridge.prepareRequests.single().containsKey("covered_reminder_ids"))
        assertEquals(listOf(AggregateAttemptId), bridge.finalizedAttemptIds)
        assertEquals(listOf("Asia/Shanghai"), bridge.finalizeRequests.map { it["timezone"] })
    }

    @Test
    fun popupHeadAllowsApproximateDispatcherButRingHeadStillRequiresExactAlarm() {
        val popupAlarm = ModeRecordingAlarm()
        val popupOutcome = scheduleSingleHead("popup", popupAlarm)
        val popupResult = popupOutcome.result
        assertTrue(popupResult.ok)
        assertEquals(ReminderScheduleMode.Approximate, popupOutcome.scheduleMode)
        assertEquals(listOf(true), popupAlarm.allowApproximateValues)

        val ringAlarm = ModeRecordingAlarm()
        val ringOutcome = scheduleSingleHead("ring", ringAlarm)
        val ringResult = ringOutcome.result
        assertFalse(ringResult.ok)
        assertEquals(null, ringOutcome.scheduleMode)
        assertEquals(NativeErrorCodes.ExactAlarmPermissionDenied, ringResult.error?.code)
        assertEquals(listOf(false), ringAlarm.allowApproximateValues)
    }

    private fun scheduleSingleHead(method: String, alarm: DispatchAlarmScheduler): ReminderScheduleReconciliation {
        val bridge = SingleHeadBridge(method)
        return V2ReminderScheduleCoordinator(
            nativeBridge = bridge,
            alarmScheduler = alarm,
            deliveryService = object : V2ReminderDeliverer {
                override fun deliverReminder(reminderId: String, expectedRemindAt: String, recoveryBatchId: String?) =
                    NativeResultContract.success(emptyMap<String, Any?>(), contractVersion = 2)
                override fun deliverSummary(recoveryBatchId: String) =
                    NativeResultContract.success(emptyMap<String, Any?>(), contractVersion = 2)
            },
            recoveryCoordinator = object : ReminderRecoveryRunner {
                override fun recover(trigger: ReminderScheduleTrigger, canContinue: () -> Boolean) =
                    NativeResultContract.success(mapOf("recovery_performed" to false), contractVersion = 2)
            },
            continuationEnqueuer = { },
            logger = { _, _, _ -> },
            nowUtc = { "2026-08-24T00:00:00Z" },
            elapsedRealtime = { 0L },
        ).reconcileWithOutcome(
            ReconcileReminderScheduleContract(ReminderScheduleTrigger.Mutation, force = true),
            Long.MAX_VALUE,
        )
    }

    @Test
    fun deliveryRetryReusesAttemptAndStableDeliveryTag() {
        val bridge = DeliveryBridge()
        val display = RecordingDisplay()
        val service = V2ReminderDeliveryService(
            nativeBridge = bridge,
            notifications = display,
            eventHub = NotificationEventHub(),
            logger = { _, _, _ -> },
        )

        assertTrue(service.deliverReminder("reminder", "2026-08-04T01:00:00Z").ok)
        assertTrue(service.deliverReminder("reminder", "2026-08-04T01:00:00Z").ok)

        assertEquals(listOf("delivery", "delivery"), display.deliveryIds)
        assertEquals(listOf("attempt", "attempt"), bridge.finalizedAttemptIds)
        assertEquals(
            listOf("Asia/Shanghai", "Asia/Shanghai"),
            bridge.prepareRequests.map { it["timezone"] },
        )
        assertEquals("delivery:delivery", com.excellentcalendar.excellent_calendar.android.notification.AndroidNotificationDisplayService.preparedNotificationIdentity("delivery").tag)
    }

    @Test
    fun eventAndRingFinalizeReadTheCurrentTimezoneForEveryCall() {
        val bridge = DeliveryBridge()
        val timezoneProvider = SequenceTimezoneProvider("Asia/Shanghai", "America/New_York")
        val client = ReminderDeliveryAttemptClient(
            bridge,
            logger = { _, _, _ -> },
            timezoneProvider = timezoneProvider,
        )

        assertTrue(client.finalize(prepared("popup"), "sent").ok)
        assertTrue(client.finalize(prepared("ring"), "sent").ok)

        assertEquals(2, timezoneProvider.callCount)
        assertEquals(
            listOf("Asia/Shanghai", "America/New_York"),
            bridge.finalizeRequests.map { it["timezone"] },
        )
    }

    @Test
    fun nativeMissingOrInvalidTimezoneFailureIsNeverReportedAsFinalizeSuccess() {
        listOf(
            NativeErrorCodes.ContractValidationFailed,
            NativeErrorCodes.TimezoneIdInvalid,
        ).forEach { code ->
            val bridge = FinalizeTimezoneFailureBridge(code)
            val client = ReminderDeliveryAttemptClient(
                bridge,
                logger = { _, _, _ -> },
                timezoneProvider = DeviceTimezoneProvider { "Asia/Shanghai" },
            )

            val result = client.finalize(prepared("popup"), "sent")

            assertFalse(result.ok)
            assertEquals(code, result.error?.code)
            assertEquals("Asia/Shanghai", bridge.request["timezone"])
        }
    }

    @Test
    fun invalidDeviceTimezoneFailsBeforeFinalizeNativeCall() {
        val bridge = FinalizeTimezoneFailureBridge(NativeErrorCodes.TimezoneIdInvalid)
        val client = ReminderDeliveryAttemptClient(
            bridge,
            logger = { _, _, _ -> },
            timezoneProvider = DeviceTimezoneProvider { "+08:00" },
        )

        val result = client.finalize(prepared("popup"), "sent")

        assertFalse(result.ok)
        assertEquals(NativeErrorCodes.ContractValidationFailed, result.error?.code)
        assertTrue(bridge.request.isEmpty())
    }

    @Test
    fun adoptedAttemptFinalizeReturnsCompletedRecoveryBatch() {
        val bridge = AdoptedDeliveryBridge()
        val service = V2ReminderDeliveryService(
            nativeBridge = bridge,
            notifications = RecordingDisplay(),
            eventHub = NotificationEventHub(),
            logger = { _, _, _ -> },
        )

        val result = service.deliverReminder("reminder", "2026-08-04T01:00:00Z", "batch")

        assertTrue(result.ok)
        @Suppress("UNCHECKED_CAST")
        val data = result.data as Map<String, Any?>
        assertEquals(true, data["recovery_completed"])
        assertEquals(listOf("batch"), bridge.prepareRecoveryBatchIds)
    }

    @Test
    fun recoveryOwnedReminderAttemptCanPrepareAndFinalize() {
        val service = V2ReminderDeliveryService(
            nativeBridge = RecoveryOwnedDeliveryBridge(),
            notifications = RecordingDisplay(),
            eventHub = NotificationEventHub(),
            logger = { _, _, _ -> },
        )

        val result = service.deliverReminder("reminder", "2026-08-04T01:00:00Z", "batch")

        assertTrue(result.ok)
        @Suppress("UNCHECKED_CAST")
        val data = result.data as Map<String, Any?>
        assertEquals(true, data["recovery_completed"])
    }

    @Test
    fun scheduleConflictDoesNotOverwriteAndImmediatelyReconciles() {
        val bridge = ScheduleConflictBridge()
        val alarm = RecordingAlarm()
        val coordinator = V2ReminderScheduleCoordinator(
            nativeBridge = bridge,
            alarmScheduler = alarm,
            deliveryService = object : V2ReminderDeliverer {
                override fun deliverReminder(reminderId: String, expectedRemindAt: String, recoveryBatchId: String?) =
                    NativeResultContract.success(emptyMap<String, Any?>(), contractVersion = 2)
                override fun deliverSummary(recoveryBatchId: String) = NativeResultContract.success(emptyMap<String, Any?>(), contractVersion = 2)
            },
            recoveryCoordinator = object : ReminderRecoveryRunner {
                override fun recover(trigger: ReminderScheduleTrigger, canContinue: () -> Boolean) =
                    NativeResultContract.success(mapOf("recovery_performed" to false), contractVersion = 2)
            },
            continuationEnqueuer = { },
            logger = { _, _, _ -> },
            nowUtc = { "2026-08-04T00:00:00Z" },
            elapsedRealtime = { 0L },
        )

        val result = coordinator.reconcile(
            ReconcileReminderScheduleContract(ReminderScheduleTrigger.Mutation, force = true),
            Long.MAX_VALUE,
        )

        assertTrue(result.ok)
        assertEquals(listOf("2026-08-05T01:00:00Z", "2026-08-05T02:00:00Z"), alarm.scheduled)
        assertEquals(
            listOf("2026-08-05T01:00:00Z", "2026-08-05T02:00:00Z"),
            bridge.markRequests.map { it["expected_remind_at"] },
        )
    }

    @Test
    fun dispatcherAlarmDeliversMatchingAuthoritativePlanBeforeRecovery() {
        val plannedAt = "2026-08-25T05:38:00Z"
        val bridge = DispatcherAlarmBridge(plannedAt)
        val order = mutableListOf<String>()
        val coordinator = V2ReminderScheduleCoordinator(
            nativeBridge = bridge,
            alarmScheduler = RecordingAlarm(),
            deliveryService = object : V2ReminderDeliverer {
                override fun deliverReminder(
                    reminderId: String,
                    expectedRemindAt: String,
                    recoveryBatchId: String?,
                ): NativeResultContract {
                    order += "ordinary:$reminderId"
                    assertEquals("on-time-anniversary", reminderId)
                    assertEquals(plannedAt, expectedRemindAt)
                    assertEquals(null, recoveryBatchId)
                    bridge.ordinaryDelivered = true
                    return NativeResultContract.success(emptyMap<String, Any?>(), contractVersion = 2)
                }

                override fun deliverSummary(recoveryBatchId: String) =
                    NativeResultContract.success(emptyMap<String, Any?>(), contractVersion = 2)
            },
            recoveryCoordinator = object : ReminderRecoveryRunner {
                override fun recover(trigger: ReminderScheduleTrigger, canContinue: () -> Boolean): NativeResultContract {
                    order += "recovery:older"
                    assertTrue(bridge.ordinaryDelivered)
                    return NativeResultContract.success(
                        mapOf("recovery_performed" to true, "continuation_required" to false),
                        contractVersion = 2,
                    )
                }
            },
            continuationEnqueuer = { },
            logger = { _, _, _ -> },
            nowUtc = { "2026-08-25T05:38:02Z" },
            elapsedRealtime = { 0L },
        )

        val result = coordinator.reconcileDispatcherAlarm(plannedAt, Long.MAX_VALUE)

        assertTrue(result.ok)
        assertEquals(listOf("ordinary:on-time-anniversary", "recovery:older"), order)
        assertEquals(plannedAt, bridge.listRequests.first()["from_at"])
        assertEquals(plannedAt, bridge.listRequests.first()["to_at"])
        assertEquals(true, bridge.listRequests.first()["include_scheduled"])
    }

    @Test
    fun dispatcherAlarmRetryableOrdinaryFailureDoesNotFallThroughToRecovery() {
        val plannedAt = "2026-08-25T05:38:00Z"
        val bridge = DispatcherAlarmBridge(plannedAt)
        var recoveryCalls = 0
        var continuationCalls = 0
        val coordinator = V2ReminderScheduleCoordinator(
            nativeBridge = bridge,
            alarmScheduler = RecordingAlarm(),
            deliveryService = object : V2ReminderDeliverer {
                override fun deliverReminder(
                    reminderId: String,
                    expectedRemindAt: String,
                    recoveryBatchId: String?,
                ) = NativeResultContract.failure(
                    NativeErrorCodes.NotificationDeliveryFailed,
                    "notification post failed",
                    retryable = true,
                    contractVersion = 2,
                )

                override fun deliverSummary(recoveryBatchId: String) =
                    NativeResultContract.success(emptyMap<String, Any?>(), contractVersion = 2)
            },
            recoveryCoordinator = object : ReminderRecoveryRunner {
                override fun recover(trigger: ReminderScheduleTrigger, canContinue: () -> Boolean): NativeResultContract {
                    recoveryCalls += 1
                    return NativeResultContract.success(emptyMap<String, Any?>(), contractVersion = 2)
                }
            },
            continuationEnqueuer = { continuationCalls += 1 },
            logger = { _, _, _ -> },
            nowUtc = { "2026-08-25T05:38:02Z" },
            elapsedRealtime = { 0L },
        )

        val result = coordinator.reconcileDispatcherAlarm(plannedAt, Long.MAX_VALUE)

        assertTrue(result.ok)
        assertEquals(0, recoveryCalls)
        assertEquals(1, continuationCalls)
        @Suppress("UNCHECKED_CAST")
        val data = result.data as Map<String, Any?>
        assertEquals(listOf("on-time-anniversary"), data["failed_reminder_ids"])
    }

    @Test
    fun recoveryFailureDoesNotBlockDueDeliveryOrNextAlarmRearm() {
        val bridge = RecoveryFailureScheduleBridge()
        val alarm = RecordingAlarm()
        val deliveredReminderIds = mutableListOf<String>()
        var continuationCount = 0
        val coordinator = V2ReminderScheduleCoordinator(
            nativeBridge = bridge,
            alarmScheduler = alarm,
            deliveryService = object : V2ReminderDeliverer {
                override fun deliverReminder(reminderId: String, expectedRemindAt: String, recoveryBatchId: String?): NativeResultContract {
                    deliveredReminderIds += reminderId
                    return NativeResultContract.success(emptyMap<String, Any?>(), contractVersion = 2)
                }

                override fun deliverSummary(recoveryBatchId: String) =
                    NativeResultContract.success(emptyMap<String, Any?>(), contractVersion = 2)
            },
            recoveryCoordinator = object : ReminderRecoveryRunner {
                override fun recover(trigger: ReminderScheduleTrigger, canContinue: () -> Boolean) =
                    NativeResultContract.failure(
                        NativeErrorCodes.RecoveryBatchConflict,
                        "stale recovery failed",
                        retryable = true,
                        contractVersion = 2,
                    )
            },
            continuationEnqueuer = { continuationCount += 1 },
            logger = { _, _, _ -> },
            nowUtc = { "2026-08-04T00:30:00Z" },
            elapsedRealtime = { 0L },
        )

        val result = coordinator.reconcile(
            ReconcileReminderScheduleContract(ReminderScheduleTrigger.AlarmFired, force = true),
            Long.MAX_VALUE,
        )

        assertFalse(result.ok)
        assertEquals(NativeErrorCodes.RecoveryBatchConflict, result.error?.code)
        assertEquals(1, continuationCount)
        assertEquals(listOf("due-reminder"), deliveredReminderIds)
        assertEquals(listOf("2026-08-04T01:00:00Z"), alarm.scheduled)
        assertEquals(listOf("2026-08-04T01:00:00Z"), bridge.markRequests.map { it["expected_remind_at"] })
    }

    @Test
    fun oneDueDeliveryFailureDoesNotBlockLaterReminderOrNextAlarmRearm() {
        val bridge = DueFailureIsolationScheduleBridge()
        val alarm = RecordingAlarm()
        val deliveredReminderIds = mutableListOf<String>()
        var continuationCount = 0
        val coordinator = V2ReminderScheduleCoordinator(
            nativeBridge = bridge,
            alarmScheduler = alarm,
            deliveryService = object : V2ReminderDeliverer {
                override fun deliverReminder(reminderId: String, expectedRemindAt: String, recoveryBatchId: String?): NativeResultContract {
                    deliveredReminderIds += reminderId
                    return if (reminderId == "broken-ring") {
                        NativeResultContract.failure(
                            NativeErrorCodes.RingSettingsStorageFailed,
                            "ring session persistence failed",
                            retryable = true,
                            contractVersion = 2,
                        )
                    } else {
                        NativeResultContract.success(emptyMap<String, Any?>(), contractVersion = 2)
                    }
                }

                override fun deliverSummary(recoveryBatchId: String) =
                    NativeResultContract.success(emptyMap<String, Any?>(), contractVersion = 2)
            },
            recoveryCoordinator = object : ReminderRecoveryRunner {
                override fun recover(trigger: ReminderScheduleTrigger, canContinue: () -> Boolean) =
                    NativeResultContract.success(mapOf("recovery_performed" to false), contractVersion = 2)
            },
            continuationEnqueuer = { continuationCount += 1 },
            logger = { _, _, _ -> },
            nowUtc = { "2026-08-04T00:30:00Z" },
            elapsedRealtime = { 0L },
        )

        val result = coordinator.reconcile(
            ReconcileReminderScheduleContract(ReminderScheduleTrigger.AlarmFired, force = true),
            Long.MAX_VALUE,
        )

        assertTrue(result.ok)
        @Suppress("UNCHECKED_CAST")
        val data = result.data as Map<String, Any?>
        assertEquals(1, data["processed_due_count"])
        assertEquals(1, data["failed_count"])
        assertEquals(listOf("broken-ring"), data["failed_reminder_ids"])
        assertEquals(true, data["continuation_enqueued"])
        assertEquals(listOf("broken-ring", "healthy-ring"), deliveredReminderIds)
        assertEquals(1, continuationCount)
        assertEquals(listOf("2026-08-04T01:00:00Z"), alarm.scheduled)
        assertEquals(listOf("2026-08-04T01:00:00Z"), bridge.markRequests.map { it["expected_remind_at"] })
    }

    @Test
    fun recoveryCancelsAbandonedThenPostsSummaryBeforeOrderedDetailsAndClearsCompletedRequest() {
        val bridge = RecoveryBridge()
        val display = RecordingDisplay()
        val order = mutableListOf<String>()
        val store = RecordingRecoveryStore()
        val recovery = ReminderRecoveryCoordinator(
            nativeBridge = bridge,
            deliveryService = object : V2ReminderDeliverer {
                override fun deliverSummary(recoveryBatchId: String): NativeResultContract {
                    order += "summary"
                    return NativeResultContract.success(emptyMap<String, Any?>(), contractVersion = 2)
                }
                override fun deliverReminder(reminderId: String, expectedRemindAt: String, recoveryBatchId: String?): NativeResultContract {
                    order += reminderId
                    return NativeResultContract.success(emptyMap<String, Any?>(), contractVersion = 2)
                }
            },
            notifications = display,
            requestStore = store,
            logger = { _, _, _ -> },
            timezoneProvider = SequenceTimezoneProvider("Asia/Shanghai", "America/New_York"),
        )

        val result = recovery.recover(ReminderScheduleTrigger.AlarmFired)

        assertTrue(result.ok)
        assertEquals(listOf("old-delivery"), display.cancelledDeliveryIds)
        assertEquals(listOf("summary", "detail-old", "detail-new"), order)
        assertEquals(listOf("fixed-request"), store.cleared)
        assertEquals(listOf("fixed-request", "fixed-request"), bridge.requestIds)
        assertEquals(listOf("Asia/Shanghai", "America/New_York"), bridge.timezones)
    }

    @Test
    fun recoveryResumeSkipsTerminalDetailsAndContinuesAfterConsumedSummary() {
        val bridge = ResumedRecoveryBridge()
        val order = mutableListOf<String>()
        val store = RecordingRecoveryStore()
        val recovery = ReminderRecoveryCoordinator(
            nativeBridge = bridge,
            deliveryService = object : V2ReminderDeliverer {
                override fun deliverSummary(recoveryBatchId: String): NativeResultContract {
                    order += "summary"
                    return NativeResultContract.failure(
                        NativeErrorCodes.ReminderAlreadyConsumed,
                        "summary was already delivered",
                        contractVersion = 2,
                    )
                }

                override fun deliverReminder(reminderId: String, expectedRemindAt: String, recoveryBatchId: String?): NativeResultContract {
                    order += reminderId
                    return NativeResultContract.success(emptyMap<String, Any?>(), contractVersion = 2)
                }
            },
            notifications = RecordingDisplay(),
            requestStore = store,
            logger = { _, _, _ -> },
        )

        val result = recovery.recover(ReminderScheduleTrigger.AlarmFired)

        assertTrue(result.ok)
        assertEquals(listOf("summary", "detail-new"), order)
        assertEquals(listOf("fixed-request"), store.cleared)
        assertEquals(listOf("fixed-request", "fixed-request"), bridge.requestIds)
    }

    private class RecordingDisplay : NotificationDisplayService {
        val deliveryIds = mutableListOf<String>()
        val cancelledDeliveryIds = mutableListOf<String>()
        override fun post(content: ReminderNotificationContent, sentAt: String) = error("v1 post must not be used")
        override fun cancel(reminderId: String) = Unit
        override fun postPrepared(content: PreparedNotificationContent): NotificationPostResult {
            deliveryIds += content.deliveryId
            return NotificationPostResult.Success(AndroidNotificationIdentity("delivery:${content.deliveryId}", 1))
        }
        override fun cancelDelivery(deliveryId: String) {
            cancelledDeliveryIds += deliveryId
        }
    }

    private class RecordingAlarm : DispatchAlarmScheduler {
        val scheduled = mutableListOf<String>()
        override fun schedule(plannedAt: String): ScheduleResult {
            scheduled += plannedAt
            return ScheduleResult.Success
        }
        override fun cancel() = CancelResult.Success
        override fun canScheduleExactAlarms() = true
    }

    private class DeliveryBridge : ReminderBridgeAdapter() {
        var finalizeCount = 0
        val prepareRequests = mutableListOf<Map<String, Any?>>()
        val finalizedAttemptIds = mutableListOf<String>()
        val finalizeRequests = mutableListOf<Map<String, Any?>>()

        override fun prepareReminderDelivery(requestJson: String): String {
            prepareRequests += NativeContractJsonCodec.decodeObject(requestJson)
            return success(linkedMapOf(
                "notification" to notification("prepared"),
                "tap_payload" to linkedMapOf(
                    "notification_id" to "notification",
                    "delivery_id" to "delivery",
                    "delivery_attempt_id" to "attempt",
                    "kind" to "reminder",
                    "reminder_id" to "reminder",
                    "recovery_batch_id" to null,
                    "target_type" to "event",
                    "target_id" to "event",
                    "occurrence_key" to null,
                    "route" to "/event/detail",
                ),
                "idempotent_replay" to (finalizeCount > 0),
            ))
        }

        override fun finalizeReminderDelivery(requestJson: String): String {
            val request = NativeContractJsonCodec.decodeObject(requestJson)
            finalizeRequests += request
            finalizedAttemptIds += request["delivery_attempt_id"] as String
            finalizeCount += 1
            return success(
                linkedMapOf(
                    "notification" to notification("sent"),
                    "reminder" to reminder("2026-08-04T01:00:00Z") + mapOf(
                        "status" to "sent",
                        "is_enabled" to false,
                        "last_triggered_at" to "2026-08-04T00:00:01Z",
                    ),
                    "successor" to null,
                    "covered_reminders" to emptyList<Any?>(),
                    "successors" to emptyList<Any?>(),
                    "recovery_batch" to null,
                    "idempotent_replay" to (finalizeCount > 1),
                ),
            )
        }
    }

    private class AdoptedDeliveryBridge : ReminderBridgeAdapter() {
        val prepareRecoveryBatchIds = mutableListOf<String?>()

        override fun prepareReminderDelivery(requestJson: String): String {
            val request = NativeContractJsonCodec.decodeObject(requestJson)
            prepareRecoveryBatchIds += request["recovery_batch_id"] as String?
            return success(
                linkedMapOf(
                    "notification" to notification("prepared") +
                        ("resolved_by_recovery_batch_id" to "batch"),
                    "tap_payload" to linkedMapOf(
                        "notification_id" to "notification",
                        "delivery_id" to "delivery",
                        "delivery_attempt_id" to "attempt",
                        "kind" to "reminder",
                        "reminder_id" to "reminder",
                        "recovery_batch_id" to null,
                        "target_type" to "event",
                        "target_id" to "event",
                        "occurrence_key" to null,
                        "route" to "/event/detail",
                    ),
                    "idempotent_replay" to true,
                ),
            )
        }

        override fun finalizeReminderDelivery(requestJson: String): String = success(
            linkedMapOf(
                "notification" to notification("sent") +
                    ("resolved_by_recovery_batch_id" to "batch"),
                "reminder" to reminder("2026-08-04T01:00:00Z") + mapOf(
                    "status" to "sent",
                    "is_enabled" to false,
                    "last_triggered_at" to "2026-08-04T00:00:01Z",
                ),
                "successor" to null,
                "covered_reminders" to emptyList<Any?>(),
                "successors" to emptyList<Any?>(),
                "recovery_batch" to linkedMapOf(
                    "recovery_batch_id" to "batch",
                    "recovery_request_id" to "request",
                    "trigger_source" to "alarm_reconcile",
                    "started_at" to "2026-08-04T00:00:00Z",
                    "window_start_at" to "2026-08-01T00:00:00Z",
                    "detail_reminder_ids" to listOf("reminder"),
                    "summary_reminder_ids" to emptyList<String>(),
                    "older_skipped_occurrence_count" to 0,
                    "older_skipped_reminder_count" to 0,
                    "window_overflow_count" to 0,
                    "summary_delivery_id" to null,
                    "anniversary_catch_up_groups" to emptyList<Any?>(),
                    "status" to "completed",
                    "completed_at" to "2026-08-04T00:00:01Z",
                ),
                "idempotent_replay" to false,
            ),
        )
    }

    private class RecoveryOwnedDeliveryBridge : ReminderBridgeAdapter() {
        override fun prepareReminderDelivery(requestJson: String): String = success(
            linkedMapOf(
                "notification" to notification("prepared") +
                    ("recovery_batch_id" to "batch"),
                "tap_payload" to linkedMapOf(
                    "notification_id" to "notification",
                    "delivery_id" to "delivery",
                    "delivery_attempt_id" to "attempt",
                    "kind" to "reminder",
                    "reminder_id" to "reminder",
                    "recovery_batch_id" to "batch",
                    "target_type" to "event",
                    "target_id" to "event",
                    "occurrence_key" to null,
                    "route" to "/event/detail",
                ),
                "idempotent_replay" to true,
            ),
        )

        override fun finalizeReminderDelivery(requestJson: String): String = success(
            linkedMapOf(
                "notification" to notification("sent") +
                    ("recovery_batch_id" to "batch"),
                "reminder" to reminder("2026-08-04T01:00:00Z") + mapOf(
                    "status" to "sent",
                    "is_enabled" to false,
                    "last_triggered_at" to "2026-08-04T00:00:01Z",
                ),
                "successor" to null,
                "covered_reminders" to emptyList<Any?>(),
                "successors" to emptyList<Any?>(),
                "recovery_batch" to linkedMapOf(
                    "recovery_batch_id" to "batch",
                    "recovery_request_id" to "request",
                    "trigger_source" to "alarm_reconcile",
                    "started_at" to "2026-08-04T00:00:00Z",
                    "window_start_at" to "2026-08-01T00:00:00Z",
                    "detail_reminder_ids" to listOf("reminder"),
                    "summary_reminder_ids" to emptyList<String>(),
                    "older_skipped_occurrence_count" to 0,
                    "older_skipped_reminder_count" to 0,
                    "window_overflow_count" to 0,
                    "summary_delivery_id" to null,
                    "anniversary_catch_up_groups" to emptyList<Any?>(),
                    "status" to "completed",
                    "completed_at" to "2026-08-04T00:00:01Z",
                ),
                "idempotent_replay" to false,
            ),
        )
    }

    private class ScheduleConflictBridge : ReminderBridgeAdapter() {
        var headCalls = 0
        val markRequests = mutableListOf<Map<String, Any?>>()

        override fun listSchedulableReminders(requestJson: String): String {
            val request = NativeContractJsonCodec.decodeObject(requestJson)
            if (request["to_at"] != null) return success(batch(emptyList()))
            headCalls += 1
            val remindAt = if (headCalls == 1) "2026-08-05T01:00:00Z" else "2026-08-05T02:00:00Z"
            return success(batch(listOf(reminder(remindAt))))
        }

        override fun markReminderScheduled(requestJson: String): String {
            val request = NativeContractJsonCodec.decodeObject(requestJson)
            markRequests += request
            return if (markRequests.size == 1) failure(NativeErrorCodes.ReminderScheduleConflict)
            else success(mapOf("reminder_id" to "reminder"))
        }
    }

    private class RecoveryFailureScheduleBridge : ReminderBridgeAdapter() {
        val markRequests = mutableListOf<Map<String, Any?>>()

        override fun listSchedulableReminders(requestJson: String): String {
            val request = NativeContractJsonCodec.decodeObject(requestJson)
            val reminders = if (request["to_at"] != null) {
                listOf(reminder("2026-08-04T00:00:00Z", "due-reminder"))
            } else {
                listOf(reminder("2026-08-04T01:00:00Z", "future-reminder"))
            }
            return success(batch(reminders))
        }

        override fun markReminderScheduled(requestJson: String): String {
            markRequests += NativeContractJsonCodec.decodeObject(requestJson)
            return success(mapOf("reminder_id" to "future-reminder"))
        }
    }

    private class DispatcherAlarmBridge(
        private val plannedAt: String,
    ) : ReminderBridgeAdapter() {
        val listRequests = mutableListOf<Map<String, Any?>>()
        var ordinaryDelivered = false

        override fun listSchedulableReminders(requestJson: String): String {
            val request = NativeContractJsonCodec.decodeObject(requestJson)
            listRequests += request
            val matchesFrozenAlarm =
                request["from_at"] == plannedAt && request["to_at"] == plannedAt
            val reminders = if (matchesFrozenAlarm && !ordinaryDelivered) {
                listOf(reminder(plannedAt, "on-time-anniversary"))
            } else {
                emptyList()
            }
            return success(batch(reminders))
        }
    }

    private class ModeRecordingAlarm : DispatchAlarmScheduler {
        val allowApproximateValues = mutableListOf<Boolean>()
        override fun schedule(plannedAt: String) = ScheduleResult.Failure(
            NativeErrorCodes.ExactAlarmPermissionDenied,
            "exact alarm denied",
            retryable = true,
        )
        override fun schedule(plannedAt: String, allowApproximate: Boolean): ScheduleResult {
            allowApproximateValues += allowApproximate
            return if (allowApproximate) {
                ScheduleResult.ApproximateSuccess
            } else {
                schedule(plannedAt)
            }
        }
        override fun cancel() = CancelResult.Success
        override fun canScheduleExactAlarms() = false
    }

    private class SingleHeadBridge(private val method: String) : ReminderBridgeAdapter() {
        override fun listSchedulableReminders(requestJson: String): String {
            val request = NativeContractJsonCodec.decodeObject(requestJson)
            val items = if (request["to_at"] != null) {
                emptyList()
            } else {
                listOf(reminder("2026-08-24T01:00:00Z") + ("methods" to listOf(method)))
            }
            return success(batch(items))
        }

        override fun markReminderScheduled(requestJson: String): String =
            success(mapOf("reminder_id" to "reminder"))
    }

    private class AnniversaryAggregateDeliveryBridge : ReminderBridgeAdapter() {
        val prepareRequests = mutableListOf<Map<String, Any?>>()
        val finalizedAttemptIds = mutableListOf<String>()
        val finalizeRequests = mutableListOf<Map<String, Any?>>()

        override fun prepareReminderDelivery(requestJson: String): String {
            prepareRequests += NativeContractJsonCodec.decodeObject(requestJson)
            return success(
                linkedMapOf(
                    "notification" to aggregateNotification("prepared"),
                    "tap_payload" to linkedMapOf(
                        "notification_id" to AggregateNotificationId,
                        "delivery_id" to AggregateDeliveryId,
                        "delivery_attempt_id" to AggregateAttemptId,
                        "kind" to "anniversary_catch_up",
                        "reminder_id" to null,
                        "recovery_batch_id" to AggregateBatchId,
                        "target_type" to "anniversary",
                        "target_id" to AggregateAnniversaryId,
                        "occurrence_key" to AggregateOccurrenceKey,
                        "route" to "anniversary.detail",
                    ),
                    "idempotent_replay" to false,
                ),
            )
        }

        override fun finalizeReminderDelivery(requestJson: String): String {
            val request = NativeContractJsonCodec.decodeObject(requestJson)
            finalizeRequests += request
            finalizedAttemptIds += request["delivery_attempt_id"] as String
            return success(
                linkedMapOf(
                    "notification" to aggregateNotification("sent"),
                    "reminder" to null,
                    "successor" to null,
                    "covered_reminders" to AggregateReminderIds.map(::anniversaryReminder),
                    "successors" to emptyList<Any?>(),
                    "recovery_batch" to aggregateRecoveryBatch(),
                    "idempotent_replay" to false,
                ),
            )
        }

        private fun aggregateNotification(status: String): Map<String, Any?> = linkedMapOf(
            "notification_id" to AggregateNotificationId,
            "delivery_id" to AggregateDeliveryId,
            "delivery_attempt_id" to AggregateAttemptId,
            "kind" to "anniversary_catch_up",
            "reminder_id" to null,
            "recovery_batch_id" to AggregateBatchId,
            "resolved_by_recovery_batch_id" to null,
            "target_type" to "anniversary",
            "target_id" to AggregateAnniversaryId,
            "occurrence_key" to AggregateOccurrenceKey,
            "covered_reminder_ids" to AggregateReminderIds,
            "method" to "popup",
            "title" to "Project anniversary",
            "body" to "Today is the anniversary",
            "planned_at" to "2026-08-24T01:00:00Z",
            "status" to status,
            "failure_class" to null,
            "error_code" to null,
            "abandon_reason" to null,
            "prepared_at" to "2026-08-24T01:00:01Z",
            "finalized_at" to if (status == "sent") "2026-08-24T01:00:02Z" else null,
            "sent_at" to if (status == "sent") "2026-08-24T01:00:02Z" else null,
            "created_at" to "2026-08-24T01:00:01Z",
            "updated_at" to if (status == "sent") "2026-08-24T01:00:02Z" else "2026-08-24T01:00:01Z",
        )

        private fun anniversaryReminder(reminderId: String): Map<String, Any?> = linkedMapOf(
            "reminder_id" to reminderId,
            "target_type" to "anniversary",
            "target_id" to AggregateAnniversaryId,
            "recurrence_revision" to null,
            "occurrence_key" to AggregateOccurrenceKey,
            "occurrence_start_at" to null,
            "template_key" to if (reminderId == AggregateReminderIds[0]) AggregateTemplateOne else AggregateTemplateTwo,
            "occurrence_date" to "2026-08-24",
            "advance_days" to 0,
            "local_time" to if (reminderId == AggregateReminderIds[0]) "09:00" else "12:00",
            "timezone_mode" to "follow_device",
            "fulfillment_delivery_id" to AggregateDeliveryId,
            "remind_at" to "2026-08-24T01:00:00Z",
            "advance_minutes" to null,
            "methods" to listOf("popup"),
            "message" to null,
            "is_enabled" to false,
            "status" to "sent",
            "scheduled_at" to null,
            "last_triggered_at" to "2026-08-24T01:00:02Z",
            "failure_reason" to null,
            "last_cancellation_reason" to null,
            "last_cancelled_at" to null,
            "expiration_reason" to null,
            "expired_at" to null,
            "reactivated_at" to null,
            "reactivation_count" to 0,
            "created_at" to "2026-08-23T01:00:00Z",
            "updated_at" to "2026-08-24T01:00:02Z",
            "deleted_at" to null,
        )

        private fun aggregateRecoveryBatch(): Map<String, Any?> = linkedMapOf(
            "recovery_batch_id" to AggregateBatchId,
            "recovery_request_id" to AggregateRequestId,
            "trigger_source" to "alarm_reconcile",
            "started_at" to "2026-08-24T01:00:00Z",
            "window_start_at" to "2026-08-21T01:00:00Z",
            "detail_reminder_ids" to emptyList<String>(),
            "summary_reminder_ids" to emptyList<String>(),
            "older_skipped_occurrence_count" to 0,
            "older_skipped_reminder_count" to 0,
            "window_overflow_count" to 0,
            "summary_delivery_id" to null,
            "anniversary_catch_up_groups" to listOf(
                linkedMapOf(
                    "anniversary_id" to AggregateAnniversaryId,
                    "occurrence_key" to AggregateOccurrenceKey,
                    "occurrence_date" to "2026-08-24",
                    "covered_reminder_ids" to AggregateReminderIds,
                    "delivery_id" to AggregateDeliveryId,
                    "status" to "completed",
                    "completed_at" to "2026-08-24T01:00:02Z",
                ),
            ),
            "status" to "completed",
            "completed_at" to "2026-08-24T01:00:02Z",
        )
    }

    private class DueFailureIsolationScheduleBridge : ReminderBridgeAdapter() {
        val markRequests = mutableListOf<Map<String, Any?>>()

        override fun listSchedulableReminders(requestJson: String): String {
            val request = NativeContractJsonCodec.decodeObject(requestJson)
            val reminders = if (request["to_at"] != null) {
                listOf(
                    reminder("2026-08-04T00:00:00Z", "broken-ring") + mapOf("methods" to listOf("ring")),
                    reminder("2026-08-04T00:05:00Z", "healthy-ring") + mapOf("methods" to listOf("ring")),
                )
            } else {
                listOf(reminder("2026-08-04T01:00:00Z", "future-reminder"))
            }
            return success(batch(reminders))
        }

        override fun markReminderScheduled(requestJson: String): String {
            markRequests += NativeContractJsonCodec.decodeObject(requestJson)
            return success(mapOf("reminder_id" to "future-reminder"))
        }
    }

    private class RecoveryBridge : ReminderBridgeAdapter() {
        var calls = 0
        val requestIds = mutableListOf<String>()
        val timezones = mutableListOf<String>()
        override fun planReminderRecovery(requestJson: String): String {
            val request = NativeContractJsonCodec.decodeObject(requestJson)
            requestIds += request["recovery_request_id"] as String
            timezones += request["timezone"] as String
            calls += 1
            val status = if (calls == 1) "in_progress" else "completed"
            return success(
                linkedMapOf(
                    "batch" to recoveryBatch(status),
                    "detail_reminders" to listOf(
                        reminder("2026-08-02T01:00:00Z", "detail-old"),
                        reminder("2026-08-03T01:00:00Z", "detail-new"),
                    ),
                    "anniversary_catch_up_groups" to emptyList<Any?>(),
                    "prepared_attempt_resolutions" to listOf(
                        linkedMapOf(
                            "delivery_attempt_id" to "old-attempt",
                            "delivery_id" to "old-delivery",
                            "reminder_id" to "old-reminder",
                            "resolution" to "abandoned_to_summary",
                            "replacement_delivery_id" to "summary-delivery",
                        ),
                    ),
                    "idempotent_replay" to (calls > 1),
                ),
            )
        }

        private fun recoveryBatch(status: String): Map<String, Any?> = linkedMapOf(
            "recovery_batch_id" to "batch",
            "recovery_request_id" to "fixed-request",
            "trigger_source" to "alarm_reconcile",
            "started_at" to "2026-08-04T00:00:00Z",
            "window_start_at" to "2026-08-01T00:00:00Z",
            "detail_reminder_ids" to listOf("detail-old", "detail-new"),
            "summary_reminder_ids" to listOf("summary-reminder"),
            "older_skipped_occurrence_count" to 0,
            "older_skipped_reminder_count" to 0,
            "window_overflow_count" to 1,
            "summary_delivery_id" to "summary-delivery",
            "anniversary_catch_up_groups" to emptyList<Any?>(),
            "status" to status,
            "completed_at" to if (status == "completed") "2026-08-04T00:00:02Z" else null,
        )
    }

    private class RecordingRecoveryStore : RecoveryRequestStore {
        val cleared = mutableListOf<String>()
        override fun getOrCreate(triggerSource: String) = PendingRecoveryRequest("fixed-request", triggerSource)
        override fun clearCompleted(requestId: String) {
            cleared += requestId
        }
    }

    private class ResumedRecoveryBridge : ReminderBridgeAdapter() {
        var calls = 0
        val requestIds = mutableListOf<String>()

        override fun planReminderRecovery(requestJson: String): String {
            val request = NativeContractJsonCodec.decodeObject(requestJson)
            requestIds += request["recovery_request_id"] as String
            calls += 1
            val completed = calls > 1
            return success(
                linkedMapOf(
                    "batch" to recoveryBatch(if (completed) "completed" else "in_progress"),
                    "detail_reminders" to listOf(
                        reminder("2026-08-02T01:00:00Z", "detail-old") + mapOf(
                            "status" to "sent",
                            "is_enabled" to false,
                            "last_triggered_at" to "2026-08-04T00:00:01Z",
                        ),
                        reminder("2026-08-03T01:00:00Z", "detail-new") + if (completed) {
                            mapOf(
                                "status" to "sent",
                                "is_enabled" to false,
                                "last_triggered_at" to "2026-08-04T00:00:02Z",
                            )
                        } else {
                            emptyMap()
                        },
                    ),
                    "anniversary_catch_up_groups" to emptyList<Any?>(),
                    "prepared_attempt_resolutions" to emptyList<Any?>(),
                    "idempotent_replay" to completed,
                ),
            )
        }

        private fun recoveryBatch(status: String): Map<String, Any?> = linkedMapOf(
            "recovery_batch_id" to "batch",
            "recovery_request_id" to "fixed-request",
            "trigger_source" to "alarm_reconcile",
            "started_at" to "2026-08-04T00:00:00Z",
            "window_start_at" to "2026-08-01T00:00:00Z",
            "detail_reminder_ids" to listOf("detail-old", "detail-new"),
            "summary_reminder_ids" to listOf("summary-reminder"),
            "older_skipped_occurrence_count" to 0,
            "older_skipped_reminder_count" to 0,
            "window_overflow_count" to 1,
            "summary_delivery_id" to "summary-delivery",
            "anniversary_catch_up_groups" to emptyList<Any?>(),
            "status" to status,
            "completed_at" to if (status == "completed") "2026-08-04T00:00:02Z" else null,
        )
    }

    private fun prepared(method: String): V2PreparedDelivery = V2PreparedDelivery(
        notification = ReminderBridgeAdapter.notification("prepared") + mapOf("method" to method),
        tapPayload = emptyMap(),
        idempotentReplay = false,
    )

    private class SequenceTimezoneProvider(vararg timezones: String) : DeviceTimezoneProvider {
        private val values = timezones.toList()
        var callCount = 0
            private set

        override fun currentTimezone(): String = values[callCount++]
    }

    private class FinalizeTimezoneFailureBridge(
        private val code: String,
    ) : ReminderBridgeAdapter() {
        var request: Map<String, Any?> = emptyMap()

        override fun finalizeReminderDelivery(requestJson: String): String {
            request = NativeContractJsonCodec.decodeObject(requestJson)
            return NativeContractJsonCodec.encodeObject(
                NativeResultContract.failure(
                    code,
                    "timezone rejected",
                    retryable = false,
                    contractVersion = 2,
                ).toMap(),
            )
        }
    }

    private abstract class ReminderBridgeAdapter : NativeReminderBridge {
        override fun createReminder(requestJson: String): String = error("unused")
        override fun updateReminder(requestJson: String): String = error("unused")
        override fun cancelReminder(requestJson: String): String = error("unused")
        override fun listReminders(requestJson: String): String = error("unused")
        override fun getReminder(requestJson: String): String = error("unused")
        override fun listSchedulableReminders(requestJson: String): String = error("unused")
        override fun markReminderScheduled(requestJson: String): String = error("unused")
        override fun markReminderSent(requestJson: String): String = error("unused")
        override fun markReminderFailed(requestJson: String): String = error("unused")
        override fun enableReminder(requestJson: String): String = error("unused")
        override fun disableReminder(requestJson: String): String = error("unused")

        fun success(data: Any?): String = NativeContractJsonCodec.encodeObject(
            NativeResultContract.success(data, contractVersion = 2).toMap(),
        )

        fun failure(code: String): String = NativeContractJsonCodec.encodeObject(
            NativeResultContract.failure(code, "conflict", retryable = true, contractVersion = 2).toMap(),
        )

        fun batch(items: List<Map<String, Any?>>): Map<String, Any?> = linkedMapOf(
            "items" to items,
            "selected_count" to items.size,
            "has_more" to false,
            "next_cursor" to null,
            "unsupported_reminder_ids" to emptyList<String>(),
        )

        fun reminder(remindAt: String, reminderId: String = "reminder"): Map<String, Any?> = linkedMapOf(
            "reminder_id" to reminderId,
            "target_type" to "event",
            "target_id" to "event",
            "recurrence_revision" to null,
            "occurrence_key" to null,
            "occurrence_start_at" to null,
            "template_key" to null,
            "occurrence_date" to null,
            "advance_days" to null,
            "local_time" to null,
            "timezone_mode" to null,
            "fulfillment_delivery_id" to null,
            "remind_at" to remindAt,
            "advance_minutes" to null,
            "methods" to listOf("popup"),
            "message" to null,
            "is_enabled" to true,
            "status" to "pending",
            "scheduled_at" to null,
            "last_triggered_at" to null,
            "failure_reason" to null,
            "last_cancellation_reason" to null,
            "last_cancelled_at" to null,
            "expiration_reason" to null,
            "expired_at" to null,
            "reactivated_at" to null,
            "reactivation_count" to 0,
            "created_at" to "2026-08-04T00:00:00Z",
            "updated_at" to "2026-08-04T00:00:00Z",
            "deleted_at" to null,
        )

        fun notification(status: String): Map<String, Any?> = Companion.notification(status)

        companion object {
            fun notification(status: String): Map<String, Any?> = linkedMapOf(
                "notification_id" to "notification",
                "delivery_id" to "delivery",
                "delivery_attempt_id" to "attempt",
                "kind" to "reminder",
                "reminder_id" to "reminder",
                "recovery_batch_id" to null,
                "resolved_by_recovery_batch_id" to null,
                "target_type" to "event",
                "target_id" to "event",
                "occurrence_key" to null,
                "covered_reminder_ids" to emptyList<String>(),
                "method" to "popup",
                "title" to "Title",
                "body" to "Body",
                "planned_at" to "2026-08-04T01:00:00Z",
                "status" to status,
                "failure_class" to null,
                "error_code" to null,
                "abandon_reason" to null,
                "prepared_at" to "2026-08-04T00:00:00Z",
                "finalized_at" to if (status == "sent") "2026-08-04T00:00:01Z" else null,
                "sent_at" to if (status == "sent") "2026-08-04T00:00:01Z" else null,
                "created_at" to "2026-08-04T00:00:00Z",
                "updated_at" to "2026-08-04T00:00:01Z",
            )
        }
    }

    companion object {
        private const val AggregateBatchId = "11111111-1111-4111-8111-111111111111"
        private const val AggregateRequestId = "22222222-2222-4222-8222-222222222222"
        private const val AggregateAnniversaryId = "33333333-3333-4333-8333-333333333333"
        private const val AggregateOccurrenceKey = "44444444-4444-4444-8444-444444444444"
        private const val AggregateDeliveryId = "55555555-5555-4555-8555-555555555555"
        private const val AggregateAttemptId = "66666666-6666-4666-8666-666666666666"
        private const val AggregateNotificationId = "77777777-7777-4777-8777-777777777777"
        private const val AggregateTemplateOne = "88888888-8888-4888-8888-888888888888"
        private const val AggregateTemplateTwo = "99999999-9999-4999-8999-999999999999"
        private val AggregateReminderIds = listOf(
            "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
        )
    }
}
