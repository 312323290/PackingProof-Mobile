package app.packingproof.mobile

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.net.Uri
import android.text.SpannableString
import android.text.Spanned
import android.text.style.AbsoluteSizeSpan
import android.text.style.BackgroundColorSpan
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.OverlaySettings
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.effect.TextOverlay
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@OptIn(UnstableApi::class)
class VideoWatermarkPlugin(
    context: Context,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, "app.packingproof.mobile/video_watermark")
    private val applicationContext = context.applicationContext
    private var transformer: Transformer? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pendingOutput: File? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "apply" -> apply(call.arguments as? Map<*, *>, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun apply(arguments: Map<*, *>?, result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("watermark_busy", "正在保存上一段录像", null)
            return
        }
        val inputPath = arguments?.get("inputPath") as? String
        val outputPath = arguments?.get("outputPath") as? String
        val startedAtMs = (arguments?.get("startedAtMs") as? Number)?.toLong()
        val trackingNumber = arguments?.get("trackingNumber") as? String ?: ""
        if (inputPath.isNullOrBlank() || outputPath.isNullOrBlank() || startedAtMs == null) {
            result.error("invalid_watermark", "录像水印参数无效", null)
            return
        }
        val input = File(inputPath)
        if (!input.isFile) {
            result.error("missing_input", "录像文件不存在", null)
            return
        }
        val output = File(outputPath)
        output.parentFile?.mkdirs()
        output.delete()

        val settings = StaticOverlaySettings.Builder()
            .setOverlayFrameAnchor(1f, -1f)
            .setBackgroundFrameAnchor(0.96f, -0.92f)
            .build()
        val overlay = object : TextOverlay() {
            private val formatter = SimpleDateFormat("yyyy/MM/dd HH:mm:ss", Locale.ROOT)

            override fun getText(presentationTimeUs: Long): SpannableString {
                val timestamp = formatter.format(Date(startedAtMs + presentationTimeUs / 1_000L))
                val text = if (trackingNumber.isBlank()) timestamp else "$timestamp\nOrder:$trackingNumber"
                return SpannableString(text).apply {
                    setSpan(
                        ForegroundColorSpan(Color.WHITE),
                        0,
                        length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                    )
                    setSpan(
                        BackgroundColorSpan(Color.argb(150, 0, 0, 0)),
                        0,
                        length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                    )
                    setSpan(
                        AbsoluteSizeSpan(32, true),
                        0,
                        length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                    )
                    setSpan(
                        StyleSpan(Typeface.BOLD),
                        0,
                        length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                    )
                }
            }

            override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings = settings
        }
        val editedMediaItem = EditedMediaItem.Builder(
            MediaItem.fromUri(Uri.fromFile(input)),
        ).setEffects(
            Effects(emptyList(), listOf(OverlayEffect(listOf(overlay)))),
        ).build()

        pendingResult = result
        pendingOutput = output
        transformer = Transformer.Builder(applicationContext)
            .setVideoMimeType(MimeTypes.VIDEO_H265)
            .addListener(
                object : Transformer.Listener {
                    override fun onCompleted(
                        composition: Composition,
                        exportResult: ExportResult,
                    ) = finishSuccess(outputPath)

                    override fun onError(
                        composition: Composition,
                        exportResult: ExportResult,
                        exportException: ExportException,
                    ) = finishError(exportException)
                },
            )
            .build()
        try {
            transformer?.start(editedMediaItem, outputPath)
        } catch (error: Exception) {
            finishError(error)
        }
    }

    private fun finishSuccess(outputPath: String) {
        val result = pendingResult
        pendingResult = null
        pendingOutput = null
        transformer = null
        result?.success(outputPath)
    }

    private fun finishError(error: Throwable) {
        pendingOutput?.delete()
        pendingOutput = null
        val result = pendingResult
        pendingResult = null
        transformer = null
        result?.error("watermark_failed", error.message ?: "录像水印生成失败", null)
    }

    fun dispose() {
        transformer?.cancel()
        transformer = null
        pendingOutput?.delete()
        pendingOutput = null
        pendingResult?.error("watermark_cancelled", "录像水印生成已取消", null)
        pendingResult = null
        channel.setMethodCallHandler(null)
    }
}
