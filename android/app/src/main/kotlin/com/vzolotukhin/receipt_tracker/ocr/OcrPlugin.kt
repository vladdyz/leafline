package com.vzolotukhin.receipt_tracker.ocr

import android.content.Context
import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

/**
 * Text recognition over a MethodChannel, backed by ML Kit.
 *
 * Kotlin recognises text and returns it with its geometry. It makes no
 * judgement about what any of it means — ranking the amounts happens in Dart,
 * in `TotalExtractor`, where it can be unit tested against fixture strings
 * without a device. See decision 0003.
 *
 * Registered from MainActivity:
 *
 *     override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
 *         super.configureFlutterEngine(flutterEngine)
 *         ocrPlugin.register(
 *             flutterEngine.dartExecutor.binaryMessenger,
 *             applicationContext,
 *         )
 *     }
 *
 * Channel contract, documented on both sides of the boundary:
 *
 *   method:   "recognizeText"
 *   argument: { "path": String }
 *   success:  List<Map<String, Any>> with keys text, left, top, width, height
 *   errors:   FILE_NOT_FOUND, DECODE_FAILED, RECOGNITION_FAILED
 */
class OcrPlugin : MethodChannel.MethodCallHandler {

    companion object {
        /**
         * Deliberately not derived from the package name; see decision 0015.
         * This string appears verbatim in `channel_ocr_service.dart`.
         */
        const val CHANNEL = "receipt_tracker/ocr"

        const val ERROR_FILE_NOT_FOUND = "FILE_NOT_FOUND"
        const val ERROR_DECODE_FAILED = "DECODE_FAILED"
        const val ERROR_RECOGNITION_FAILED = "RECOGNITION_FAILED"
    }

    private var channel: MethodChannel? = null
    private var appContext: Context? = null
    private var recognizer: TextRecognizer? = null

    fun register(messenger: BinaryMessenger, context: Context) {
        appContext = context.applicationContext
        recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        channel = MethodChannel(messenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    fun unregister() {
        channel?.setMethodCallHandler(null)
        channel = null
        recognizer?.close()
        recognizer = null
        appContext = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "recognizeText" -> {
                val path = call.argument<String>("path")
                if (path.isNullOrBlank()) {
                    result.error(ERROR_FILE_NOT_FOUND, "No path supplied", null)
                    return
                }
                recognize(path, result)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Every path through this method ends in exactly one `result.success` or
     * `result.error`.
     *
     * That is the rule worth holding onto. A channel that never replies
     * leaves the Dart future pending forever, which presents as a spinner
     * that never stops and no error anywhere — the hardest possible failure
     * to diagnose from the Flutter side.
     */
    private fun recognize(path: String, result: MethodChannel.Result) {
        val context = appContext
        val client = recognizer
        if (context == null || client == null) {
            result.error(ERROR_RECOGNITION_FAILED, "Plugin is not registered", null)
            return
        }

        val file = File(path)
        if (!file.exists()) {
            result.error(ERROR_FILE_NOT_FOUND, "No file at $path", null)
            return
        }

        val image = try {
            // fromFilePath rather than decoding a Bitmap by hand: it reads the
            // EXIF orientation and rotates accordingly. A phone photo taken
            // in portrait is very often stored landscape with a rotation flag,
            // and text recognition on a sideways receipt finds nothing.
            InputImage.fromFilePath(context, Uri.fromFile(file))
        } catch (error: IOException) {
            result.error(ERROR_DECODE_FAILED, error.message, null)
            return
        }

        // No Executor is passed, so both listeners run on the main thread —
        // which is where a MethodChannel result has to be delivered from.
        client.process(image)
            .addOnSuccessListener { text ->
                result.success(ReceiptTextMapper.toBlocks(text))
            }
            .addOnFailureListener { error ->
                result.error(ERROR_RECOGNITION_FAILED, error.message, null)
            }
    }
}
