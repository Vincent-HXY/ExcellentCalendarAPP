package com.excellentcalendar.excellent_calendar.bridge.native

import android.content.Context
import java.io.File

object AndroidNativeBridgeFactory {
    fun create(context: Context): JniNativeEventBridge {
        val storageDirectory = File(
            context.applicationContext.filesDir,
            "local_storage/test_storage_json",
        )
        return JniNativeEventBridge(storageDirectory = storageDirectory.absolutePath)
    }
}


/*AndroidNativeBridgeFactory.create(context)
→ 创建 JniNativeEventBridge，并指定 storageDirectory
→ 上层调用 createEvent / createReminder 等方法
→ JniNativeEventBridge 加载 native 库
→ 初始化 C++ storage
→ 调用对应 JNI/C++ 函数

NativeEventBridge.kt
= 抽象能力接口，定义 Kotlin 可以向 C++ Core 请求哪些能力。

JniNativeEventBridge.kt
= JNI 实现类，真正负责加载 native 库、初始化存储、调用 C++ 函数。

AndroidNativeBridgeFactory.kt
= Android 创建入口，负责根据 Android Context 构造 JNI bridge，并指定正式数据目录。
 */