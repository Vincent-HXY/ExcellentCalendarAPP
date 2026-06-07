package com.excellentcalendar.excellent_calendar

import com.excellentcalendar.excellent_calendar.bridge.channel.NativeMethodChannelHandler
import com.excellentcalendar.excellent_calendar.bridge.native.JniNativeEventBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var nativeMethodChannelHandler: NativeMethodChannelHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val handler = NativeMethodChannelHandler(
            nativeEventBridge = JniNativeEventBridge(),
        )
        nativeMethodChannelHandler = handler
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NativeMethodChannelHandler.ChannelName,
        ).setMethodCallHandler(handler)
    }

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
