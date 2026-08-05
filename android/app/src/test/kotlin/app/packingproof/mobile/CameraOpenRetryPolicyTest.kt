package app.packingproof.mobile

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CameraOpenRetryPolicyTest {
    @Test
    fun `camera in use and service disconnects are transient`() {
        assertTrue(CameraOpenRetryPolicy.isTransientStateError(1))
        assertTrue(CameraOpenRetryPolicy.isTransientStateError(2))
        assertTrue(CameraOpenRetryPolicy.isTransientStateError(3))
        assertTrue(CameraOpenRetryPolicy.isTransientStateError(4))
        assertTrue(CameraOpenRetryPolicy.isTransientStateError(6))
    }

    @Test
    fun `fatal device errors are not retried`() {
        assertFalse(CameraOpenRetryPolicy.isTransientStateError(5))
        assertFalse(CameraOpenRetryPolicy.isTransientStateError(0))
        assertFalse(CameraOpenRetryPolicy.isTransientStateError(-1))
    }

    @Test
    fun `retry budget is bounded`() {
        assertEquals(3, CameraOpenRetryPolicy.MAX_ATTEMPTS)
        assertTrue(CameraOpenRetryPolicy.RETRY_DELAY_MS > 0)
    }
}
