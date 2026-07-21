package app.packingproof.mobile

import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class OrderInfoRecordTest {
    @Test
    fun sameOrderKeepsPreviouslyConfirmedRefundWhenIncomingPayloadIsIncomplete() {
        val previous = record(orderId = "ORDER-1", isPrintedRefund = true, refundStatus = "SUCCESS")
        val merged = record(orderId = "ORDER-1").mergePreservingConfirmedRefund(previous)

        assertTrue(merged.hasRefund)
        assertTrue(merged.isPrintedRefund)
    }

    @Test
    fun reusedTrackingNumberUsesNewOrderRefundState() {
        val previous = record(orderId = "ORDER-OLD", isPrintedRefund = true, refundStatus = "SUCCESS")
        val merged = record(orderId = "ORDER-NEW").mergePreservingConfirmedRefund(previous)

        assertFalse(merged.hasRefund)
        assertFalse(merged.isPrintedRefund)
    }

    @Test
    fun duplicateTrackingNumbersKeepFirstLatestOrder() {
        val latest = record(orderId = "ORDER-NEW")
        val older = record(orderId = "ORDER-OLD", isPrintedRefund = true)

        val result = OrderInfoRecord.latestByTrackingNumber(listOf(latest, older))

        assertEquals(1, result.size)
        assertEquals("ORDER-NEW", result.single().orderId)
        assertFalse(result.single().isPrintedRefund)
    }

    private fun record(
        orderId: String,
        isPrintedRefund: Boolean = false,
        refundStatus: String = "",
    ) = OrderInfoRecord(
        trackingNumber = "TRACK-1",
        orderId = orderId,
        buyerMessage = "",
        sellerMemo = "",
        productInfo = "",
        hasRefund = isPrintedRefund,
        isPrintedRefund = isPrintedRefund,
        refundStatus = refundStatus,
        refundProductInfo = "",
        pushTimeMillis = 1L,
    )
}
