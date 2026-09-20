package com.vzolotukhin.receipt_tracker.ocr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The first Kotlin tests in this project.
 *
 * `:app:testDebugUnitTest` has been wired into CI since Phase 0 and passing
 * trivially, because there was nothing to run. There is now.
 *
 * These are plain JVM tests — no Robolectric, no emulator, no `android.jar`
 * stubs. That is the entire reason `ReceiptBlocks` holds no Android types.
 */
class ReceiptBlocksTest {

    @Test
    fun `builds a block from a bounding box`() {
        val block = ReceiptBlocks.block("TOTAL 7.06", 40, 350, 440, 384)

        assertEquals("TOTAL 7.06", block!!["text"])
        assertEquals(40, block["left"])
        assertEquals(350, block["top"])
        assertEquals(400, block["width"])
        assertEquals(34, block["height"])
    }

    @Test
    fun `converts right and bottom into width and height`() {
        // The contract is left/top/width/height; ML Kit gives a Rect.
        val block = ReceiptBlocks.block("x", 10, 20, 110, 70)
        assertEquals(100, block!!["width"])
        assertEquals(50, block["height"])
    }

    @Test
    fun `trims surrounding whitespace`() {
        val block = ReceiptBlocks.block("   TOTAL 7.06  ", 0, 0, 10, 10)
        assertEquals("TOTAL 7.06", block!!["text"])
    }

    @Test
    fun `keeps whitespace inside the line`() {
        // The gap between label and amount is what the extractor reads as one
        // line; collapsing it would change nothing it looks for, but there is
        // no reason to alter what was recognised.
        val block = ReceiptBlocks.block("TOTAL     7.06", 0, 0, 10, 10)
        assertEquals("TOTAL     7.06", block!!["text"])
    }

    @Test
    fun `drops an empty line`() {
        assertNull(ReceiptBlocks.block("", 0, 0, 10, 10))
    }

    @Test
    fun `drops a whitespace-only line`() {
        // Recognisers report these between columns. An empty block costs the
        // extractor a pass over nothing.
        assertNull(ReceiptBlocks.block("   \t  ", 0, 0, 10, 10))
    }

    @Test
    fun `clamps a negative width to zero`() {
        // A malformed box should cost one line its position bonus, not corrupt
        // the geometry every other line is measured against.
        val block = ReceiptBlocks.block("x", 100, 0, 40, 10)
        assertEquals(0, block!!["width"])
    }

    @Test
    fun `clamps a negative height to zero`() {
        val block = ReceiptBlocks.block("x", 0, 100, 10, 40)
        assertEquals(0, block!!["height"])
    }

    @Test
    fun `a zero-size box is still a block`() {
        // Text with no geometry is worth sending; it loses its position bonus
        // in the extractor and nothing else.
        val block = ReceiptBlocks.block("TOTAL 7.06", 0, 0, 0, 0)
        assertEquals("TOTAL 7.06", block!!["text"])
        assertEquals(0, block["width"])
    }

    @Test
    fun `emits exactly the five keys the channel contract names`() {
        val block = ReceiptBlocks.block("x", 1, 2, 3, 4)
        assertEquals(
            setOf("text", "left", "top", "width", "height"),
            block!!.keys,
        )
    }
}
