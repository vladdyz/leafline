package com.vzolotukhin.receipt_tracker

import com.vzolotukhin.receipt_tracker.ocr.OcrPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private val ocrPlugin = OcrPlugin()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ocrPlugin.register(flutterEngine.dartExecutor.binaryMessenger)
    }

    // If `cleanUpFlutterEngine` does not resolve against your Flutter version,
    // delete this override. It is hygiene, not a requirement — the plugin
    // lives exactly as long as the activity either way.
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        ocrPlugin.unregister()
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
