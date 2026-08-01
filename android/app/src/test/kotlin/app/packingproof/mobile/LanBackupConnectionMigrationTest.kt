package app.packingproof.mobile

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LanBackupConnectionMigrationTest {
    @Test
    fun `legacy connection is cleared while host identity remains a reconnect hint`() {
        val migration = planLanBackupConnectionMigration(
            schemaVersion = 0,
            computerId = " host-1 ",
            computerName = " 仓库电脑 ",
        )

        assertEquals("host-1", migration?.computerId)
        assertEquals("仓库电脑", migration?.computerName)
    }

    @Test
    fun `current device token connection is not migrated again`() {
        assertNull(
            planLanBackupConnectionMigration(
                schemaVersion = 1,
                computerId = "host-1",
                computerName = "仓库电脑",
            ),
        )
    }
}
