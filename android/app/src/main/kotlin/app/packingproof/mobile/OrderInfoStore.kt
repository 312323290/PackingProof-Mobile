package app.packingproof.mobile

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONObject

internal class OrderInfoStore(context: Context) : SQLiteOpenHelper(
    context,
    "order_info.db",
    null,
    2,
) {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE order_info (
                tracking_number TEXT PRIMARY KEY,
                payload TEXT NOT NULL,
                push_time INTEGER NOT NULL
            )
            """.trimIndent(),
        )
        db.execSQL("CREATE INDEX idx_order_info_push_time ON order_info(push_time DESC)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // The app has not been released yet. Drop development caches so data
        // previously decoded with the wrong request charset cannot survive.
        db.execSQL("DROP TABLE IF EXISTS order_info")
        onCreate(db)
    }

    @Synchronized
    fun upsert(items: List<OrderInfoRecord>): List<OrderInfoRecord> {
        val stored = mutableListOf<OrderInfoRecord>()
        writableDatabase.beginTransaction()
        try {
            for (incoming in OrderInfoRecord.latestByTrackingNumber(items)) {
                val merged = incoming.mergePreservingConfirmedRefund(lookupInternal(incoming.trackingNumber))
                val values = ContentValues().apply {
                    put("tracking_number", merged.trackingNumber)
                    put("payload", merged.toJson().toString())
                    put("push_time", merged.pushTimeMillis)
                }
                writableDatabase.insertWithOnConflict(
                    "order_info",
                    null,
                    values,
                    SQLiteDatabase.CONFLICT_REPLACE,
                )
                stored += merged
            }
            cleanupInternal()
            writableDatabase.setTransactionSuccessful()
        } finally {
            writableDatabase.endTransaction()
        }
        return stored
    }

    @Synchronized
    fun lookup(trackingNumber: String): OrderInfoRecord? =
        lookupInternal(trackingNumber.trim().uppercase())

    private fun lookupInternal(trackingNumber: String): OrderInfoRecord? {
        readableDatabase.query(
            "order_info",
            arrayOf("payload"),
            "tracking_number = ?",
            arrayOf(trackingNumber),
            null,
            null,
            null,
            "1",
        ).use { cursor ->
            if (!cursor.moveToFirst()) return null
            return decode(cursor.getString(0))
        }
    }

    private fun cleanupInternal() {
        val cutoff = System.currentTimeMillis() - RETENTION_MILLIS
        writableDatabase.delete("order_info", "push_time < ?", arrayOf(cutoff.toString()))
        writableDatabase.execSQL(
            """
            DELETE FROM order_info
            WHERE tracking_number IN (
                SELECT tracking_number FROM order_info
                ORDER BY push_time DESC
                LIMIT -1 OFFSET $MAX_RECORDS
            )
            """.trimIndent(),
        )
    }

    private fun decode(payload: String): OrderInfoRecord? = try {
        val value = JSONObject(payload)
        OrderInfoRecord(
            trackingNumber = value.optString("trackingNumber", "").trim().uppercase(),
            orderId = value.optString("orderId", ""),
            buyerMessage = value.optString("buyerMessage", ""),
            sellerMemo = value.optString("sellerMemo", ""),
            productInfo = value.optString("productInfo", ""),
            hasRefund = value.optBoolean("hasRefund", false),
            isPrintedRefund = value.optBoolean("isPrintedRefund", false),
            refundStatus = value.optString("refundStatus", ""),
            refundProductInfo = value.optString("refundProductInfo", ""),
            pushTimeMillis = value.optLong("pushTimeMilliseconds", 0),
            isTest = value.optBoolean("isTest", false),
        )
    } catch (_: Exception) {
        null
    }

    companion object {
        private const val MAX_RECORDS = 50_000
        private const val RETENTION_MILLIS = 90L * 24 * 60 * 60 * 1000
    }
}
