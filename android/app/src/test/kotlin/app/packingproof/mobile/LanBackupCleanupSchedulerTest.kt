package app.packingproof.mobile

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LanBackupCleanupSchedulerTest {
    @Test
    fun jsonNullIsNotTreatedAsDeletedTimestamp() {
        assertNull(LanBackupCleanupScheduler.normalizeNullableText(null))
        assertNull(LanBackupCleanupScheduler.normalizeNullableText("null"))
    }

    @Test
    fun realTimestampRemainsAvailable() {
        val value = "2026-07-20T03:21:56Z"
        assertEquals(value, LanBackupCleanupScheduler.normalizeNullableText(value))
    }
}
