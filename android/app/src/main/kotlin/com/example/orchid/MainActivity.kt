package com.example.orchid

import android.content.Intent
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "orchid/audio_routes"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openAudioSettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("audio_settings_unavailable", error.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
