package com.yeoback.preview.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class ReviewPlannerTest {
    private fun candidate(uri: String, name: String) = Candidate(uri, name, ArtifactCategory.SVG_ARTWORK, ArtifactCategory.SVG_ARTWORK.reason, DocumentFingerprint(uri, name, 4L, 5L), true)

    @Test fun `review freezes the exact selected eligible items including offscreen matches`() {
        val source = SourceGrant("content://provider/tree/root", "provider", true)
        val scanned = mutableListOf(candidate("one", "z.svg"), candidate("two", "a.svg"))
        val review = ReviewPlanner.freeze(source, scanned, setOf("one", "two"), 99L)
        scanned.clear()
        assertEquals(listOf("a.svg", "z.svg"), review.items.map { it.relativePath })
        assertEquals(99L, review.reviewedAtMillis)
        assertThrows(UnsupportedOperationException::class.java) {
            (review.items as MutableList<Candidate>).clear()
        }
    }
}
