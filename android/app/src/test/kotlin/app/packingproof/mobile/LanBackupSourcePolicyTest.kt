package app.packingproof.mobile

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Test

class LanBackupSourcePolicyTest {
    @Test
    fun `missing and empty recordings are unavailable`() {
        val root = Files.createTempDirectory("packing-proof-source-test").toFile()
        try {
            val missing = File(root, "missing.mp4")
            val empty = File(root, "empty.mp4").apply { createNewFile() }

            assertEquals(
                LanBackupSourceStatus.MISSING,
                LanBackupSourcePolicy.inspect(missing, -1L, -1L),
            )
            assertEquals(
                LanBackupSourceStatus.EMPTY,
                LanBackupSourcePolicy.inspect(empty, -1L, -1L),
            )
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun `recording replacement is rejected while unchanged source remains available`() {
        val file = Files.createTempFile("packing-proof-source-test", ".mp4").toFile()
        try {
            file.writeBytes(byteArrayOf(1, 2, 3))
            val expectedBytes = file.length()
            val expectedModified = file.lastModified()

            assertEquals(
                LanBackupSourceStatus.AVAILABLE,
                LanBackupSourcePolicy.inspect(file, expectedBytes, expectedModified),
            )
            file.appendBytes(byteArrayOf(4))
            assertEquals(
                LanBackupSourceStatus.REPLACED,
                LanBackupSourcePolicy.inspect(file, expectedBytes, expectedModified),
            )
        } finally {
            file.delete()
        }
    }
}
