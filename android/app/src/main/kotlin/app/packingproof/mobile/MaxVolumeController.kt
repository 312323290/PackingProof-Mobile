package app.packingproof.mobile

import android.content.Context
import android.database.ContentObserver
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings

class MaxVolumeController(context: Context) {
    private val audioManager = context.getSystemService(AudioManager::class.java)
    private val contentResolver = context.contentResolver
    private val mainHandler = Handler(Looper.getMainLooper())
    private var sessionActive = false
    private var enabled = false
    private var originalVolume = 0
    private var maximumVolume = 0
    private var sessionVolume = 0
    private var lastObservedVolume = 0
    private var userChangedVolume = false
    private var ignoreOwnChangeUntil = 0L
    private var volumeRetryCount = 0
    private val audioFocusChangeListener = AudioManager.OnAudioFocusChangeListener { }
    private val volumeRetry = Runnable { resumeSession() }

    private val volumeObserver = object : ContentObserver(mainHandler) {
        override fun onChange(selfChange: Boolean) {
            if (!sessionActive) return
            val current = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
            if (SystemClock.elapsedRealtime() <= ignoreOwnChangeUntil) {
                lastObservedVolume = current
                return
            }
            if (current != lastObservedVolume) {
                userChangedVolume = true
                lastObservedVolume = current
            }
        }
    }

    fun enable() {
        enabled = true
        volumeRetryCount = 0
        resumeSession()
    }

    fun disable() {
        enabled = false
        pauseSession()
    }

    fun boost() {
        if (!enabled || userChangedVolume) return
        repeat(8) {
            if (audioManager.getStreamVolume(AudioManager.STREAM_MUSIC) >= maximumVolume) {
                return
            }
            runBoostPass()
        }
    }

    private fun runBoostPass() {
        mainHandler.removeCallbacks(volumeRetry)
        volumeRetryCount = 0
        if (sessionActive) {
            sessionActive = false
            contentResolver.unregisterContentObserver(volumeObserver)
        }
        resumeSession()
    }

    fun resumeSession() {
        if (!enabled) return
        if (sessionActive) return
        if (volumeRetryCount == 0) {
            originalVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
        }
        maximumVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        userChangedVolume = false
        val focusRequest = requestTemporaryAudioFocus()
        var current: Int
        try {
            current = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
            while (current < maximumVolume) {
                audioManager.setStreamVolume(
                    AudioManager.STREAM_MUSIC,
                    current + 1,
                    AudioManager.FLAG_SHOW_UI,
                )
                val adjusted = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
                if (adjusted == current) break
                current = adjusted
            }
        } finally {
            abandonTemporaryAudioFocus(focusRequest)
        }
        if (current == originalVolume && current < maximumVolume && volumeRetryCount < 8) {
            volumeRetryCount += 1
            mainHandler.removeCallbacks(volumeRetry)
            mainHandler.postDelayed(volumeRetry, 250L)
            return
        }
        volumeRetryCount = 0
        sessionActive = true
        sessionVolume = current
        lastObservedVolume = sessionVolume
        ignoreOwnChangeUntil = SystemClock.elapsedRealtime() + 750L
        contentResolver.registerContentObserver(
            Settings.System.CONTENT_URI,
            true,
            volumeObserver,
        )
    }

    fun pauseSession() {
        mainHandler.removeCallbacks(volumeRetry)
        volumeRetryCount = 0
        if (!sessionActive) return
        sessionActive = false
        contentResolver.unregisterContentObserver(volumeObserver)
    }

    fun dispose() {
        pauseSession()
        mainHandler.removeCallbacksAndMessages(null)
    }

    private fun requestTemporaryAudioFocus(): AudioFocusRequest? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build(),
                )
                .setOnAudioFocusChangeListener(audioFocusChangeListener)
                .build()
            audioManager.requestAudioFocus(request)
            return request
        }
        @Suppress("DEPRECATION")
        audioManager.requestAudioFocus(
            audioFocusChangeListener,
            AudioManager.STREAM_MUSIC,
            AudioManager.AUDIOFOCUS_GAIN_TRANSIENT,
        )
        return null
    }

    private fun abandonTemporaryAudioFocus(request: AudioFocusRequest?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && request != null) {
            audioManager.abandonAudioFocusRequest(request)
            return
        }
        @Suppress("DEPRECATION")
        audioManager.abandonAudioFocus(audioFocusChangeListener)
    }
}
