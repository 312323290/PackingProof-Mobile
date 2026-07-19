package app.packingproof.mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.ServiceInfo
import android.media.MediaExtractor
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import org.json.JSONObject
import org.json.JSONArray
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.security.MessageDigest
import kotlin.math.min

internal class LanBackupWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {
    companion object {
        private const val CHANNEL_ID = "packing_proof_backup"
        private const val DEFAULT_CHUNK_SIZE = 4 * 1024 * 1024
        private const val TAG = "PackingProofBackup"
    }

    private val store = LanBackupStateStore(appContext)
    private val credentials = LanBackupCredentialStore(appContext)

    override suspend fun doWork(): Result {
        val id = inputData.getString("jobId") ?: return Result.failure()
        val job = store.readJob(id) ?: return Result.failure()
        val file = File(job.optString("filePath"))
        val connection = store.connection()
        val accessKey = credentials.load()
        if (!file.exists()) return fail(job, "录像文件不存在")
        if (connection == null || accessKey.isNullOrBlank()) return fail(job, "请重新连接电脑")
        if (job.optString("destinationComputerId") != connection.optString("computerId")) {
            return Result.failure()
        }

        return try {
            Log.i(TAG, "Backup started id=${id.take(8)} file=${file.name} bytes=${file.length()}")
            setForeground(foreground(job, 0))
            job.put("state", "uploading").put("errorMessage", JSONObject.NULL)
            store.writeJob(job)

            val sha256 = file.sha256()
            val baseUrl = connection.getString("baseUrl").trimEnd('/')
            val createResponse = postJson(
                "$baseUrl/api/mobile-backup/uploads",
                accessKey,
                JSONObject()
                    .put("fileSha256", sha256)
                    .put("totalBytes", file.length())
                    .put("mimeType", "video/mp4"),
            )
            Log.i(TAG, "Upload session ready id=${id.take(8)}")
            val uploadId = createResponse.getString("uploadId")
            val encodedUploadId = URLEncoder.encode(uploadId, Charsets.UTF_8.name())
            var offset = createResponse.optLong("offset", 0L).coerceIn(0L, file.length())
            val chunkSize = createResponse.optInt("chunkSize", DEFAULT_CHUNK_SIZE)
                .coerceIn(256 * 1024, 8 * 1024 * 1024)

            RandomAccessFile(file, "r").use { input ->
                while (offset < file.length()) {
                    if (isStopped) {
                        job.put("state", "paused")
                        store.writeJob(job)
                        return Result.failure()
                    }
                    val size = min(chunkSize.toLong(), file.length() - offset).toInt()
                    val bytes = ByteArray(size)
                    input.seek(offset)
                    input.readFully(bytes)
                    val nextOffset = putChunk(
                        "$baseUrl/api/mobile-backup/uploads/$encodedUploadId/chunks",
                        accessKey,
                        bytes,
                        offset,
                        file.length(),
                    )
                    offset = nextOffset.coerceIn(offset + size, file.length())
                    Log.d(TAG, "Chunk accepted id=${id.take(8)} offset=$offset total=${file.length()}")
                    job.put("uploadedBytes", offset)
                    store.writeJob(job)
                    setForeground(foreground(job, ((offset * 100) / file.length()).toInt()))
                }
            }
            val completion = postJson(
                "$baseUrl/api/mobile-backup/uploads/$encodedUploadId/complete",
                accessKey,
                JSONObject()
                    .put("fileSha256", sha256)
                    .put("sourceDeviceId", store.deviceId())
                    .put("sourceDeviceName", store.deviceName())
                    .put("sessions", completionSessions(job.getJSONArray("sessions"))),
            )
            if (completion.optString("status") != "verified" ||
                completion.optString("fileSha256") != sha256
            ) {
                return fail(job, "电脑未确认录像校验结果")
            }
            complete(job, file.length(), completion.optJSONArray("recordIds") ?: JSONArray())
        } catch (error: BackupHttpException) {
            Log.w(TAG, "Backup HTTP failure id=${id.take(8)} status=${error.statusCode}", error)
            if (error.statusCode == 401 || error.statusCode == 403 || error.statusCode == 404) {
                fail(job, error.message ?: "电脑拒绝备份")
            } else {
                pauseForRetry(job, error.message ?: "电脑暂时不可用")
            }
        } catch (error: IOException) {
            Log.w(TAG, "Backup network failure id=${id.take(8)}", error)
            pauseForRetry(job, "网络中断，等待自动续传")
        } catch (error: Throwable) {
            Log.e(TAG, "Backup failed id=${id.take(8)}", error)
            fail(job, error.message ?: "备份失败")
        }
    }

    private fun complete(job: JSONObject, total: Long, recordIds: JSONArray): Result {
        job.put("state", "completed")
            .put("uploadedBytes", total)
            .put("backupCompletedAt", java.time.Instant.now().toString())
            .put("remoteRecordIds", recordIds)
            .put("errorMessage", JSONObject.NULL)
        store.writeJob(job)
        LanBackupCleanupScheduler.reschedule(applicationContext, store, job)
        return Result.success()
    }

    private fun completionSessions(sessions: JSONArray): JSONArray {
        val result = JSONArray()
        for (index in 0 until sessions.length()) {
            val source = sessions.getJSONObject(index)
            val duration = (source.optLong("mediaEndMs") - source.optLong("mediaStartMs"))
                .takeIf { it > 0 }
                ?: runCatching {
                    java.time.Duration.between(
                        java.time.Instant.parse(source.getString("startedAt")),
                        java.time.Instant.parse(source.getString("endedAt")),
                    ).toMillis()
                }.getOrDefault(1L)
            result.put(
                JSONObject()
                    .put("sessionId", source.getString("id"))
                    .put("trackingNumber", source.optString("trackingNumber"))
                    .put("startedAt", source.getString("startedAt"))
                    .put("durationMilliseconds", duration.coerceAtLeast(1L)),
            )
        }
        return result
    }

    private fun fail(job: JSONObject, message: String): Result {
        job.put("state", "failed").put("errorMessage", message)
        store.writeJob(job)
        return Result.failure()
    }

    private fun pauseForRetry(job: JSONObject, message: String): Result {
        job.put("state", "paused").put("errorMessage", message)
        store.writeJob(job)
        return Result.retry()
    }

    private fun postJson(url: String, key: String, body: JSONObject): JSONObject {
        val connection = open(url, "POST", key)
        connection.setRequestProperty("Content-Type", "application/json; charset=utf-8")
        connection.doOutput = true
        connection.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
        return readJson(connection)
    }

    private fun putChunk(
        url: String,
        key: String,
        bytes: ByteArray,
        offset: Long,
        total: Long,
    ): Long {
        val connection = open(url, "PUT", key)
        connection.setRequestProperty("Content-Type", "application/octet-stream")
        connection.setRequestProperty("Content-Range", "bytes $offset-${offset + bytes.size - 1}/$total")
        connection.setRequestProperty("X-Chunk-SHA256", bytes.sha256())
        connection.setFixedLengthStreamingMode(bytes.size)
        connection.doOutput = true
        connection.outputStream.use { it.write(bytes) }
        return readJson(connection).getLong("offset")
    }

    private fun open(url: String, method: String, key: String): HttpURLConnection =
        (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = 10_000
            readTimeout = 30_000
            useCaches = false
            instanceFollowRedirects = false
            setRequestProperty("X-EPM-Access-Key", key)
        }

    private fun readJson(connection: HttpURLConnection): JSONObject {
        val status = connection.responseCode
        val stream = if (status in 200..299) connection.inputStream else connection.errorStream
        val body = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
        if (status !in 200..299) throw BackupHttpException(status, body.ifBlank { "HTTP $status" })
        return if (body.isBlank()) JSONObject() else JSONObject(body)
    }

    private fun foreground(job: JSONObject, progress: Int): ForegroundInfo {
        val manager = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "录像备份", NotificationManager.IMPORTANCE_LOW),
            )
        }
        val notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setSmallIcon(applicationContext.applicationInfo.icon)
            .setContentTitle("正在备份录像")
            .setContentText(job.optString("fileName"))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(100, progress.coerceIn(0, 100), false)
            .build()
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(
                job.getString("id").take(8).hashCode(),
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            ForegroundInfo(job.getString("id").take(8).hashCode(), notification)
        }
    }
}

private class BackupHttpException(val statusCode: Int, message: String) : IOException(message)

private fun File.sha256(): String {
    val digest = MessageDigest.getInstance("SHA-256")
    inputStream().use { input ->
        val buffer = ByteArray(1024 * 1024)
        while (true) {
            val count = input.read(buffer)
            if (count <= 0) break
            digest.update(buffer, 0, count)
        }
    }
    return digest.digest().joinToString("") { "%02x".format(it) }
}

private fun ByteArray.sha256(): String = MessageDigest.getInstance("SHA-256")
    .digest(this)
    .joinToString("") { "%02x".format(it) }

private fun File.videoCodec(): String {
    val extractor = MediaExtractor()
    return try {
        extractor.setDataSource(path)
        for (index in 0 until extractor.trackCount) {
            val mime = extractor.getTrackFormat(index)
                .getString(android.media.MediaFormat.KEY_MIME)
                .orEmpty()
            if (mime.startsWith("video/")) {
                return if (mime == "video/hevc") "h265" else "h264"
            }
        }
        "h265"
    } finally {
        extractor.release()
    }
}
