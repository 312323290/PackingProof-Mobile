package app.packingproof.mobile

internal class AdaptivePreviewFpsPolicy(
    private val stableDelayMs: Long = 4_000L,
    private val stableThreshold: Float = 0.05f,
    private val motionThreshold: Float = 0.12f,
) {
    var targetFps: Int = ACTIVE_FPS
        private set

    private var stableSinceMs: Long? = null

    fun activate(nowMs: Long): Boolean {
        stableSinceMs = nowMs
        return updateTarget(ACTIVE_FPS)
    }

    fun deactivate(): Boolean {
        stableSinceMs = null
        return updateTarget(STABLE_FPS)
    }

    fun observe(angularSpeed: Float, nowMs: Long): Boolean {
        if (angularSpeed >= motionThreshold) {
            stableSinceMs = null
            return updateTarget(ACTIVE_FPS)
        }
        if (angularSpeed > stableThreshold) {
            stableSinceMs = null
            return false
        }
        val stableSince = stableSinceMs ?: nowMs.also { stableSinceMs = it }
        return if (nowMs - stableSince >= stableDelayMs) {
            updateTarget(STABLE_FPS)
        } else {
            false
        }
    }

    private fun updateTarget(value: Int): Boolean {
        if (targetFps == value) return false
        targetFps = value
        return true
    }

    companion object {
        const val ACTIVE_FPS = 30
        const val STABLE_FPS = 15
    }
}
