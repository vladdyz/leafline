package com.vzolotukhin.receipt_tracker.ocr

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Text recognition over a MethodChannel.
 *
 * PHASE 0: this is a stub. It validates the file path and then returns a
 * hardcoded list of text blocks without calling ML Kit at all.
 *
 * That is deliberate. The channel and the recognition library are two
 * separate things that can each go wrong, and debugging them together is
 * considerably harder than debugging them apart. Get this stub returning
 * its fake blocks to Dart first. Once that round trip works, swapping the
 * body of [recognize] for a real ML Kit call is a contained change, and any
 * breakage afterwards is unambiguously ML Kit's.
 *
 * Register from MainActivity:
 *
 *     override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
 *         super.configureFlutterEngine(flutterEngine)
 *         OcrPlugin().register(flutterEngine.dartExecutor.binaryMessenger)
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
        const val CHANNEL = "com.example.receipt_tracker/ocr"

        const val ERROR_FILE_NOT_FOUND = "FILE_NOT_FOUND"
        const val ERROR_DECODE_FAILED = "DECODE_FAILED"
        const val ERROR_RECOGNITION_FAILED = "RECOGNITION_FAILED"
    }

    private var channel: MethodChannel? = null

    fun register(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    fun unregister() {
        channel?.setMethodCallHandler(null)
        channel = null
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
     * PHASE 3 replaces this body with:
     *
     *     val image = InputImage.fromFilePath(context, Uri.fromFile(file))
     *     TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
     *         .process(image)
     *         .addOnSuccessListener { text -> result.success(ReceiptTextMapper.toBlocks(text)) }
     *         .addOnFailureListener { e -> result.error(ERROR_RECOGNITION_FAILED, e.message, null) }
     *
     * Note that ML Kit resolves on a background thread. Every path through
     * the listeners must call result.success or result.error exactly once —
     * a channel that never replies leaves the Dart future pending forever,
     * which presents as a spinner that never stops and no error anywhere.
     */
    private fun recognize(path: String, result: MethodChannel.Result) {
        val file = File(path)
        if (!file.exists()) {
            result.error(ERROR_FILE_NOT_FOUND, "No file at $path", null)
            return
        }

        result.success(STUB_BLOCKS)
    }
}

/**
 * Fake recognition output shaped like a real corner-store receipt, including
 * the decoys the extractor has to rank below the true total: a subtotal, tax
 * lines, and a cash-tendered amount larger than the total itself.
 */
private val STUB_BLOCKS: List<Map<String, Any>> = listOf(
    block("CORNER MARKET", 40, 30, 300, 40),
    block("123 QUEEN ST W", 40, 80, 280, 30),
    block("COFFEE LARGE      2.75", 40, 150, 400, 30),
    block("BAGEL             3.50", 40, 190, 400, 30),
    block("SUBTOTAL          6.25", 40, 260, 400, 30),
    block("HST 13%           0.81", 40, 300, 400, 30),
    block("TOTAL             7.06", 40, 350, 400, 34),
    block("CASH             10.00", 40, 400, 400, 30),
    block("CHANGE            2.94", 40, 440, 400, 30),
)

private fun block(
    text: String,
    left: Int,
    top: Int,
    width: Int,
    height: Int,
): Map<String, Any> = mapOf(
    "text" to text,
    "left" to left,
    "top" to top,
    "width" to width,
    "height" to height,
)
