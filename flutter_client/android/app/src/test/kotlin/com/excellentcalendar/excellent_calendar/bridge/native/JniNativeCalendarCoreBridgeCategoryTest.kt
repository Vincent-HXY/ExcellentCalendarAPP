package com.excellentcalendar.excellent_calendar.bridge.native

import com.excellentcalendar.excellent_calendar.bridge.codec.NativeContractJsonCodec
import java.lang.reflect.Modifier
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class JniNativeCalendarCoreBridgeCategoryTest {
    @Test
    fun categoryBridgeMethodsAreAbstractAndMustBeImplementedExplicitly() {
        listOf("listCategories", "createCategory").forEach { methodName ->
            val declaration = NativeCategoryBridge::class.java.getDeclaredMethod(
                methodName,
                String::class.java,
            )
            assertTrue("$methodName must not have a default throwing body", Modifier.isAbstract(declaration.modifiers))
        }
    }

    @Test
    fun everyCategoryBridgeMethodReachesItsDeclaredExternalJniCallPoint() {
        val calls = linkedMapOf<String, (JniNativeCalendarCoreBridge) -> String>(
            "nativeListCategoriesV2" to { it.listCategories("{}") },
            "nativeCreateCategoryV2" to { it.createCategory("{}") },
        )

        calls.forEach { (symbol, call) ->
            val declaration = JniNativeCalendarCoreBridge::class.java.getDeclaredMethod(
                symbol,
                String::class.java,
            )
            assertTrue("$symbol must remain a native declaration", Modifier.isNative(declaration.modifiers))
            try {
                call(bridge())
                fail("$symbol unexpectedly resolved without the Android C++ JNI library")
            } catch (error: NativeBridgeUnavailableException) {
                assertEquals("JNI symbol $symbol is unavailable.", error.message)
                assertTrue(error.cause is UnsatisfiedLinkError)
            }
        }
    }

    private fun bridge() = JniNativeCalendarCoreBridge(
        profile = NativeContractProfile.V2,
        runtimeRequestProvider = NativeRuntimeRequestProvider { "{}" },
        libraryLoader = NativeLibraryLoader { },
        runtimeInitializer = {
            NativeContractJsonCodec.encodeObject(
                linkedMapOf(
                    "ok" to true,
                    "data" to linkedMapOf(
                        "initialized" to true,
                        "storage_format_version" to 2,
                        "tzdb_version" to BundledTzdbExtractor.Version,
                    ),
                    "error" to null,
                    "contract_version" to 2,
                    "request_id" to "category-runtime-test",
                ),
            )
        },
    )
}
