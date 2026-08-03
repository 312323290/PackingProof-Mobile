package app.packingproof.mobile

internal enum class LanBackupFailureKind(val wireValue: String) {
    CREDENTIAL_INVALID("credential_invalid"),
    OFFLINE_OR_TIMEOUT("offline_or_timeout"),
    TEMPORARY_SERVICE("temporary_service"),
    UPLOAD_EXPIRED("upload_expired"),
    VERIFICATION_FAILED("verification_failed"),
    STORAGE_UNAVAILABLE("storage_unavailable"),
    NOT_BACKUP_HOST("not_backup_host"),
    INCOMPATIBLE_VERSION("incompatible_version"),
    UNKNOWN("unknown"),
}

internal object LanBackupFailurePolicy {
    fun shouldAutoRetry(failureKind: LanBackupFailureKind): Boolean = failureKind in setOf(
        LanBackupFailureKind.OFFLINE_OR_TIMEOUT,
        LanBackupFailureKind.TEMPORARY_SERVICE,
        LanBackupFailureKind.STORAGE_UNAVAILABLE,
    )

    fun classifyHttp(statusCode: Int, errorCode: String): LanBackupFailureKind = when {
        statusCode == 401 || statusCode == 403 -> LanBackupFailureKind.CREDENTIAL_INVALID
        errorCode == "upload_not_found" -> LanBackupFailureKind.UPLOAD_EXPIRED
        errorCode == "sha256_mismatch" -> LanBackupFailureKind.VERIFICATION_FAILED
        errorCode == "storage_unavailable" -> LanBackupFailureKind.STORAGE_UNAVAILABLE
        errorCode in setOf("invalid_content_range", "invalid_request", "invalid_json") ->
            LanBackupFailureKind.INCOMPATIBLE_VERSION
        statusCode == 404 -> LanBackupFailureKind.INCOMPATIBLE_VERSION
        statusCode in 500..599 || errorCode == "mobile_backup_failed" ->
            LanBackupFailureKind.TEMPORARY_SERVICE
        else -> LanBackupFailureKind.UNKNOWN
    }
}
