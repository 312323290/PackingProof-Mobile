package app.packingproof.mobile

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

internal class LanBackupStateStore(private val context: Context) {
    companion object {
        private const val PREFS = "lan_backup_connection"

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
            .apply()
    }

    fun connection(): JSONObject? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val baseUrl = prefs.getString("baseUrl", null) ?: return null
        return JSONObject()
            .put("baseUrl", baseUrl)
            .put("computerId", prefs.getString("computerId", "") ?: "")
            .put("computerName", prefs.getString("computerName", "已连接电脑") ?: "已连接电脑")
    }

    fun clearConnection() {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
    }

    fun upsertJob(filePath: String, sessions: JSONArray): JSONObject {
        val file = File(filePath)
        val id = stableId(file.canonicalPath)
        val existing = readJob(id)
        if (existing != null &&
            existing.optLong("totalBytes") == file.length() &&
            existing.optLong("lastModified") == file.lastModified()
        ) {
            existing.put("sessions", sessions)
            writeJob(existing)
            return existing
        }
        val job = JSONObject()
            .put("id", id)
            .put("filePath", file.canonicalPath)
            .put("fileName", file.name)
            .put("state", "pending")
            .put("uploadedBytes", 0L)
            .put("totalBytes", file.length())
            .put("lastModified", file.lastModified())
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
}
