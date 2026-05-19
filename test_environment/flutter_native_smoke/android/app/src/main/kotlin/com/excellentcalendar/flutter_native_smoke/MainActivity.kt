package com.excellentcalendar.flutter_native_smoke

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "excellent_calendar/native_smoke"

        init {
            System.loadLibrary("native_smoke")
        }
    }

    external fun nativePing(): String

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
