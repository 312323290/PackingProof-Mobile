package app.packingproof.mobile

import android.app.Activity
import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.TimeUnit

internal class LanBackupPlugin(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    companion object {
        private const val CHANNEL = "app.packingproof.mobile/lan_backup"
        private const val WORK_PREFIX = "lan-backup-"
    }

    private val context: Context = activity.applicationContext
    private val channel = MethodChannel(messenger, CHANNEL)
    private val store = LanBackupStateStore(context)
    private val credentials = LanBackupCredentialStore(context)

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "initialize", "snapshot" -> {
                    if (call.method == "initialize") {
                        store.saveRetentionPolicies(
                            call.argument<Int>("unbackedRetentionDays"),
                            call.argument<Int>("backedRetentionDays"),
                        )
                        schedulePending()
                        LanBackupCleanupScheduler.rescheduleAll(context, store)
                    }
                    result.success(snapshot())
                }
                "loadAccessKey" -> result.success(credentials.load() ?: "")
                "saveConnection" -> {
                    val baseUrl = call.argument<String>("baseUrl") ?: error("缺少电脑地址")
                    val accessKey = call.argument<String>("accessKey") ?: error("缺少电脑密钥")
                    val computerId = call.argument<String>("computerId") ?: ""
                    WorkManager.getInstance(context).cancelAllWorkByTag("lan-backup")
                    store.saveConnection(
                        baseUrl,
                        computerId,
                        call.argument<String>("computerName") ?: "已连接电脑",
                    )
                    credentials.save(accessKey)
                    store.retargetJobs(computerId)
                    schedulePending()
                    result.success(null)
                }
                "disconnect" -> {
                    WorkManager.getInstance(context).cancelAllWorkByTag("lan-backup")
                    store.clearConnection()
                    credentials.clear()
                    result.success(null)
                }
                "enqueue" -> {
                    val path = call.argument<String>("filePath") ?: error("缺少录像路径")
                    if (!File(path).exists()) error("录像文件不存在")
                    val sessions = JSONArray(
                        call.argument<List<Map<String, Any?>>>("sessions")
                            ?: emptyList<Map<String, Any?>>(),
                    )
                    val job = store.upsertJob(path, sessions)
                    val forceRestart = call.argument<Boolean>("forceRestart") == true
                    if (forceRestart && job.optString("state") != "completed") {
                        job.put("state", "pending").put("errorMessage", JSONObject.NULL)
                        store.writeJob(job)
                    }
                    LanBackupCleanupScheduler.reschedule(context, store, job)
                    if (call.argument<Boolean>("startUpload") != false) {
                        schedule(job.getString("id"), replace = forceRestart)
                    }
                    result.success(null)
                }
                "setRetentionPolicies" -> {
                    store.saveRetentionPolicies(
                        call.argument<Int>("unbackedRetentionDays"),
                        call.argument<Int>("backedRetentionDays"),
                    )
                    LanBackupCleanupScheduler.rescheduleAll(context, store)
                    result.success(null)
                }
                "retry" -> {
                    val id = call.argument<String>("id") ?: error("缺少任务编号")
                    val job = store.readJob(id) ?: error("找不到备份任务")
                    job.put("state", "pending").put("errorMessage", JSONObject.NULL)
                    store.writeJob(job)
                    schedule(id, replace = true)
                    result.success(null)
                }
                "cancel" -> {
                    val id = call.argument<String>("id") ?: error("缺少任务编号")
                    WorkManager.getInstance(context).cancelUniqueWork(WORK_PREFIX + id)
                    store.readJob(id)?.let { job ->
                        job.put("state", "paused")
                        store.writeJob(job)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (error: Throwable) {
            result.error("lan_backup", error.message ?: "局域网备份失败", null)
        }
    }

    private fun schedulePending() {
        if (store.connection() == null || credentials.load().isNullOrBlank()) return
        store.jobs()
            .filter { it.optString("state") in setOf("pending", "paused", "uploading") }
            .forEach { schedule(it.getString("id"), replace = false) }
    }

    private fun schedule(id: String, replace: Boolean) {
        if (store.connection() == null || credentials.load().isNullOrBlank()) return
        val request = OneTimeWorkRequestBuilder<LanBackupWorker>()
            .setInputData(workDataOf("jobId" to id))
            .setConstraints(
                Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build(),
            )
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 15, TimeUnit.SECONDS)
            .addTag("lan-backup")
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(
            WORK_PREFIX + id,
            if (replace) ExistingWorkPolicy.REPLACE else ExistingWorkPolicy.KEEP,
            request,
        )
    }

    private fun snapshot(): Map<String, Any?> = mapOf(
        "connection" to store.connection()?.toFlutterValue(),
        "jobs" to store.jobs().map { it.toFlutterValue() },
    )

    fun dispose() {
        channel.setMethodCallHandler(null)
    }
}

internal fun Any?.toFlutterValue(): Any? = when (this) {
    null, JSONObject.NULL -> null
    is JSONObject -> keys().asSequence().associateWith { get(it).toFlutterValue() }
    is JSONArray -> (0 until length()).map { get(it).toFlutterValue() }
    else -> this
}
