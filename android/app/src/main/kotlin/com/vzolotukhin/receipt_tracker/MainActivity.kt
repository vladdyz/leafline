package com.vzolotukhin.receipt_tracker

import com.vzolotukhin.receipt_tracker.ocr.OcrPlugin
// FlutterFragmentActivity, not FlutterActivity. local_auth shows the
// biometric prompt as a DialogFragment, which needs a FragmentActivity
// underneath it — with plain FlutterActivity the prompt simply never appears.
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {

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

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        ocrPlugin.unregister()
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
