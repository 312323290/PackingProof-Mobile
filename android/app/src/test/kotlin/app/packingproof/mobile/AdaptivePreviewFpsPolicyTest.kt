package app.packingproof.mobile

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AdaptivePreviewFpsPolicyTest {
    @Test
    fun `stable device drops to 15 fps after four seconds`() {
        val policy = AdaptivePreviewFpsPolicy()
        policy.activate(1_000L)

        assertFalse(policy.observe(0.01f, 4_999L))
        assertTrue(policy.observe(0.01f, 5_000L))
        assertEquals(15, policy.targetFps)
    }

    @Test
    fun `motion immediately restores 30 fps`() {
        val policy = AdaptivePreviewFpsPolicy()
        policy.activate(0L)
        policy.observe(0.01f, 4_000L)

        assertTrue(policy.observe(0.15f, 4_020L))
        assertEquals(30, policy.targetFps)
    }

    @Test
    fun `leaving preview lowers fps without waiting`() {
        val policy = AdaptivePreviewFpsPolicy()

        assertTrue(policy.deactivate())
        assertEquals(15, policy.targetFps)
    }
}
