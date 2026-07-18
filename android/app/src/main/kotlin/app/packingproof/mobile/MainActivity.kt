package app.packingproof.mobile

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    private var continuousCameraPlugin: ContinuousCameraPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        continuousCameraPlugin = ContinuousCameraPlugin(
            activity = this,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
            textures = flutterEngine.renderer,
        )
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
        super.onDestroy()
    }
}
