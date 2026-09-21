package com.vzolotukhin.receipt_tracker

import com.vzolotukhin.receipt_tracker.ocr.OcrPlugin
import com.vzolotukhin.receipt_tracker.widget.BudgetWidgetPlugin
// FlutterFragmentActivity, not FlutterActivity. local_auth shows the
// biometric prompt as a DialogFragment, which needs a FragmentActivity
// underneath it — with plain FlutterActivity the prompt never appears.
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {

    private val ocrPlugin = OcrPlugin()
    private val widgetPlugin = BudgetWidgetPlugin()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        // applicationContext rather than `this`, so neither plugin outlives a
        // reference to a destroyed Activity.
        ocrPlugin.register(messenger, applicationContext)
        widgetPlugin.register(messenger, applicationContext)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        ocrPlugin.unregister()
        widgetPlugin.unregister()
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
