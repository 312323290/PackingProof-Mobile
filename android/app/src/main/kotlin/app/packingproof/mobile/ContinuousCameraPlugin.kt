package app.packingproof.mobile

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

class ContinuousCameraPlugin(
    private val activity: Activity,
    messenger: BinaryMessenger,
    private val textures: TextureRegistry,
) : MethodChannel.MethodCallHandler {
    companion object {
        private const val CHANNEL_NAME = "app.packingproof.mobile/continuous_camera"
        private const val PERMISSION_REQUEST = 4102
    }

    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private var engine = createEngine()
    private var pendingPermissionResult: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> initialize(result)
            "startWork" -> {
                val path = call.argument<String>("path")
                val recordAudio = call.argument<Boolean>("recordAudio") ?: true
                if (path.isNullOrBlank()) {
                    result.error("invalid_path", "录像文件路径不能为空", null)
                } else {
                    engine.startWork(path, recordAudio, result)
                }
            }
            "split" -> {
                val path = call.argument<String>("path")
                if (path.isNullOrBlank()) {
                    result.error("invalid_path", "下一段录像路径不能为空", null)
                } else {
                    engine.split(path, result)
                }
            }
            "stopWork" -> engine.stopWork(result)
            "setPairingScanEnabled" -> {
                engine.setPairingScanEnabled(call.argument<Boolean>("enabled") == true)
                result.success(null)
            }
            "setWorkScanEnabled" -> {
                engine.setWorkScanEnabled(call.argument<Boolean>("enabled") == true)
                result.success(null)
            }
            "setPreviewActive" -> {
                engine.setPreviewActive(call.argument<Boolean>("active") == true)
                result.success(null)
            }
            "setTorchEnabled" -> {
                engine.setTorchEnabled(call.argument<Boolean>("enabled") == true, result)
            }
            "switchCamera" -> {
                if (!engine.canSwitchNow()) {
                    result.error("camera_busy", "当前状态不能切换摄像头", null)
                } else {
                    val target = if (
                        engine.currentLensFacing() == CameraCharacteristics.LENS_FACING_FRONT
                    ) CameraCharacteristics.LENS_FACING_BACK
                    else CameraCharacteristics.LENS_FACING_FRONT
                    engine.dispose {
                        engine = createEngine(target)
                        engine.initialize(result)
                    }
                }
            }
            "dispose" -> {
                engine.dispose()
                engine = createEngine()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun initialize(result: MethodChannel.Result) {
        if (hasPermissions()) {
            engine.initialize(result)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("permission_pending", "正在等待摄像头权限", null)
            return
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO),
            PERMISSION_REQUEST,
        )
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST) {
            return false
        }
        val result = pendingPermissionResult
        pendingPermissionResult = null
        if (result == null) {
            return true
        }
        if (grantResults.size >= 2 && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
            engine.initialize(result)
        } else {
            result.error("permission_denied", "需要摄像头和麦克风权限才能工作", null)
        }
        return true
    }

    private fun hasPermissions(): Boolean =
        ContextCompat.checkSelfPermission(activity, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(activity, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    fun dispose() {
        channel.setMethodCallHandler(null)
        pendingPermissionResult?.error("disposed", "页面已关闭", null)
        pendingPermissionResult = null
        engine.dispose()
    }

    private fun createEngine(
        preferredLensFacing: Int = CameraCharacteristics.LENS_FACING_BACK,
    ): ContinuousSegmentCamera =
        ContinuousSegmentCamera(activity, textures, preferredLensFacing) { method, arguments ->
            activity.runOnUiThread { channel.invokeMethod(method, arguments) }
        }
}
