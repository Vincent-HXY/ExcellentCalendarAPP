package com.excellentcalendar.excellent_calendar.android.ring

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.widget.Toast
import java.util.concurrent.Executors

class RingActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in setOf(ActionStop, ActionSnooze, ActionComplete)) return
        val ids = intent.getStringArrayExtra(ExtraDeliveryIds)?.filter { it.isNotBlank() }.orEmpty()
        if (ids.isEmpty()) return
        val pending = goAsync()
        Executor.execute {
            try {
                val runtime = RingRuntimeProvider.get(context.applicationContext)
                when (intent.action) {
                    ActionStop -> runtime.stopFromNotification(ids)
                    ActionSnooze -> {
                        val feedback = ringSnoozeFeedback(runtime.snoozeFromNotification(ids))
                        if (feedback != null) {
                            Handler(Looper.getMainLooper()).post {
                                Toast.makeText(context.applicationContext, feedback, Toast.LENGTH_LONG).show()
                            }
                        }
                    }
                    ActionComplete -> runtime.completeFromNotification(ids.first())
                }
            } finally {
                pending.finish()
            }
        }
    }

    companion object {
        const val ActionStop = "excellent_calendar.action.RING_STOP"
        const val ActionSnooze = "excellent_calendar.action.RING_SNOOZE"
        const val ActionComplete = "excellent_calendar.action.RING_COMPLETE"
        const val ExtraDeliveryIds = "delivery_ids"
        private val Executor = Executors.newSingleThreadExecutor()
    }
}
