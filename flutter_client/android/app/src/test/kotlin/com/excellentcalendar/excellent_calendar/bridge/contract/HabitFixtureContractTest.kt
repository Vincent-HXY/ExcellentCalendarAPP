package com.excellentcalendar.excellent_calendar.bridge.contract

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

/** Keeps the Kotlin fake/validator scenarios traceable to the frozen Contract fixtures. */
class HabitFixtureContractTest {
    @Test
    fun requestScenariosAreDerivedFromNamedContractFixtures() {
        HabitContracts.create(fixture("create_binary.valid.json"))
        HabitContracts.checkIn(fixture("check_in_manual_done.valid.json"))

        assertThrows(NativeContractViolation::class.java) {
            HabitContracts.create(fixture("create_fractional_hundredths.invalid.json"))
        }
        assertThrows(NativeContractViolation::class.java) {
            HabitContracts.checkIn(fixture("check_in_notification_action.valid.json"))
        }
    }

    @Test
    fun reconciliationAndAppearanceScenariosRetainFixtureSourceMapping() {
        val page = HabitContracts.reconcileResponse(fixture("reconcile_page.valid.json"), expectedLimit = 100)
        assertEquals(100, page.processedCount)
        assertThrows(NativeContractViolation::class.java) {
            HabitContracts.reconcileResponse(fixture("reconcile_zero_progress.invalid.json"), expectedLimit = 100)
        }

        assertEquals("indigo", AppearanceContracts.update(fixture("appearance_update.valid.json")))
        // Shape is valid, but the handler/store boundary owns the preset allow-list error.
        assertEquals("#4F46E5", AppearanceContracts.update(fixture("appearance_update.invalid.json")))
    }

    private fun fixture(name: String): Map<String, Any?> {
        val directory = fixtureDirectories.firstOrNull(File::isDirectory)
            ?: error("Cannot locate frozen Habit fixtures from ${System.getProperty("user.dir")}")
        return NativeContractJsonCodec.decodeObject(File(directory, name).readText(Charsets.UTF_8))
    }

    companion object {
        private val fixtureDirectories = listOf(
            File("../../../contracts/fixtures/habit"),
            File("../../contracts/fixtures/habit"),
            File("../contracts/fixtures/habit"),
            File("contracts/fixtures/habit"),
        )
    }
}
