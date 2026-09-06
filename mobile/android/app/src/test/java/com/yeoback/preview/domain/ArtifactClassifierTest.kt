package com.yeoback.preview.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ArtifactClassifierTest {
    @Test fun `classifies svg with an uncertainty category`() {
        assertEquals(ArtifactCategory.SVG_ARTWORK, ArtifactClassifier.classify("mark.svg", "assets/mark.svg"))
    }

    @Test fun `classifies draft folder but not a longer false positive token`() {
        assertEquals(ArtifactCategory.DRAFT_EXPORT, ArtifactClassifier.classify("brief.pdf", "project/drafts/brief.pdf"))
        assertNull(ArtifactClassifier.classify("draftsmanship.txt", "notes/draftsmanship.txt"))
    }

    @Test fun `classifies supported work record filename`() {
        assertEquals(ArtifactCategory.WORK_RECORD, ArtifactClassifier.classify("session-42.jsonl", "logs/session-42.jsonl"))
    }

    @Test fun `does not turn a current nonmatching asset into a candidate`() {
        assertNull(ArtifactClassifier.classify("approved-brand.png", "project/assets/approved-brand.png"))
    }
}

