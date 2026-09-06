package com.excellentcalendar.excellent_calendar.bridge.channel

import com.excellentcalendar.excellent_calendar.android.appearance.AppearancePreferencesStore
import com.excellentcalendar.excellent_calendar.android.appearance.AppearanceStorageException
import com.excellentcalendar.excellent_calendar.android.appearance.SharedPreferencesAppearanceStore
import com.excellentcalendar.excellent_calendar.bridge.contract.AppearanceContracts
import com.excellentcalendar.excellent_calendar.bridge.contract.EmptyRequestContract
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeErrorCodes
import com.excellentcalendar.excellent_calendar.bridge.contract.NativeResultContract
import io.flutter.plugin.common.MethodCall

internal class AppearanceMethodHandler(
    private val store: AppearancePreferencesStore?,
    private val calls: NativeCallExecutor,
) : ChannelMethodHandler {
    override val methods = setOf(
        NativeMethodChannelHandler.MethodAppearanceGetLocal,
        NativeMethodChannelHandler.MethodAppearanceUpdateLocal,
    )

    override fun handle(call: MethodCall, completion: SingleCompletion) {
        when (call.method) {
            NativeMethodChannelHandler.MethodAppearanceGetLocal -> {
                if (!calls.parse(call, completion) { EmptyRequestContract.validate(it) }.let { it != null }) return
                execute(call.method, completion) { store!!.getHabitProgressColor() }
            }
            NativeMethodChannelHandler.MethodAppearanceUpdateLocal -> {
                val token = calls.parse(call, completion, AppearanceContracts::update) ?: return
                if (token !in SharedPreferencesAppearanceStore.AllowedTokens) {
                    calls.executeOperation(call.method, completion) {
                        NativeResultContract.failure(
                            NativeErrorCodes.AppearanceColorTokenInvalid,
                            "Appearance color token is invalid.",
                            contractVersion = 2,
                        )
                    }
                    return
                }
                val display = AppearanceContracts.displayUpdate(call.arguments)
                execute(call.method, completion) {
                    if (display == null) store!!.updateHabitProgressColor(token)
                    else store!!.updateDisplayPreferences(token, display)
                }
            }
            else -> completion.notImplemented()
        }
    }

    private fun execute(method: String, completion: SingleCompletion, operation: () -> String) {
        calls.executeOperation(method, completion) {
            if (store == null) {
                NativeResultContract.failure(
                    NativeErrorCodes.AppearanceStorageFailed,
                    "Appearance storage is unavailable.",
                    contractVersion = 2,
                )
            } else try {
                NativeResultContract.success(AppearanceContracts.response(operation(), store.getDisplayPreferences()), contractVersion = 2)
            } catch (_: IllegalArgumentException) {
                NativeResultContract.failure(
                    NativeErrorCodes.AppearanceColorTokenInvalid,
                    "Appearance color token is invalid.",
                    contractVersion = 2,
                )
            } catch (_: AppearanceStorageException) {
                NativeResultContract.failure(
                    NativeErrorCodes.AppearanceStorageFailed,
                    "Appearance preferences could not be persisted.",
                    retryable = true,
                    contractVersion = 2,
                )
            }
        }
    }
}
