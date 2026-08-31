package com.excellentcalendar.excellent_calendar.bridge.native

import org.junit.Assert.assertEquals
import org.junit.Test

class JniHabitBridgeTest {
    @Test
    fun productionAdapterUsesExactlyTheFrozenElevenSymbols() {
        val observed = mutableListOf<String>()
        val bridge = JniHabitBridge { symbol, request -> observed += symbol; request }
        val calls = listOf<(String) -> String>(
            bridge::createHabit,
            bridge::updateHabit,
            bridge::listHabits,
            bridge::getHabitDetail,
            bridge::endHabit,
            bridge::deleteHabit,
            bridge::checkInHabit,
            bridge::clearHabitCheckIn,
            bridge::listHabitDailyStatuses,
            bridge::setHabitReminder,
            bridge::reconcileHabitReminders,
        )
        calls.forEachIndexed { index, call -> assertEquals("request-$index", call("request-$index")) }
        assertEquals(HabitJniSymbolManifest.methods, observed)
        assertEquals(11, observed.distinct().size)
    }
}
