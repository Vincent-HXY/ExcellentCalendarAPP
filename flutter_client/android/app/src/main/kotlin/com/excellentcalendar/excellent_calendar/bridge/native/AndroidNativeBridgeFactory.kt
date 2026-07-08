package com.excellentcalendar.excellent_calendar.bridge.native

import android.content.Context

object AndroidNativeBridgeFactory {
    fun create(context: Context): NativeCalendarCoreBridge {
        val storageDirectory = CalendarCoreStorageDirectoryResolver.resolve(
            filesDir = context.applicationContext.filesDir,
        )
        return JniNativeCalendarCoreBridge(storageDirectory = storageDirectory.absolutePath)
    }
}


/*AndroidNativeBridgeFactory.create(context)
→ 创建 JniNativeCalendarCoreBridge，并指定 storageDirectory
→ 上层调用 createEvent / createReminder 等方法
→ JniNativeCalendarCoreBridge 加载 native 库
→ 初始化 C++ storage
→ 调用对应 JNI/C++ 函数

NativeEventBridge.kt
= Event 模块能力接口，只定义 event 相关 JNI 调用。

NativeReminderBridge.kt / NativeNotificationBridge.kt
= Reminder / Notification 模块能力接口。

NativeCalendarCoreBridge.kt
= 聚合接口，本身不新增方法，只继承各模块能力接口。

JniNativeCalendarCoreBridge.kt
= JNI 实现类，真正负责加载 native 库、初始化存储、调用 C++ 函数。

AndroidNativeBridgeFactory.kt
= Android 创建入口，负责根据 Android Context 构造 JNI bridge，并指定正式数据目录。
 */
