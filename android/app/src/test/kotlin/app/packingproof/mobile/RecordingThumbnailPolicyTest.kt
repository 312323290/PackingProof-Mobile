package app.packingproof.mobile

import org.junit.Assert.assertEquals
import org.junit.Test

class RecordingThumbnailPolicyTest {
    @Test
    fun `thumbnail uses frame at eighty percent`() {
        assertEquals(8_000L, RecordingThumbnailPolicy.frameTimeMs(10_000L))
        assertEquals(48_000L, RecordingThumbnailPolicy.frameTimeMs(60_000L))
        assertEquals(800L, RecordingThumbnailPolicy.frameTimeMs(1_000L))
    }

    @Test
    fun `thumbnail stays inside very short video`() {
        assertEquals(0L, RecordingThumbnailPolicy.frameTimeMs(1L))
    }
}
