package com.vzolotukhin.receipt_tracker

import com.vzolotukhin.receipt_tracker.ocr.OcrPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private val ocrPlugin = OcrPlugin()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // ML Kit needs a Context to read the image file and its EXIF
        // orientation. applicationContext rather than `this`, so the plugin
        // never outlives a reference to a destroyed Activity.
        ocrPlugin.register(
            flutterEngine.dartExecutor.binaryMessenger,
            applicationContext,
        )
    }

    // If `cleanUpFlutterEngine` does not resolve against your Flutter version,
    // delete this override — but note it now also closes the recogniser, which
    // is worth keeping if you can.
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        ocrPlugin.unregister()
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
