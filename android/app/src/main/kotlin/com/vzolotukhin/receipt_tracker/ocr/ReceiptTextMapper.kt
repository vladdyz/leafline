package com.vzolotukhin.receipt_tracker.ocr

import com.google.mlkit.vision.text.Text

/**
 * Turns ML Kit's result into channel maps.
 *
 * Everything Android-flavoured is here so that [ReceiptBlocks] can stay a
 * plain JVM object with tests that need no emulator.
 */
object ReceiptTextMapper {

    /**
     * Flattens to **lines**, not blocks.
     *
     * ML Kit's `TextBlock` is a paragraph — a contiguous run of lines — while
     * a `Line` is words sharing a baseline. A receipt's `TOTAL   7.06` is one
     * line and usually one block, but a wide gap can split it across blocks,
     * and on a two-column receipt a block may span several rows at once.
     *
     * Lines are the closest thing to what the Dart side expects. Where ML Kit
     * still splits a label from its amount, `groupIntoLines` in Dart rejoins
     * them by vertical overlap — so this can be generous and let the Dart
     * side tidy up.
     */
    fun toBlocks(text: Text): List<Map<String, Any>> {
        return text.textBlocks
            .flatMap { it.lines }
            .mapNotNull { line ->
                val box = line.boundingBox
                if (box == null) {
                    // Text with no geometry is still worth sending. It loses
                    // its position bonus in the extractor, nothing more.
                    ReceiptBlocks.block(line.text, 0, 0, 0, 0)
                } else {
                    ReceiptBlocks.block(
                        line.text,
                        box.left,
                        box.top,
                        box.right,
                        box.bottom,
                    )
                }
            }
    }
}
