package com.excellentcalendar.excellent_calendar.bridge.ring

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

class RingStateEventHub : RingStateListener {
    private var sink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    val streamHandler: EventChannel.StreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            synchronized(this@RingStateEventHub) { sink = events }
        }

        override fun onCancel(arguments: Any?) {
            synchronized(this@RingStateEventHub) { sink = null }
        }
    }

    override fun onStateChanged(reason: String, event: Map<String, Any?>) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            deliver(event)
        } else {
            mainHandler.post { deliver(event) }
        }
    }

    private fun deliver(event: Map<String, Any?>) {
        val current = synchronized(this) { sink } ?: return
        runCatching { current.success(event) }
    }

    @Synchronized
    fun clear() {
        sink = null
    }

    companion object {
        const val ChannelName = "excellent_calendar/events/ring_state"
    }
}
