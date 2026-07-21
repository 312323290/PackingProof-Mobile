package app.packingproof.mobile

import org.json.JSONObject

internal data class OrderInfoRecord(
    val trackingNumber: String,
    val orderId: String,
    val buyerMessage: String,
    val sellerMemo: String,
    val productInfo: String,
    val hasRefund: Boolean,
    val isPrintedRefund: Boolean,
    val refundStatus: String,
    val refundProductInfo: String,
    val pushTimeMillis: Long,
    val isTest: Boolean = false,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("trackingNumber", trackingNumber)
        .put("orderId", orderId)
        .put("buyerMessage", buyerMessage)
        .put("sellerMemo", sellerMemo)
        .put("productInfo", productInfo)
        .put("hasRefund", hasRefund)
        .put("isPrintedRefund", isPrintedRefund)
        .put("refundStatus", refundStatus)
        .put("refundProductInfo", refundProductInfo)
        .put("pushTimeMilliseconds", pushTimeMillis)
        .put("isTest", isTest)

    fun toMap(): Map<String, Any> = mapOf(
        "trackingNumber" to trackingNumber,
        "orderId" to orderId,
        "buyerMessage" to buyerMessage,
        "sellerMemo" to sellerMemo,
        "productInfo" to productInfo,
        "hasRefund" to hasRefund,
        "isPrintedRefund" to isPrintedRefund,
        "refundStatus" to refundStatus,
        "refundProductInfo" to refundProductInfo,
        "pushTimeMilliseconds" to pushTimeMillis,
        "isTest" to isTest,
    )

    fun mergePreservingConfirmedRefund(previous: OrderInfoRecord?): OrderInfoRecord {
        val sameOrder = previous != null &&
            (orderId.isBlank() || previous.orderId.isBlank() || orderId == previous.orderId)
        if (!sameOrder || !previous.isPrintedRefund || isPrintedRefund) return this
        return copy(
            hasRefund = true,
            isPrintedRefund = true,
            refundStatus = refundStatus.ifBlank { previous.refundStatus },
            refundProductInfo = refundProductInfo.ifBlank { previous.refundProductInfo },
        )
    }

    companion object {
        fun latestByTrackingNumber(items: List<OrderInfoRecord>): List<OrderInfoRecord> {
            val seen = mutableSetOf<String>()
            return items.filter { item ->
                item.trackingNumber.isNotBlank() && seen.add(item.trackingNumber)
            }
        }

        fun fromJson(value: JSONObject, nowMillis: Long = System.currentTimeMillis()): OrderInfoRecord {
            fun text(name: String, maxLength: Int): String {
                val result = value.optString(name, "")
                require(result.length <= maxLength) { fieldError(name, maxLength) }
                return result
            }
            return OrderInfoRecord(
                trackingNumber = text("trackingNumber", 128).trim().uppercase(),
                orderId = text("orderId", 128),
                buyerMessage = text("buyerMessage", 2000),
                sellerMemo = text("sellerMemo", 2000),
                productInfo = text("productInfo", 4000),
                hasRefund = value.optBoolean("hasRefund", false),
                isPrintedRefund = value.optBoolean("isPrintedRefund", false),
                refundStatus = text("refundStatus", 256),
                refundProductInfo = text("refundProductInfo", 4000),
                pushTimeMillis = nowMillis,
                isTest = value.optBoolean("isTest", false),
            )
        }

        private fun fieldError(name: String, maxLength: Int): String = when (name) {
            "trackingNumber" -> "快递单号过长，最多允许 $maxLength 个字符"
            "orderId" -> "订单号过长，最多允许 $maxLength 个字符"
            "buyerMessage" -> "买家留言过长，最多允许 $maxLength 个字符"
            "sellerMemo" -> "卖家备注过长，最多允许 $maxLength 个字符"
            "productInfo" -> "商品信息过长，最多允许 $maxLength 个字符"
            "refundStatus" -> "退款状态过长，最多允许 $maxLength 个字符"
            else -> "退款商品信息过长，最多允许 $maxLength 个字符"
        }
    }
}
