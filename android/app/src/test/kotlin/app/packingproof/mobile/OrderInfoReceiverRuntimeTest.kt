package app.packingproof.mobile

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OrderInfoReceiverRuntimeTest {
    @Test
    fun privateAddressValidationAcceptsLanAndRejectsPublicIpv4() {
        assertTrue(OrderInfoReceiverRuntime.isPrivateAddress("192.168.1.20"))
        assertTrue(OrderInfoReceiverRuntime.isPrivateAddress("10.0.0.2"))
        assertTrue(OrderInfoReceiverRuntime.isPrivateAddress("172.31.2.3"))
        assertTrue(OrderInfoReceiverRuntime.isPrivateAddress("169.254.1.2"))
        assertFalse(OrderInfoReceiverRuntime.isPrivateAddress("8.8.8.8"))
        assertFalse(OrderInfoReceiverRuntime.isPrivateAddress("172.32.0.1"))
        assertFalse(OrderInfoReceiverRuntime.isPrivateAddress("not-an-ip"))
    }
}
