package app.packingproof.mobile

import java.io.File

internal enum class LanBackupSourceStatus(val reason: String) {
    AVAILABLE(""),
    MISSING("录像文件不存在"),
    EMPTY("录像文件为空"),
    REPLACED("录像文件已被替换"),
    UNREADABLE("录像文件无法读取"),
}

internal object LanBackupSourcePolicy {
    fun inspect(
        file: File,
        expectedBytes: Long,
        expectedLastModified: Long,
    ): LanBackupSourceStatus {
        if (!file.isFile) return LanBackupSourceStatus.MISSING
        val actualBytes = file.length()
        if (actualBytes <= 0L) return LanBackupSourceStatus.EMPTY
        if ((expectedBytes > 0L && actualBytes != expectedBytes) ||
            (expectedLastModified > 0L && file.lastModified() != expectedLastModified)
        ) {
            return LanBackupSourceStatus.REPLACED
        }
        return LanBackupSourceStatus.AVAILABLE
    }
}
