package com.excellentcalendar.excellent_calendar.bridge.native

/**
 * Aggregate bridge for flows that need multiple C++ Calendar Core modules.
 *
 * Add no direct methods here. New module-level JNI surfaces should get their own
 * narrow interface first, then be included in this aggregate interface.
 */
interface NativeCalendarCoreBridge :
    NativeRuntimeBridge,
    NativeEventBridge,
    NativeReminderBridge,
    NativeNotificationBridge,
    NativeAnniversaryBridge,
    NativeCategoryBridge
