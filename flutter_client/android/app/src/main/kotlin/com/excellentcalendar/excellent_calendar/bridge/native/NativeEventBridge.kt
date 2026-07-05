package com.excellentcalendar.excellent_calendar.bridge.native

/**
 * Kotlin 侧访问 native 事件能力的抽象接口。
 *
 * 这里故意只传入/返回 JSON 字符串，而不是直接暴露 C++ 对象：
 * - Flutter/Dart、Kotlin、C++ 三种语言之间没有共享的对象模型。
 * - JSON 是稳定的边界格式，便于记录、测试、校验和跨语言传递。
 * - 上层只依赖这个接口，测试时可以传入假的实现，不必真的加载 JNI 动态库。
 */
interface NativeEventBridge {
    /** 创建事件。`requestJson` 必须符合 CreateEventRequest 合约，返回 NativeResult JSON。 */
    fun createEvent(requestJson: String): String

    fun updateEvent(requestJson: String): String

    fun deleteEvent(requestJson: String): String

    /** 搜索事件。`requestJson` 必须符合 SearchEventRequest 合约，返回 NativeResult JSON。 */
    fun searchEvents(requestJson: String): String

    /** 完成一个单次、非重复事件。 */
    fun completeEvent(requestJson: String): String

    /** 将已完成的事件实例重新打开。当前 C++ 阶段可能返回 FEATURE_NOT_IMPLEMENTED。 */
    fun reopenEvent(requestJson: String): String

    fun createReminder(requestJson: String): String

    fun updateReminder(requestJson: String): String

    fun cancelReminder(requestJson: String): String

    fun listReminders(requestJson: String): String

    fun getReminder(requestJson: String): String

    fun listSchedulableReminders(requestJson: String): String

    fun markReminderScheduled(requestJson: String): String

    fun markReminderSent(requestJson: String): String

    fun markReminderFailed(requestJson: String): String

    fun enableReminder(requestJson: String): String

    fun disableReminder(requestJson: String): String

    fun createNotification(requestJson: String): String

    fun consumeReminderAfterDelivery(requestJson: String): String
}
