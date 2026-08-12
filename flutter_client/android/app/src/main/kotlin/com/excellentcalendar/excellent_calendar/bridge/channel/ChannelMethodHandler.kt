package com.excellentcalendar.excellent_calendar.bridge.channel

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/** One MethodChannel module with an explicit, non-overlapping method registry. */
internal interface ChannelMethodHandler {
    val methods: Set<String>

    fun handle(call: MethodCall, completion: SingleCompletion)
}

/** Ensures a Flutter MethodChannel call completes at most once and on the configured dispatcher. */
internal class SingleCompletion(
    private val result: MethodChannel.Result,
    private val dispatcher: ResultDispatcher,
) {
    private val completed = AtomicBoolean(false)

    fun success(value: Any?) {
        complete { result.success(value) }
    }

    fun notImplemented() {
        complete { result.notImplemented() }
    }

    private fun complete(block: () -> Unit) {
        if (completed.compareAndSet(false, true)) {
            dispatcher.dispatch(block)
        }
    }
}
