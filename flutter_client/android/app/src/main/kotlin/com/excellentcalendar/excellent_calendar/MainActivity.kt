package com.excellentcalendar.excellent_calendar

import com.excellentcalendar.excellent_calendar.bridge.channel.NativeMethodChannelHandler
import com.excellentcalendar.excellent_calendar.bridge.native.JniNativeEventBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var nativeMethodChannelHandler: NativeMethodChannelHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val storageDirectory = File(applicationContext.filesDir, "local_storage/test_storage_json")
        val nativeBridge = JniNativeEventBridge(storageDirectory = storageDirectory.absolutePath)
        val handler = NativeMethodChannelHandler(nativeEventBridge = nativeBridge)
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
