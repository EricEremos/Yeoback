package com.yeoback.preview.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

class RevalidationPolicyTest {
    private val fingerprint = DocumentFingerprint("id-1", "draft.svg", 12L, 34L)
    private val reviewed = Candidate("content://provider/document/id-1", "draft.svg", ArtifactCategory.SVG_ARTWORK, ArtifactCategory.SVG_ARTWORK.reason, fingerprint, true)

    @Test fun `rejects revoked grant before any mutation`() {
        assertEquals(RevalidationFailure.GRANT_REVOKED, RevalidationPolicy.evaluate(false, reviewed, CurrentDocument(fingerprint, true)))
    }

    @Test fun `rejects changed and unknown metadata fail closed`() {
        assertEquals(RevalidationFailure.CHANGED, RevalidationPolicy.evaluate(true, reviewed, CurrentDocument(fingerprint.copy(sizeBytes = 13L), true)))
        assertEquals(RevalidationFailure.UNVERIFIABLE, RevalidationPolicy.evaluate(true, reviewed, CurrentDocument(fingerprint.copy(lastModifiedMillis = null), true)))
    }

    @Test fun `accepts only exact unchanged deletion capable identity`() {
        assertNull(RevalidationPolicy.evaluate(true, reviewed, CurrentDocument(fingerprint, true)))
        assertEquals(RevalidationFailure.IDENTITY_CHANGED, RevalidationPolicy.evaluate(true, reviewed, CurrentDocument(fingerprint.copy(documentId = "id-2"), true)))
    }

    @Test fun `zero timestamp and negative size are review only`() {
        assertFalse(DocumentFingerprint("id-1", "draft.svg", -1L, 34L).isReliable)
        assertFalse(DocumentFingerprint("id-1", "draft.svg", 12L, 0L).isReliable)
    }
}
