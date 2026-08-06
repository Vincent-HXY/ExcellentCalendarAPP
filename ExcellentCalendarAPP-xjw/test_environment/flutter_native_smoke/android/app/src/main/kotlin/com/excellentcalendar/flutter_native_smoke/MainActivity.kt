package com.excellentcalendar.flutter_native_smoke

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 最小 native smoke 测试 Activity。
 *
 * 这个环境不跑完整日历业务，只验证 Flutter -> Kotlin MethodChannel -> JNI -> C++
 * 这条链路能否打通。成功时 Dart 调用 `pingNative` 会得到 C++ 返回的 pong 字符串。
 */
class MainActivity : FlutterActivity() {
    companion object {
        /** smoke 测试专用 channel，避免和正式 app 的 channel 混用。 */
        private const val CHANNEL = "excellent_calendar/native_smoke"

        init {
            // 加载 android/app/src/main/cpp 编译出的 native_smoke 动态库。
            System.loadLibrary("native_smoke")
        }
    }

    /** external 表示函数体在 C++ JNI 文件 native_ping.cpp 中。 */
    external fun nativePing(): String

    /** 注册 smoke MethodChannel handler。 */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            call,
            result ->
            when (call.method) {
                "pingNative" -> result.success(nativePing())
                else -> result.notImplemented()
            }
        }
    }
}
