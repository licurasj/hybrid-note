package com.yonghao.hybridnote

import android.os.SystemClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The boot time, read as RingBootReceiver reads it (T-13 unit 14, G2).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.yonghao.hybridnote/boot")
            .setMethodCallHandler { call, result ->
                if (call.method == "bootMs") {
                    result.success(System.currentTimeMillis() - SystemClock.elapsedRealtime())
                } else {
                    result.notImplemented()
                }
            }
    }
}
