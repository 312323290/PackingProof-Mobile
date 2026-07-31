package app.packingproof.mobile

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RecordingStoragePolicyTest {
    @Test
    fun fixedWatermarksAreAppliedAtExactBoundaries() {
        assertTrue(RecordingStoragePolicy.needsWarning(RecordingStoragePolicy.WARNING_BYTES - 1))
        assertFalse(RecordingStoragePolicy.needsWarning(RecordingStoragePolicy.WARNING_BYTES))
        assertTrue(RecordingStoragePolicy.needsReclaim(RecordingStoragePolicy.MINIMUM_BYTES - 1))
        assertFalse(RecordingStoragePolicy.needsReclaim(RecordingStoragePolicy.MINIMUM_BYTES))
    }

    @Test
    fun onlyVerifiedBackupsAreEligibleAndOldestComesFirst() {
        val old = verified("old", "2026-07-01T00:00:00Z")
        val recent = verified("recent", "2026-07-20T00:00:00Z")
        val unbacked = verified("unbacked", "2026-06-01T00:00:00Z")
            .copy(backupCompletedAt = null)
        val uploading = verified("uploading", "2026-06-02T00:00:00Z")
            .copy(state = "uploading")
        val unverified = verified("unverified", "2026-06-03T00:00:00Z")
            .copy(contentSha256 = null)
        val deleted = verified("deleted", "2026-06-04T00:00:00Z")
            .copy(localDeletedAt = "2026-07-21T00:00:00Z")
        val legacyUnsigned = verified("legacy", "2026-06-05T00:00:00Z")
            .copy(verificationVersion = 0)

        val candidates = RecordingStoragePolicy.verifiedCandidates(
            listOf(recent, unbacked, uploading, old, unverified, deleted, legacyUnsigned),
        )

        assertEquals(listOf("old", "recent"), candidates.map { it.id })
    }

    private fun verified(id: String, createdAt: String) = RecordingStorageCandidate(
        id = id,
        state = "completed",
        fileCreatedAt = createdAt,
        backupCompletedAt = "2026-07-22T00:00:00Z",
        contentSha256 = "a".repeat(64),
        verificationVersion = BackupRequestAuthentication.VERSION,
        lastAttestedAt = java.time.Instant.now().toString(),
        localDeletedAt = null,
    )
}
