package com.mk2004.heartnagaland

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MODEL_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method == "getMobileFaceNetPath") {
                try {
                    val cacheFile = File(cacheDir, "mobilefacenet.tflite")
                    if (!cacheFile.exists()) {
                        assets.open("models/mobilefacenet.tflite").use { input ->
                            FileOutputStream(cacheFile).use { output ->
                                input.copyTo(output)
                            }
                        }
                    }
                    result.success(cacheFile.absolutePath)
                } catch (e: Exception) {
                    result.error("MODEL", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    companion object {
        private const val MODEL_CHANNEL = "com.mk2004.heartnagaland/tflite_model"
    }
}
