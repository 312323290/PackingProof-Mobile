package app.packingproof.mobile

import android.media.AudioManager
import android.os.Bundle
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var continuousCameraPlugin: ContinuousCameraPlugin? = null
    private var maxVolumeController: MaxVolumeController? = null
    private var maxVolumeChannel: MethodChannel? = null
    private var lanBackupPlugin: LanBackupPlugin? = null
    private var videoExportPlugin: VideoExportPlugin? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        volumeControlStream = AudioManager.STREAM_MUSIC
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        continuousCameraPlugin = ContinuousCameraPlugin(
            activity = this,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
            textures = flutterEngine.renderer,
        )
        lanBackupPlugin = LanBackupPlugin(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        videoExportPlugin = VideoExportPlugin(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        maxVolumeController = MaxVolumeController(this)
        maxVolumeChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app.packingproof.mobile/system_volume",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "beginSession" -> {
                        maxVolumeController?.enable()
                        result.success(null)
                    }
                    "endSession" -> {
                        maxVolumeController?.pauseSession()
                        result.success(null)
                    }
                    "disable" -> {
                        maxVolumeController?.disable()
                        result.success(null)
                    }
                    "boost" -> {
                        maxVolumeController?.boost()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (continuousCameraPlugin?.onRequestPermissionsResult(requestCode, grantResults) == true) {
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
        continuousCameraPlugin?.dispose()
        continuousCameraPlugin = null
        maxVolumeChannel?.setMethodCallHandler(null)
        maxVolumeChannel = null
        maxVolumeController?.dispose()
        maxVolumeController = null
        lanBackupPlugin?.dispose()
        lanBackupPlugin = null
        videoExportPlugin?.dispose()
        videoExportPlugin = null
        super.onDestroy()
    }

    override fun onStart() {
        super.onStart()
        maxVolumeController?.resumeSession()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            maxVolumeController?.resumeSession()
        }
    }

    override fun onStop() {
        maxVolumeController?.pauseSession()
        super.onStop()
    }
}
