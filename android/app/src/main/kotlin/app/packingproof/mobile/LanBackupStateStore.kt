package app.packingproof.mobile

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.time.Instant
import java.util.UUID

internal class LanBackupStateStore(private val context: Context) {
    companion object {
        private const val PREFS = "lan_backup_connection"
        private const val RETENTION_PREFS = "lan_backup_retention"
        private const val DEVICE_PREFS = "lan_backup_device"

        fun stableId(value: String): String = MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
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

    fun retargetJobs(computerId: String) {
        jobs().forEach { job ->
            if (job.optString("destinationComputerId") == computerId) return@forEach
            val file = File(job.optString("filePath"))
            if (!file.exists()) return@forEach
            job.put("destinationComputerId", computerId)
                .put("state", "pending")
                .put("uploadedBytes", 0L)
                .put("backupCompletedAt", JSONObject.NULL)
                .put("remoteRecordIds", JSONArray())
                .put("errorMessage", JSONObject.NULL)
            writeJob(job)
        }
    }

    fun upsertJob(filePath: String, sessions: JSONArray): JSONObject {
        val file = File(filePath)
        val id = stableId(file.canonicalPath)
        val existing = readJob(id)
        val destinationComputerId = connection()?.optString("computerId").orEmpty()
        if (existing != null &&
            existing.optLong("totalBytes") == file.length() &&
            existing.optLong("lastModified") == file.lastModified() &&
            existing.optString("destinationComputerId") == destinationComputerId
        ) {
            existing.put("sessions", sessions)
            if (!existing.has("fileCreatedAt")) {
                existing.put("fileCreatedAt", Instant.ofEpochMilli(file.lastModified()).toString())
            }
            if (!existing.has("backupCompletedAt")) existing.put("backupCompletedAt", JSONObject.NULL)
            if (!existing.has("scheduledCleanupAt")) existing.put("scheduledCleanupAt", JSONObject.NULL)
            if (!existing.has("localDeletedAt")) existing.put("localDeletedAt", JSONObject.NULL)
            if (!existing.has("waitingCleanup")) existing.put("waitingCleanup", false)
            if (!existing.has("remoteRecordIds")) existing.put("remoteRecordIds", JSONArray())
            writeJob(existing)
            return existing
        }
        val job = JSONObject()
            .put("id", id)
            .put("filePath", file.canonicalPath)
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
            .put("errorMessage", JSONObject.NULL)
            .put("sessions", sessions)
        writeJob(job)
        return job
    }

    fun readJob(id: String): JSONObject? {
        val file = File(jobsDirectory, "$id.json")
        return try {
            if (file.exists()) JSONObject(file.readText(Charsets.UTF_8)) else null
        } catch (_: Throwable) {
            null
        }
    }

    @Synchronized
    fun writeJob(job: JSONObject) {
        val target = File(jobsDirectory, "${job.getString("id")}.json")
        val temporary = File(target.path + ".tmp")
        temporary.writeText(job.toString(), Charsets.UTF_8)
        if (target.exists()) target.delete()
        temporary.renameTo(target)
    }

    fun jobs(): List<JSONObject> = jobsDirectory.listFiles { file -> file.extension == "json" }
        ?.mapNotNull { file ->
            try {
                JSONObject(file.readText(Charsets.UTF_8))
            } catch (_: Throwable) {
                null
            }
        }
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
        val prefs = context.getSharedPreferences(DEVICE_PREFS, Context.MODE_PRIVATE)
        prefs.getString("id", null)?.takeIf { it.isNotBlank() }?.let { return it }
        val value = UUID.randomUUID().toString()
        prefs.edit().putString("id", value).apply()
        return value
    }

    fun deviceName(): String = android.os.Build.MODEL?.trim().orEmpty().ifBlank { "打包手机" }
}
