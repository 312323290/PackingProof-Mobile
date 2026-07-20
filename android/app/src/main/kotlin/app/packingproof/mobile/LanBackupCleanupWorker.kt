package app.packingproof.mobile

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import org.json.JSONObject
import java.io.File
import java.time.Duration
import java.time.Instant
import java.util.concurrent.TimeUnit

internal object LanBackupCleanupScheduler {
    private const val WORK_PREFIX = "lan-backup-cleanup-"

    fun reschedule(context: Context, store: LanBackupStateStore, job: JSONObject) {
        val id = job.getString("id")
        val workManager = WorkManager.getInstance(context)
        val dueAt = dueAt(store, job)
        if (dueAt == null || nullableText(job, "localDeletedAt") != null) {
            workManager.cancelUniqueWork(WORK_PREFIX + id)
            job.put("scheduledCleanupAt", JSONObject.NULL).put("waitingCleanup", false)
            store.writeJob(job)
            return
        }
        val delay = Duration.between(Instant.now(), dueAt).toMillis().coerceAtLeast(0)
        job.put("scheduledCleanupAt", dueAt.toString())
        store.writeJob(job)
        val request = OneTimeWorkRequestBuilder<LanBackupCleanupWorker>()
            .setInputData(workDataOf("jobId" to id))
            .setInitialDelay(delay, TimeUnit.MILLISECONDS)
            .build()
        workManager.enqueueUniqueWork(
            WORK_PREFIX + id,
            ExistingWorkPolicy.REPLACE,
            request,
        )
    }

    fun rescheduleAll(context: Context, store: LanBackupStateStore) {
        store.jobs().forEach { reschedule(context, store, it) }
    }

    fun dueAt(store: LanBackupStateStore, job: JSONObject): Instant? {
        val completedAt = nullableText(job, "backupCompletedAt")
        if (job.optString("state") == "completed" && completedAt == null) return null
        val days = if (completedAt != null) store.backedRetentionDays() else store.unbackedRetentionDays()
        if (days < 0) return null
        val base = runCatching {
            Instant.parse(completedAt ?: job.getString("fileCreatedAt"))
        }.getOrNull() ?: return null
        return base.plus(Duration.ofDays(days.toLong()))
    }

    internal fun nullableText(value: JSONObject, key: String): String? {
        if (!value.has(key) || value.isNull(key)) return null
        return normalizeNullableText(value.opt(key))
    }

    internal fun normalizeNullableText(value: Any?): String? = value
        ?.takeUnless { it == JSONObject.NULL }
        ?.toString()
        ?.trim()
        ?.takeIf { it.isNotEmpty() && it != "null" }
}

internal class LanBackupCleanupWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {
    private val store = LanBackupStateStore(appContext)

    override suspend fun doWork(): Result {
        val id = inputData.getString("jobId") ?: return Result.failure()
        val job = store.readJob(id) ?: return Result.success()
        if (LanBackupCleanupScheduler.nullableText(job, "localDeletedAt") != null) {
            return Result.success()
        }
        val dueAt = LanBackupCleanupScheduler.dueAt(store, job) ?: return Result.success()
        if (Instant.now().isBefore(dueAt)) {
            LanBackupCleanupScheduler.reschedule(applicationContext, store, job)
            return Result.success()
        }
        if (job.optString("state") == "uploading") {
            job.put("waitingCleanup", true)
            store.writeJob(job)
            return Result.retry()
        }

        val file = File(job.optString("filePath"))
        val appDataRoot = applicationContext.dataDir.canonicalFile
        val managed = runCatching {
            file.canonicalFile.path.startsWith(appDataRoot.path + File.separator)
        }.getOrDefault(false)
        if (!managed) {
            job.put("waitingCleanup", false)
                .put("errorMessage", "录像不在应用目录内，已取消自动清理")
            store.writeJob(job)
            return Result.failure()
        }
        if (file.exists() && !file.delete()) {
            job.put("waitingCleanup", true)
            store.writeJob(job)
            return Result.retry()
        }
        job.put("localDeletedAt", Instant.now().toString())
            .put("scheduledCleanupAt", JSONObject.NULL)
            .put("waitingCleanup", false)
        if (job.optString("backupCompletedAt").isBlank()) {
            job.put("state", "expired")
                .put("errorMessage", "未备份录像已按保留策略清理")
        }
        store.writeJob(job)
        return Result.success()
    }
}
