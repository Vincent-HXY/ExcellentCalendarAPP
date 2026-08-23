package com.excellentcalendar.excellent_calendar.bridge

import com.excellentcalendar.excellent_calendar.bridge.contract.NativeContractViolation
import com.excellentcalendar.excellent_calendar.bridge.contract.RingRequestContracts
import org.junit.Assert.assertEquals
import org.junit.Test

class RingContractsTest {
    @Test
    fun activeItemsRejectsDuplicateDeliveryIds() {
        val id = "11111111-1111-4111-8111-111111111111"
        assertFailsField("ActiveRingItemsRequest.delivery_ids") {
            RingRequestContracts.activeItems(
                mapOf(
                    "runtime_instance_id" to id,
                    "session_id" to "22222222-2222-4222-8222-222222222222",
                    "expected_session_revision" to 1,
                    "delivery_ids" to listOf(id, id),
                ),
            )
        }
    }

    @Test
    fun completeItemKeepsWireIdentityExact() {
        val request = RingRequestContracts.completeItem(
            mapOf(
                "runtime_instance_id" to "11111111-1111-4111-8111-111111111111",
                "session_id" to "22222222-2222-4222-8222-222222222222",
                "expected_session_revision" to 9L,
                "delivery_id" to "33333333-3333-4333-8333-333333333333",
            ),
        )
        assertEquals(9L, request.expectedSessionRevision)
        assertEquals("33333333-3333-4333-8333-333333333333", request.deliveryId)
    }

    private fun assertFailsField(field: String, block: () -> Unit) {
        try {
            block()
            throw AssertionError("Expected NativeContractViolation")
        } catch (error: NativeContractViolation) {
            assertEquals(field, error.field)
        }
    }
}
