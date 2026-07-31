package app.packingproof.mobile

import org.junit.Assert.assertEquals
import org.junit.Test

class RecordingThumbnailPolicyTest {
    @Test
    fun `thumbnail uses frame at fifty percent`() {
        assertEquals(5_000L, RecordingThumbnailPolicy.frameTimeMs(10_000L))
        assertEquals(30_000L, RecordingThumbnailPolicy.frameTimeMs(60_000L))
        assertEquals(500L, RecordingThumbnailPolicy.frameTimeMs(1_000L))
    }

    @Test
    fun `thumbnail stays inside very short video`() {
        assertEquals(0L, RecordingThumbnailPolicy.frameTimeMs(1L))
    }
}
