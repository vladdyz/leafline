package com.vzolotukhin.receipt_tracker.ocr

/**
 * Builds the maps sent across the channel.
 *
 * Deliberately free of Android and ML Kit types. That is what makes it
 * testable as a plain JVM unit test — no Robolectric, no `android.jar` stubs
 * throwing "not mocked", no emulator. `ReceiptTextMapper` holds the part that
 * does touch those types, and holds nothing else.
 *
 * The split exists because this is where the fiddly decisions live: what
 * counts as empty, what a negative bounding box means, what the Dart side is
 * entitled to assume about the numbers it receives.
 */
object ReceiptBlocks {

    /**
     * One recognised line, as the channel contract describes it.
     *
     * Returns null for text worth dropping, which the caller filters out.
     * Blank lines are common — a recogniser will happily report whitespace
     * between columns — and an empty block costs the extractor a pass over
     * nothing.
     *
     * Bounding boxes arrive as left/top/right/bottom; the contract is
     * left/top/width/height. Widths are clamped at zero rather than allowed
     * to go negative: a malformed box should cost a line its position bonus,
     * not corrupt the geometry every other line is measured against.
     */
    fun block(
        text: String,
        left: Int,
        top: Int,
        right: Int,
        bottom: Int,
    ): Map<String, Any>? {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return null

        return mapOf(
            "text" to trimmed,
            "left" to left,
            "top" to top,
            "width" to maxOf(right - left, 0),
            "height" to maxOf(bottom - top, 0),
        )
    }
}
