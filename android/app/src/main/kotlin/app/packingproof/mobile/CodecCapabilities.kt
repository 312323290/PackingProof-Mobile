package app.packingproof.mobile

import android.media.MediaCodecList

/**
 * 查询设备 MediaCodec 编解码能力。
 *
 * 部分鸿蒙/低端机型只有 H.265 编码器却没有可用的 H.265 解码器，
 * 这类机型录出的 H.265 本机无法播放，需要在录像前自动回退到 H.264。
 */
object CodecCapabilities {
    fun hasDecoder(mime: String): Boolean {
        return try {
            val codecList = MediaCodecList(MediaCodecList.ALL_CODECS)
            codecList.codecInfos.any { info ->
                !info.isEncoder &&
                    info.supportedTypes.any { it.equals(mime, ignoreCase = true) }
            }
        } catch (_: Throwable) {
            // 查询失败时不阻断现有录像流程，按“支持解码”处理。
            true
        }
    }
}
