package com.excellentcalendar.excellent_calendar

import com.excellentcalendar.excellent_calendar.bridge.channel.NativeMethodChannelHandler
import com.excellentcalendar.excellent_calendar.bridge.native.JniNativeEventBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Android 端的 Flutter 入口 Activity。
 *
 * `FlutterActivity` 是 Flutter Android embedding 提供的基类：它负责启动 Flutter 引擎、
 * 渲染 Dart UI，并允许原生 Android 代码通过 `configureFlutterEngine` 注册平台通道。
 *
 * 本类的职责很小但很关键：
 * 1. 准备 C++ native 层需要的本地存储目录。
 * 2. 创建 `JniNativeEventBridge`，让 Kotlin 可以调用 JNI/C++。
 * 3. 注册 `MethodChannel`，让 Dart 可以用方法名调用 Kotlin。
 */
class MainActivity : FlutterActivity() {
    /**
     * 保存 handler 引用，避免它只被 MethodChannel 间接持有，也方便在引擎销毁时主动关闭线程池。
     *
     * Kotlin 里的 `?` 表示可空类型。这里初始时没有 handler，所以类型是
     * `NativeMethodChannelHandler?`，使用时需要 `?.` 安全调用。
     */
    private var nativeMethodChannelHandler: NativeMethodChannelHandler? = null

    /**
     * Flutter 引擎创建后会调用这个函数。
     *
     * 用法上，你可以把它理解成“注册 Flutter 与 Android 原生代码通信入口”的地方。
     * `override` 表示重写父类 `FlutterActivity` 中定义的方法。
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Android 每个 app 都有独立的 filesDir。这里把 JSON 存储放在 app 私有目录下，
        // 普通用户和其他 app 不能直接访问，适合保存本地业务数据。
        val storageDirectory = File(applicationContext.filesDir, "local_storage/test_storage_json")
        val nativeBridge = JniNativeEventBridge(storageDirectory = storageDirectory.absolutePath)
        val handler = NativeMethodChannelHandler(nativeEventBridge = nativeBridge)
        nativeMethodChannelHandler = handler
        // MethodChannel 是 Flutter 的“方法调用通道”：
        // Dart 侧用同一个 ChannelName 发起调用，Kotlin 侧通过 handler 接收并返回结果。
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NativeMethodChannelHandler.ChannelName,
        ).setMethodCallHandler(handler)
    }

    /**
     * Flutter 引擎准备释放时调用。
     *
     * 这里取消 MethodChannel handler，并关闭后台 executor，避免 Activity 重建或 app 退出后
     * 仍有线程/引用存活造成资源泄漏。
     */
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NativeMethodChannelHandler.ChannelName,
        ).setMethodCallHandler(null)
        nativeMethodChannelHandler?.close()
        nativeMethodChannelHandler = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
