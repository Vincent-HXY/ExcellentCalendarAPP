package com.excellentcalendar.excellent_calendar.bridge

import com.excellentcalendar.excellent_calendar.bridge.channel.NativeBridgeLogger
import com.excellentcalendar.excellent_calendar.bridge.channel.NativeMethodChannelHandler
import com.excellentcalendar.excellent_calendar.bridge.channel.ResultDispatcher
import com.excellentcalendar.excellent_calendar.bridge.channel.AnniversaryCapabilityProvider
import com.excellentcalendar.excellent_calendar.bridge.channel.AnniversaryCapabilitySnapshot
import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import com.excellentcalendar.excellent_calendar.bridge.contract.ReconcileReminderScheduleContract
import com.excellentcalendar.excellent_calendar.bridge.native.NativeAnniversaryBridge
import com.excellentcalendar.excellent_calendar.bridge.native.NativeCalendarCoreBridge
import com.excellentcalendar.excellent_calendar.bridge.native.NativeContractProfile
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderScheduleReconciler
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderScheduleMode
import com.excellentcalendar.excellent_calendar.bridge.reminder.ReminderScheduleReconciliation
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.reflect.Proxy
import java.util.concurrent.Executor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AnniversaryMethodChannelHandlerTest {
    @Test
    fun everyAnniversaryMethodRoutesToItsNarrowBridgeAndPreservesRequestJson() {
        val bridge = RecordingAnniversaryBridge()
        val cases = listOf(
            Case(NativeMethodChannelHandler.MethodAnniversaryCreate, createRequest(), "create"),
            Case(NativeMethodChannelHandler.MethodAnniversaryUpdate, updateRequest(), "update"),
            Case(NativeMethodChannelHandler.MethodAnniversaryDelete, mapOf("id" to AnniversaryId), "delete"),
            Case(
                NativeMethodChannelHandler.MethodAnniversaryDetail,
                mapOf("id" to AnniversaryId, "timezone" to "Asia/Shanghai"),
                "detail",
            ),
            Case(NativeMethodChannelHandler.MethodAnniversaryList, listRequest(), "list"),
            Case(
                NativeMethodChannelHandler.MethodAnniversaryPreviewCountdown,
                linkedMapOf(
                    "date" to "2020-02-29",
                    "calendar_type" to "solar",
                    "recurrence" to linkedMapOf("frequency" to "yearly", "interval" to 1),
                    "timezone" to "Asia/Shanghai",
                ),
                "preview",
            ),
            Case(
                NativeMethodChannelHandler.MethodAnniversarySetRemindersEnabled,
                linkedMapOf(
                    "id" to AnniversaryId,
                    "reminders_enabled" to true,
                    "timezone" to "Asia/Shanghai",
                ),
                "toggle",
            ),
            Case(
                NativeMethodChannelHandler.MethodAnniversaryListOccurrences,
                occurrenceRequest(),
                "occurrences",
            ),
        )

        cases.forEach { case ->
            val result = invoke(handler(bridge), case.method, case.arguments)
            assertTrue("${case.method} should return NativeResult", result.successCalled)
            assertEquals(true, result.successMap()["ok"])
        }

        assertEquals(cases.map { it.bridgeOperation }, bridge.calls.map { it.first })
        cases.zip(bridge.calls).forEach { (case, call) ->
            val jsonNormalized = NativeContractJsonCodec.decodeObject(
                NativeContractJsonCodec.encodeObject(case.arguments),
            )
            assertEquals(jsonNormalized, call.second)
        }
    }

    @Test
    fun listRequestPreservesNullNumberArrayNestedDateEnumAndBooleanResponseFields() {
        val bridge = RecordingAnniversaryBridge()
        val result = invoke(
            handler(bridge),
            NativeMethodChannelHandler.MethodAnniversaryList,
            listRequest(),
        )

        val forwarded = bridge.calls.single().second
        assertEquals(listOf(CategoryId), forwarded["category_ids"])
        assertEquals(listOf("important_noturgent"), forwarded["importance"])
        @Suppress("UNCHECKED_CAST")
        val pagination = forwarded["pagination"] as Map<String, Any?>
        assertEquals(2, pagination["page"])
        assertEquals(null, pagination["cursor"])
        @Suppress("UNCHECKED_CAST")
        val responsePagination = (result.successMap()["data"] as Map<String, Any?>)["pagination"] as Map<String, Any?>
        assertEquals(false, responsePagination["has_more"])
    }

    @Test
    @Suppress("UNCHECKED_CAST")
    fun nestedSortAndDoublePositionConflictFailBeforeTheNativeBridge() {
        val nestedOnly = listRequest().toMutableMap().also { request ->
            request.remove("sort_by")
            request.remove("sort_direction")
            val pagination = (request["pagination"] as Map<String, Any?>).toMutableMap()
            pagination["sort_by"] = "title"
            request["pagination"] = pagination
        }
        val conflicting = listRequest().toMutableMap().also { request ->
            val pagination = (request["pagination"] as Map<String, Any?>).toMutableMap()
            pagination["sort_by"] = "target_occurrence_date"
            pagination["sort_direction"] = "asc"
            request["pagination"] = pagination
        }
        val bridge = RecordingAnniversaryBridge()

        listOf(nestedOnly, conflicting).forEach { invalid ->
            val result = invoke(
                handler(bridge),
                NativeMethodChannelHandler.MethodAnniversaryList,
                invalid,
            )
            assertEquals(NativeErrorCodes.ContractValidationFailed, result.errorCode())
        }
        assertTrue(bridge.calls.isEmpty())
    }

    @Test
    fun businessAndContractErrorsAreForwardedAsNativeResultWithoutPlatformError() {
        val errors = listOf(
            NativeErrorCodes.AnniversaryNotFound,
            NativeErrorCodes.ContractValidationFailed,
            NativeErrorCodes.AnniversaryCalendarUnsupported,
        )
        errors.forEach { code ->
            val bridge = RecordingAnniversaryBridge(
                overrideJson = nativeFailure(code, requestId = "failure-$code"),
            )
            val result = invoke(
                handler(bridge),
                NativeMethodChannelHandler.MethodAnniversaryDetail,
                mapOf("id" to AnniversaryId, "timezone" to "Asia/Shanghai"),
            )

            assertFalse(result.errorCalled)
            assertEquals(false, result.successMap()["ok"])
            assertEquals(code, result.errorCode())
            assertEquals("failure-$code", result.successMap()["request_id"])
        }
    }

    @Test
    fun missingRecurrenceOrTimezoneFailsBeforeTheNativeBridge() {
        val bridge = RecordingAnniversaryBridge()
        val invalidRequests = listOf(
            createRequest().toMutableMap().also { it.remove("recurrence") },
            createRequest().toMutableMap().also { it.remove("timezone") },
            createRequest().toMutableMap().also { it["timezone"] = "" },
        )

        invalidRequests.forEach { invalid ->
            val result = invoke(
                handler(bridge),
                NativeMethodChannelHandler.MethodAnniversaryCreate,
                invalid,
            )
            assertEquals(NativeErrorCodes.ContractValidationFailed, result.errorCode())
        }
        assertTrue(bridge.calls.isEmpty())
    }

    @Test
    fun impossibleDateAndUtcInstantFailAtTheContractBoundary() {
        val requestBridge = RecordingAnniversaryBridge()
        val invalidRequest = createRequest().toMutableMap().also {
            it["date"] = "2021-02-29"
        }
        val requestResult = invoke(
            handler(requestBridge),
            NativeMethodChannelHandler.MethodAnniversaryCreate,
            invalidRequest,
        )
        assertEquals(NativeErrorCodes.ContractValidationFailed, requestResult.errorCode())
        assertTrue(requestBridge.calls.isEmpty())

        val invalidAnniversary = anniversaryResponse().toMutableMap().also {
            it["created_at"] = "2026-02-30T01:02:03Z"
        }
        val invalidDetail = detailResponse().toMutableMap().also {
            it["anniversary"] = invalidAnniversary
        }
        val responseResult = invoke(
            handler(
                RecordingAnniversaryBridge(
                    overrideJson = nativeSuccess(invalidDetail, requestId = "invalid-instant"),
                ),
            ),
            NativeMethodChannelHandler.MethodAnniversaryDetail,
            mapOf("id" to AnniversaryId, "timezone" to "Asia/Shanghai"),
        )
        assertEquals(NativeErrorCodes.ContractValidationFailed, responseResult.errorCode())
    }

    @Test
    fun malformedNativeSuccessIsConvertedToContractFailure() {
        val malformed = nativeSuccess(
            linkedMapOf("anniversary" to anniversaryResponse()),
            requestId = "malformed",
        )
        val result = invoke(
            handler(RecordingAnniversaryBridge(overrideJson = malformed)),
            NativeMethodChannelHandler.MethodAnniversaryDetail,
            mapOf("id" to AnniversaryId, "timezone" to "Asia/Shanghai"),
        )

        assertEquals(NativeErrorCodes.ContractValidationFailed, result.errorCode())
    }

    @Test
    fun updateRequiresAndForwardsExpectedUpdatedAtAndPreservesConflict() {
        val invalidBridge = RecordingAnniversaryBridge()
        val missing = updateRequest().toMutableMap().also { it.remove("expected_updated_at") }
        val fractional = updateRequest().toMutableMap().also {
            it["expected_updated_at"] = "2026-08-08T02:03:04.123Z"
        }

        listOf(missing, fractional).forEach { invalid ->
            val result = invoke(
                handler(invalidBridge),
                NativeMethodChannelHandler.MethodAnniversaryUpdate,
                invalid,
            )
            assertEquals(NativeErrorCodes.ContractValidationFailed, result.errorCode())
        }
        assertTrue(invalidBridge.calls.isEmpty())

        val conflictBridge = RecordingAnniversaryBridge(
            overrideJson = nativeFailure(
                NativeErrorCodes.AnniversaryUpdateConflict,
                requestId = "update-conflict",
            ),
        )
        val conflict = invoke(
            handler(conflictBridge),
            NativeMethodChannelHandler.MethodAnniversaryUpdate,
            updateRequest(),
        )

        assertEquals(false, conflict.successMap()["ok"])
        assertEquals(NativeErrorCodes.AnniversaryUpdateConflict, conflict.errorCode())
        assertEquals("2026-08-08T02:03:04Z", conflictBridge.calls.single().second["expected_updated_at"])
    }

    @Test
    fun committedMutationReconcilesOnceAndReturnsExactCapability() {
        var reconcileCalls = 0
        var retries = 0
        val bridge = RecordingAnniversaryBridge(
            overrideJson = nativeSuccess(detailResponse(reconciliationRequired = true), "commit"),
        )
        val result = invoke(
            handler(
                bridge,
                reconciler = object : ReminderScheduleReconciler {
                    override fun reconcile(
                        request: ReconcileReminderScheduleContract,
                        executionBudgetMillis: Long,
                    ): NativeResultContract {
                        reconcileCalls += 1
                        return NativeResultContract.success(mapOf("action" to "scheduled"), contractVersion = 2)
                    }

                    override fun reconcileWithOutcome(
                        request: ReconcileReminderScheduleContract,
                        executionBudgetMillis: Long,
                    ): ReminderScheduleReconciliation = ReminderScheduleReconciliation(
                        result = reconcile(request, executionBudgetMillis),
                        scheduleMode = ReminderScheduleMode.Exact,
                    )
                },
                capability = capability(canPost = true, exact = true),
                retry = { retries += 1 },
            ),
            NativeMethodChannelHandler.MethodAnniversaryCreate,
            createRequest(),
        )

        val data = result.successMap()["data"] as Map<*, *>
        val capability = data["capability"] as Map<*, *>
        val detail = data["detail"] as Map<*, *>
        val settings = detail["reminder_settings"] as Map<*, *>
        assertEquals(true, data["data_saved"])
        assertEquals("scheduled_exact", capability["schedule_status"])
        assertEquals(false, capability["schedule_reconciliation_required"])
        assertEquals(false, settings["schedule_reconciliation_required"])
        assertEquals(1, reconcileCalls)
        assertEquals(0, retries)
        assertEquals(1, result.successCount)
    }

    @Test
    fun committedMutationUsesActualApproximateResultInsteadOfExactPermissionSnapshot() {
        var retries = 0
        val scheduled = NativeResultContract.success(mapOf("action" to "scheduled"), contractVersion = 2)
        val result = invoke(
            handler(
                RecordingAnniversaryBridge(
                    overrideJson = nativeSuccess(detailResponse(reconciliationRequired = true), "commit"),
                ),
                reconciler = object : ReminderScheduleReconciler {
                    override fun reconcile(
                        request: ReconcileReminderScheduleContract,
                        executionBudgetMillis: Long,
                    ): NativeResultContract = scheduled

                    override fun reconcileWithOutcome(
                        request: ReconcileReminderScheduleContract,
                        executionBudgetMillis: Long,
                    ): ReminderScheduleReconciliation = ReminderScheduleReconciliation(
                        result = scheduled,
                        scheduleMode = ReminderScheduleMode.Approximate,
                    )
                },
                capability = capability(canPost = true, exact = true),
                retry = { retries += 1 },
            ),
            NativeMethodChannelHandler.MethodAnniversaryCreate,
            createRequest(),
        )

        val data = result.successMap()["data"] as Map<*, *>
        val capability = data["capability"] as Map<*, *>
        assertEquals("scheduled_approximate", capability["schedule_status"])
        assertEquals(false, capability["schedule_reconciliation_required"])
        assertEquals(listOf("exact_alarm_permission_unavailable"), capability["degradation_reasons"])
        assertEquals(0, retries)
    }

    @Test
    fun committedMutationKeepsDataSavedWhenReconciliationMustRetry() {
        var retries = 0
        val result = invoke(
            handler(
                RecordingAnniversaryBridge(
                    overrideJson = nativeSuccess(detailResponse(reconciliationRequired = true), "commit"),
                ),
                reconciler = object : ReminderScheduleReconciler {
                    override fun reconcile(
                        request: ReconcileReminderScheduleContract,
                        executionBudgetMillis: Long,
                    ) = NativeResultContract.failure(
                        NativeErrorCodes.AlarmScheduleFailed,
                        "alarm unavailable",
                        retryable = true,
                        contractVersion = 2,
                    )
                },
                capability = capability(canPost = true, exact = true),
                retry = { retries += 1 },
            ),
            NativeMethodChannelHandler.MethodAnniversaryUpdate,
            updateRequest(),
        )

        val data = result.successMap()["data"] as Map<*, *>
        val capability = data["capability"] as Map<*, *>
        assertEquals(true, result.successMap()["ok"])
        assertEquals(true, data["data_saved"])
        assertEquals("pending_reconciliation", capability["schedule_status"])
        assertEquals(true, capability["schedule_reconciliation_required"])
        assertEquals(listOf("scheduler_retry_required"), capability["degradation_reasons"])
        assertEquals(1, retries)
        assertEquals(1, result.successCount)
    }

    @Test
    fun deniedNotificationPermissionDefersWithoutCallingScheduler() {
        var reconcileCalls = 0
        var retries = 0
        val result = invoke(
            handler(
                RecordingAnniversaryBridge(
                    overrideJson = nativeSuccess(detailResponse(reconciliationRequired = true), "commit"),
                ),
                reconciler = object : ReminderScheduleReconciler {
                    override fun reconcile(
                        request: ReconcileReminderScheduleContract,
                        executionBudgetMillis: Long,
                    ): NativeResultContract {
                        reconcileCalls += 1
                        return NativeResultContract.success(mapOf("action" to "scheduled"), contractVersion = 2)
                    }
                },
                capability = capability(canPost = false, exact = false),
                retry = { retries += 1 },
            ),
            NativeMethodChannelHandler.MethodAnniversarySetRemindersEnabled,
            mapOf("id" to AnniversaryId, "reminders_enabled" to true, "timezone" to "Asia/Shanghai"),
        )

        val data = result.successMap()["data"] as Map<*, *>
        val capability = data["capability"] as Map<*, *>
        assertEquals("pending_permission", capability["schedule_status"])
        assertEquals(listOf("notification_permission_unavailable"), capability["degradation_reasons"])
        assertEquals(0, reconcileCalls)
        assertEquals(1, retries)
    }

    @Test
    fun deniedNotificationPermissionDoesNotBlockDisabledReminderCancellation() {
        var reconcileCalls = 0
        var retries = 0
        val result = invoke(
            handler(
                RecordingAnniversaryBridge(
                    overrideJson = nativeSuccess(
                        detailResponse(
                            reconciliationRequired = true,
                            remindersEnabled = false,
                        ),
                        "commit",
                    ),
                ),
                reconciler = object : ReminderScheduleReconciler {
                    override fun reconcile(
                        request: ReconcileReminderScheduleContract,
                        executionBudgetMillis: Long,
                    ): NativeResultContract {
                        reconcileCalls += 1
                        return NativeResultContract.success(
                            mapOf("action" to "cancelled"),
                            contractVersion = 2,
                        )
                    }
                },
                capability = capability(canPost = false, exact = false),
                retry = { retries += 1 },
            ),
            NativeMethodChannelHandler.MethodAnniversarySetRemindersEnabled,
            mapOf(
                "id" to AnniversaryId,
                "reminders_enabled" to false,
                "timezone" to "Asia/Shanghai",
            ),
        )

        val data = result.successMap()["data"] as Map<*, *>
        val capability = data["capability"] as Map<*, *>
        assertEquals("not_required", capability["schedule_status"])
        assertEquals(false, capability["schedule_reconciliation_required"])
        assertEquals("denied", capability["notification_permission_status"])
        assertEquals(emptyList<String>(), capability["degradation_reasons"])
        assertEquals(1, reconcileCalls)
        assertEquals(0, retries)
    }

    @Test
    fun deniedNotificationPermissionDoesNotMisreportPendingCancellationAsPermissionBlocked() {
        val result = invoke(
            handler(
                RecordingAnniversaryBridge(
                    overrideJson = nativeSuccess(
                        detailResponse(
                            reconciliationRequired = true,
                            remindersEnabled = false,
                        ),
                        "detail",
                    ),
                ),
                capability = capability(canPost = false, exact = false),
            ),
            NativeMethodChannelHandler.MethodAnniversaryDetail,
            mapOf("id" to AnniversaryId, "timezone" to "Asia/Shanghai"),
        )

        val data = result.successMap()["data"] as Map<*, *>
        val capability = data["capability"] as Map<*, *>
        assertEquals("pending_reconciliation", capability["schedule_status"])
        assertEquals(true, capability["schedule_reconciliation_required"])
        assertEquals(listOf("scheduler_retry_required"), capability["degradation_reasons"])
    }

    @Test
    fun invalidReminderPlanAndOccurrenceWindowFailBeforeNative() {
        val bridge = RecordingAnniversaryBridge()
        val duplicatePlan = createRequest().toMutableMap().also { request ->
            val plan = request["reminder_plan"] as Map<String, Any?>
            request["reminder_plan"] = plan + ("templates" to listOf(planTemplate(), planTemplate()))
        }
        val fractional = createRequest().toMutableMap().also { request ->
            request["reminder_plan"] = mapOf(
                "reminders_enabled" to true,
                "templates" to listOf(planTemplate() + ("advance_days" to 10.5)),
            )
        }
        val tooLargeRange = occurrenceRequest().toMutableMap().also { it["range_end_date"] = "2027-09-06" }
        val malformedCursor = occurrenceRequest().toMutableMap().also { it["cursor"] = "bad" }

        listOf(duplicatePlan, fractional).forEach { invalid ->
            assertEquals(
                NativeErrorCodes.ContractValidationFailed,
                invoke(handler(bridge), NativeMethodChannelHandler.MethodAnniversaryCreate, invalid).errorCode(),
            )
        }
        listOf(tooLargeRange, malformedCursor).forEach { invalid ->
            assertEquals(
                NativeErrorCodes.ContractValidationFailed,
                invoke(handler(bridge), NativeMethodChannelHandler.MethodAnniversaryListOccurrences, invalid).errorCode(),
            )
        }
        assertTrue(bridge.calls.isEmpty())
    }

    private fun handler(
        bridge: NativeAnniversaryBridge,
        reconciler: ReminderScheduleReconciler? = null,
        capability: AnniversaryCapabilityProvider = capability(canPost = false, exact = false),
        retry: (() -> Unit)? = null,
    ) = NativeMethodChannelHandler(
        nativeCalendarCoreBridge = unusedAggregateBridge(),
        nativeAnniversaryBridge = bridge,
        contractProfile = NativeContractProfile.V2,
        executor = Executor { command -> command.run() },
        resultDispatcher = ResultDispatcher { block -> block() },
        logger = NativeBridgeLogger { _, _, _ -> },
        reminderScheduleCoordinator = reconciler,
        anniversaryCapabilityProvider = capability,
        reconcileRetryEnqueuer = retry,
    )

    private fun invoke(
        handler: NativeMethodChannelHandler,
        method: String,
        arguments: Map<String, Any?>,
    ): RecordingResult = RecordingResult().also {
        handler.onMethodCall(MethodCall(method, arguments), it)
    }

    private class RecordingAnniversaryBridge(
        private val overrideJson: String? = null,
    ) : NativeAnniversaryBridge {
        val calls = mutableListOf<Pair<String, Map<String, Any?>>>()

        override fun createAnniversary(requestJson: String) = record("create", requestJson, detailResponse())
        override fun updateAnniversary(requestJson: String) = record("update", requestJson, detailResponse())
        override fun deleteAnniversary(requestJson: String) = record("delete", requestJson, deleteCommitResponse())
        override fun getAnniversaryDetail(requestJson: String) = record("detail", requestJson, detailResponse())
        override fun listAnniversaries(requestJson: String) = record("list", requestJson, listResponse())
        override fun previewAnniversaryCountdown(requestJson: String) = record("preview", requestJson, countdownResponse())
        override fun setAnniversaryRemindersEnabled(requestJson: String) = record("toggle", requestJson, detailResponse())
        override fun listAnniversaryOccurrences(requestJson: String) = record("occurrences", requestJson, occurrenceListResponse())

        private fun record(operation: String, requestJson: String, data: Any?): String {
            calls += operation to NativeContractJsonCodec.decodeObject(requestJson)
            return overrideJson ?: nativeSuccess(data, requestId = "$operation-request")
        }
    }

    private class RecordingResult : MethodChannel.Result {
        var successValue: Any? = null
            private set
        var successCalled = false
            private set
        var errorCalled = false
            private set

        var successCount = 0
            private set

        override fun success(result: Any?) {
            successCalled = true
            successCount += 1
            successValue = result
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            errorCalled = true
        }

        override fun notImplemented() = Unit

        @Suppress("UNCHECKED_CAST")
        fun successMap(): Map<String, Any?> = successValue as Map<String, Any?>

        @Suppress("UNCHECKED_CAST")
        fun errorCode(): String = ((successMap()["error"] as Map<String, Any?>)["code"] as String)
    }

    private data class Case(
        val method: String,
        val arguments: Map<String, Any?>,
        val bridgeOperation: String,
    )

    companion object {
        private const val AnniversaryId = "11111111-1111-4111-8111-111111111111"
        private const val RecurrenceId = "22222222-2222-4222-8222-222222222222"
        private const val CategoryId = "33333333-3333-4333-8333-333333333333"

        private fun planTemplate(): Map<String, Any?> = linkedMapOf(
            "advance_days" to 10.0,
            "local_time" to "09:30",
            "method" to "popup",
            "is_enabled" to true,
        )

        private fun createRequest(): Map<String, Any?> = linkedMapOf(
            "title" to "Project anniversary",
            "date" to "2020-02-29",
            "calendar_type" to "solar",
            "category_id" to CategoryId,
            "recurrence" to linkedMapOf("frequency" to "yearly", "interval" to 1),
            "note" to null,
            "importance" to "important_noturgent",
            "timezone" to "Asia/Shanghai",
            "reminder_plan" to linkedMapOf(
                "reminders_enabled" to true,
                "templates" to listOf(
                    planTemplate(),
                ),
            ),
        )

        private fun updateRequest(): Map<String, Any?> = linkedMapOf(
            "id" to AnniversaryId,
            "expected_updated_at" to "2026-08-08T02:03:04Z",
            *createRequest().entries.map { it.key to it.value }.toTypedArray(),
        )

        private fun listRequest(): Map<String, Any?> = linkedMapOf(
            "timezone" to "Asia/Shanghai",
            "category_ids" to listOf(CategoryId),
            "importance" to listOf("important_noturgent"),
            "pagination" to linkedMapOf(
                "page" to 2,
                "page_size" to 20,
                "cursor" to null,
            ),
            "sort_by" to "countdown_days",
            "sort_direction" to "desc",
        )

        private fun occurrenceRequest(): Map<String, Any?> = linkedMapOf(
            "range_start_date" to "2026-08-01",
            "range_end_date" to "2027-09-05",
            "timezone" to "Asia/Shanghai",
            "category_ids" to emptyList<String>(),
            "importance" to emptyList<String>(),
            "cursor" to null,
            "page_size" to 50.0,
        )

        private fun anniversaryResponse(deleted: Boolean = false): Map<String, Any?> = linkedMapOf(
            "id" to AnniversaryId,
            "title" to "Project anniversary",
            "date" to "2020-02-29",
            "calendar_type" to "solar",
            "category_id" to CategoryId,
            "recurrence_id" to RecurrenceId,
            "note" to null,
            "importance" to "important_noturgent",
            "created_at" to "2026-08-08T01:02:03Z",
            "updated_at" to "2026-08-08T02:03:04Z",
            "deleted_at" to if (deleted) "2026-08-08T03:04:05Z" else null,
        )

        private fun countdownResponse(): Map<String, Any?> = linkedMapOf(
            "relation" to "remaining",
            "days" to 203,
            "target_occurrence_date" to "2027-02-28",
            "iso_weekday" to 7,
            "timezone" to "Asia/Shanghai",
            "calculated_at" to "2026-08-08T04:05:06Z",
        )

        private fun detailResponse(
            reconciliationRequired: Boolean = false,
            remindersEnabled: Boolean = true,
        ): Map<String, Any?> = linkedMapOf(
            "anniversary" to anniversaryResponse(),
            "recurrence" to linkedMapOf(
                "recurrence_id" to RecurrenceId,
                "frequency" to "yearly",
                "interval" to 1,
            ),
            "countdown" to countdownResponse(),
            "reminder_settings" to linkedMapOf(
                "reminders_enabled" to remindersEnabled,
                "templates" to listOf(
                    linkedMapOf(
                        "template_key" to "44444444-4444-4444-8444-444444444444",
                        "advance_days" to 10.0,
                        "local_time" to "09:30",
                        "timezone_mode" to "follow_device",
                        "method" to "popup",
                        "is_enabled" to true,
                    ),
                ),
                "active_reminder_count" to if (remindersEnabled) 1.0 else 0.0,
                "schedule_reconciliation_required" to reconciliationRequired,
            ),
        )

        private fun deleteCommitResponse(): Map<String, Any?> = linkedMapOf(
            "anniversary" to anniversaryResponse(deleted = true),
            "schedule_reconciliation_required" to false,
        )

        private fun occurrenceListResponse(): Map<String, Any?> = linkedMapOf(
            "items" to listOf(
                linkedMapOf(
                    "anniversary_id" to AnniversaryId,
                    "occurrence_key" to "55555555-5555-4555-8555-555555555555",
                    "occurrence_date" to "2027-02-28",
                    "source_date" to "2020-02-29",
                    "title" to "Project anniversary",
                    "calendar_type" to "solar",
                    "is_repeating" to true,
                    "years_elapsed" to 7.0,
                    "category_id" to CategoryId,
                    "importance" to "important_noturgent",
                    "has_active_reminders" to true,
                    "reminder_count" to 1.0,
                ),
            ),
            "has_more" to false,
            "next_cursor" to null,
        )

        private fun listResponse(): Map<String, Any?> = linkedMapOf(
            "items" to listOf(
                linkedMapOf(
                    "anniversary" to anniversaryResponse(),
                    "countdown" to countdownResponse(),
                ),
            ),
            "pagination" to linkedMapOf(
                "total" to 1,
                "page" to 2,
                "page_size" to 20,
                "has_more" to false,
                "next_cursor" to null,
            ),
        )

        private fun nativeSuccess(data: Any?, requestId: String): String =
            NativeContractJsonCodec.encodeObject(
                linkedMapOf(
                    "ok" to true,
                    "data" to data,
                    "error" to null,
                    "contract_version" to 2,
                    "request_id" to requestId,
                ),
            )

        private fun nativeFailure(code: String, requestId: String): String =
            NativeContractJsonCodec.encodeObject(
                linkedMapOf(
                    "ok" to false,
                    "data" to null,
                    "error" to linkedMapOf(
                        "code" to code,
                        "message" to "Anniversary failure",
                        "details" to linkedMapOf("source" to "test"),
                        "retryable" to false,
                    ),
                    "contract_version" to 2,
                    "request_id" to requestId,
                ),
            )

        private fun capability(canPost: Boolean, exact: Boolean): AnniversaryCapabilityProvider =
            AnniversaryCapabilityProvider {
                AnniversaryCapabilitySnapshot(
                    notificationPermissionStatus = if (canPost) "granted" else "denied",
                    exactAlarmPermissionStatus = if (exact) "granted" else "denied",
                    canPostNotifications = canPost,
                    canScheduleExactAlarms = exact,
                )
            }

        private fun unusedAggregateBridge(): NativeCalendarCoreBridge =
            Proxy.newProxyInstance(
                NativeCalendarCoreBridge::class.java.classLoader,
                arrayOf(NativeCalendarCoreBridge::class.java),
            ) { _, method, _ ->
                throw AssertionError("Unexpected aggregate bridge call: ${method.name}")
            } as NativeCalendarCoreBridge
    }
}
