package app.packingproof.mobile

import org.junit.Assert.assertEquals
import org.junit.Test

class LanBackupFailurePolicyTest {
    @Test
    fun `credential failures always require a new scan`() {
        assertEquals(
            LanBackupFailureKind.CREDENTIAL_INVALID,
            LanBackupFailurePolicy.classifyHttp(401, ""),
        )
        assertEquals(
            LanBackupFailureKind.CREDENTIAL_INVALID,
            LanBackupFailurePolicy.classifyHttp(403, "mobile_backup_failed"),
        )
    }

    @Test
    fun `server failures are classified for one matching recovery action`() {
        val cases = mapOf(
            Pair(404, "upload_not_found") to LanBackupFailureKind.UPLOAD_EXPIRED,
            Pair(409, "sha256_mismatch") to LanBackupFailureKind.VERIFICATION_FAILED,
            Pair(503, "storage_unavailable") to LanBackupFailureKind.STORAGE_UNAVAILABLE,
            Pair(400, "invalid_json") to LanBackupFailureKind.INCOMPATIBLE_VERSION,
            Pair(404, "") to LanBackupFailureKind.INCOMPATIBLE_VERSION,
            Pair(503, "mobile_backup_failed") to LanBackupFailureKind.TEMPORARY_SERVICE,
            Pair(418, "") to LanBackupFailureKind.UNKNOWN,
        )

        cases.forEach { (input, expected) ->
            assertEquals(expected, LanBackupFailurePolicy.classifyHttp(input.first, input.second))
        }
    }
}
