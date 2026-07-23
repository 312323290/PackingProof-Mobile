package app.packingproof.mobile

import android.content.Context
import android.provider.Settings
import android.util.AtomicFile
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.time.Instant
import java.util.UUID

internal class LanBackupStateStore(private val context: Context) {
    companion object {
        private const val PREFS = "lan_backup_connection"
        private const val RETENTION_PREFS = "lan_backup_retention"
        private const val DEVICE_PREFS = "lan_backup_device"
        private const val TAG = "PackingProofBackup"
        private val jobIoLock = Any()

        fun stableId(value: String): String = MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }

        fun stableDeviceId(androidId: String?, packageName: String): String? {
            val normalizedAndroidId = androidId?.trim()?.lowercase().orEmpty()
            if (normalizedAndroidId.isBlank() ||
                normalizedAndroidId == "9774d56d682e549c"
            ) {
                return null
            }
            return "android-${stableId("$packageName:$normalizedAndroidId")}"
        }

        fun <T> withJobLock(action: () -> T): T = synchronized(jobIoLock, action)
    }

    private val jobsDirectory = File(context.filesDir, "lan_backup/jobs").apply { mkdirs() }

    fun saveConnection(baseUrl: String, computerId: String, computerName: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("baseUrl", baseUrl)
            .putString("computerId", computerId)
            .putString("computerName", computerName)
            .putString("lastConnectedAt", Instant.now().toString())
            .apply()
    }

    fun connection(): JSONObject? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val baseUrl = prefs.getString("baseUrl", null) ?: return null
        return JSONObject()
            .put("baseUrl", baseUrl)
            .put("computerId", prefs.getString("computerId", "") ?: "")
            .put("computerName", prefs.getString("computerName", "已连接电脑") ?: "已连接电脑")
            .put("lastConnectedAt", prefs.getString("lastConnectedAt", "") ?: "")
    }

    fun clearConnection() {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
    }

    fun retargetJobs(computerId: String) = withJobLock {
        jobsUnlocked().forEach { job ->
            if (job.optString("destinationComputerId") == computerId) return@forEach
            val file = File(job.optString("filePath"))
            if (!file.exists()) return@forEach
            job.put("destinationComputerId", computerId)
                .put("state", "pending")
                .put("generation", UUID.randomUUID().toString())
                .put("uploadedBytes", 0L)
                .put("backupCompletedAt", JSONObject.NULL)
                .put("contentSha256", JSONObject.NULL)
                .put("remoteRecordIds", JSONArray())
                .put("errorMessage", JSONObject.NULL)
            writeJobUnlocked(job)
        }
    }

    fun upsertJob(filePath: String, sessions: JSONArray): JSONObject = withJobLock {
        val file = File(filePath)
        val id = stableId(file.canonicalPath)
        val existing = readJobUnlocked(id)
        val destinationComputerId = connection()?.optString("computerId").orEmpty()
        if (existing != null &&
            existing.optLong("totalBytes") == file.length() &&
            existing.optLong("lastModified") == file.lastModified() &&
            existing.optString("destinationComputerId") == destinationComputerId
        ) {
            existing.put("filePath", file.absolutePath)
            existing.put("sessions", sessions)
            if (!existing.has("fileCreatedAt")) {
                existing.put("fileCreatedAt", Instant.ofEpochMilli(file.lastModified()).toString())
            }
            if (!existing.has("backupCompletedAt")) existing.put("backupCompletedAt", JSONObject.NULL)
            if (!existing.has("scheduledCleanupAt")) existing.put("scheduledCleanupAt", JSONObject.NULL)
            if (!existing.has("localDeletedAt")) existing.put("localDeletedAt", JSONObject.NULL)
            if (!existing.has("waitingCleanup")) existing.put("waitingCleanup", false)
            if (!existing.has("remoteRecordIds")) existing.put("remoteRecordIds", JSONArray())
            if (!existing.has("contentSha256")) existing.put("contentSha256", JSONObject.NULL)
            if (!existing.has("cleanupReason")) existing.put("cleanupReason", JSONObject.NULL)
            if (existing.optString("generation").isBlank()) {
                existing.put("generation", UUID.randomUUID().toString())
            }
            writeJobUnlocked(existing)
            return@withJobLock existing
        }
        val job = JSONObject()
            .put("id", id)
            .put("generation", UUID.randomUUID().toString())
            .put("filePath", file.absolutePath)
            .put("fileName", file.name)
            .put("destinationComputerId", destinationComputerId)
            .put("state", "pending")
            .put("uploadedBytes", 0L)
            .put("totalBytes", file.length())
            .put("lastModified", file.lastModified())
            .put("fileCreatedAt", Instant.ofEpochMilli(file.lastModified()).toString())
            .put("backupCompletedAt", JSONObject.NULL)
            .put("scheduledCleanupAt", JSONObject.NULL)
            .put("localDeletedAt", JSONObject.NULL)
            .put("waitingCleanup", false)
            .put("remoteRecordIds", JSONArray())
            .put("contentSha256", JSONObject.NULL)
            .put("cleanupReason", JSONObject.NULL)
            .put("errorMessage", JSONObject.NULL)
            .put("sessions", sessions)
        writeJobUnlocked(job)
        job
    }

    fun readJob(id: String): JSONObject? = withJobLock { readJobUnlocked(id) }

    fun writeJob(job: JSONObject) = withJobLock { writeJobUnlocked(job) }

    fun updateJob(
        id: String,
        expectedGeneration: String? = null,
        update: (JSONObject) -> Boolean,
    ): JSONObject? = withJobLock {
        val job = readJobUnlocked(id) ?: return@withJobLock null
        if (expectedGeneration != null && job.optString("generation") != expectedGeneration) {
            return@withJobLock null
        }
        if (!update(job)) return@withJobLock null
        writeJobUnlocked(job)
        JSONObject(job.toString())
    }

    fun jobs(): List<JSONObject> = withJobLock { jobsUnlocked() }

    fun discardUnavailableJobs() = withJobLock {
        jobsUnlocked()
            .filter { it.optString("state") != "completed" }
            .forEach { job ->
                val status = sourceStatus(job)
                if (status == LanBackupSourceStatus.AVAILABLE) return@forEach
                if (deleteJobUnlocked(job.getString("id"), job.optString("generation"))) {
                    Log.w(
                        TAG,
                        "Discard unavailable backup job " +
                            "id=${job.getString("id").take(8)} " +
                            "path=${job.optString("filePath")} reason=${status.reason}",
                    )
                }
            }
    }

    fun discardJobIfUnavailable(id: String): LanBackupSourceStatus? = withJobLock {
        val job = readJobUnlocked(id) ?: return@withJobLock null
        if (job.optString("state") == "completed") {
            return@withJobLock LanBackupSourceStatus.AVAILABLE
        }
        val status = sourceStatus(job)
        if (status == LanBackupSourceStatus.AVAILABLE) return@withJobLock status
        if (deleteJobUnlocked(id, job.optString("generation"))) {
            Log.w(
                TAG,
                "Discard unavailable backup job " +
                    "id=${id.take(8)} path=${job.optString("filePath")} reason=${status.reason}",
            )
        }
        status
    }

    fun deleteJob(id: String, expectedGeneration: String): Boolean = withJobLock {
        deleteJobUnlocked(id, expectedGeneration)
    }

    private fun readJobUnlocked(id: String): JSONObject? {
        val file = File(jobsDirectory, "$id.json")
        return try {
            if (!file.exists() && !File("${file.path}.bak").exists()) return null
            AtomicFile(file).openRead().bufferedReader(Charsets.UTF_8).use { reader ->
                JSONObject(reader.readText())
            }
        } catch (_: Throwable) {
            null
        }
    }

    private fun writeJobUnlocked(job: JSONObject) {
        val target = File(jobsDirectory, "${job.getString("id")}.json")
        val atomicFile = AtomicFile(target)
        var output: FileOutputStream? = null
        try {
            output = atomicFile.startWrite()
            output.write(job.toString().toByteArray(Charsets.UTF_8))
            atomicFile.finishWrite(output)
        } catch (error: Throwable) {
            output?.let(atomicFile::failWrite)
            throw error
        }
    }

    private fun deleteJobUnlocked(id: String, expectedGeneration: String): Boolean {
        val current = readJobUnlocked(id) ?: return false
        if (current.optString("generation") != expectedGeneration) return false
        if (current.optString("state") == "completed") return false
        AtomicFile(File(jobsDirectory, "$id.json")).delete()
        return true
    }

    private fun sourceStatus(job: JSONObject): LanBackupSourceStatus =
        LanBackupSourcePolicy.inspect(
            file = File(job.optString("filePath")),
            expectedBytes = job.optLong("totalBytes", -1L),
            expectedLastModified = job.optLong("lastModified", -1L),
        )

    private fun jobsUnlocked(): List<JSONObject> = jobsDirectory.listFiles { file ->
        file.name.endsWith(".json") || file.name.endsWith(".json.bak")
    }
        ?.map { file -> file.name.removeSuffix(".bak").removeSuffix(".json") }
        ?.distinct()
        ?.mapNotNull(::readJobUnlocked)
        ?.sortedByDescending { it.optLong("lastModified") }
        ?: emptyList()

    fun saveRetentionPolicies(unbackedDays: Int?, backedDays: Int?) {
        context.getSharedPreferences(RETENTION_PREFS, Context.MODE_PRIVATE).edit()
            .putInt("unbackedDays", unbackedDays ?: -1)
            .putInt("backedDays", backedDays ?: -1)
            .apply()
    }

    fun unbackedRetentionDays(): Int = context
        .getSharedPreferences(RETENTION_PREFS, Context.MODE_PRIVATE)
        .getInt("unbackedDays", 30)

    fun backedRetentionDays(): Int = context
        .getSharedPreferences(RETENTION_PREFS, Context.MODE_PRIVATE)
        .getInt("backedDays", 7)

    fun deviceId(): String {
        val androidId = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ANDROID_ID,
        )
        stableDeviceId(androidId, context.packageName)?.let { return it }

        // Only obsolete or unavailable Android IDs use an installation-local
        // fallback. Normal devices keep the same ID after uninstall/reinstall.
        val prefs = context.getSharedPreferences(DEVICE_PREFS, Context.MODE_PRIVATE)
        prefs.getString("id", null)?.takeIf { it.isNotBlank() }?.let { return it }
        val value = UUID.randomUUID().toString()
        prefs.edit().putString("id", value).apply()
        return value
    }

    fun deviceName(): String = android.os.Build.MODEL?.trim().orEmpty().ifBlank { "打包手机" }
}
