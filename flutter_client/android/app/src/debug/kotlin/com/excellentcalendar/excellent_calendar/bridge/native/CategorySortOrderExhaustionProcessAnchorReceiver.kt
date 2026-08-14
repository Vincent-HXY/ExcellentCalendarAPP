package com.excellentcalendar.excellent_calendar.bridge.native

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Defines the debug-only secondary process targeted by the isolated JNI instrumentation. */
class CategorySortOrderExhaustionProcessAnchorReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) = Unit
}
