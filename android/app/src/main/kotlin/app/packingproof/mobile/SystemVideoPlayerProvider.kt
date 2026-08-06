package app.packingproof.mobile

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.io.File
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * 为系统播放器提供临时只读文件描述符。
 *
 * 录像保存在应用文档目录（/data/user/0/<包名>/app_flutter），不在
 * FileProvider 的标准根目录下，因此用令牌注册表避免暴露任意路径。
 */
class SystemVideoPlayerProvider : ContentProvider() {
    companion object {
        private const val MAX_REGISTERED_FILES = 128
        private val registeredFiles = LinkedHashMap<String, File>()

        @Synchronized
        fun register(file: File): String {
            while (registeredFiles.size >= MAX_REGISTERED_FILES) {
                val oldest = registeredFiles.keys.firstOrNull() ?: break
                registeredFiles.remove(oldest)
            }
            val token = UUID.randomUUID().toString()
            registeredFiles[token] = file
            return token
        }

        @Synchronized
        fun take(token: String): File? = registeredFiles.remove(token)
    }

    override fun onCreate(): Boolean = true

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        val token = uri.lastPathSegment
            ?: throw IllegalArgumentException("无效的录像地址")
        val file = take(token)
            ?: throw IllegalArgumentException("录像文件已过期，请重新打开")
        if (!file.exists()) {
            throw IllegalArgumentException("录像文件不存在")
        }
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun getType(uri: Uri): String? = "video/mp4"

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0
}
