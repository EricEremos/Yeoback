package com.yeoback.preview.domain

import org.junit.Assert.assertEquals
import org.junit.Test

class CandidateFilterTest {
    private val now = 200L * 24L * 60L * 60L * 1000L
    private fun candidate(uri: String, bytes: Long?, modified: Long?, category: ArtifactCategory = ArtifactCategory.SVG_ARTWORK) = Candidate(
        uri = uri,
        relativePath = "work/$uri.svg",
        category = category,
        reason = category.reason,
        fingerprint = DocumentFingerprint(uri, "$uri.svg", bytes, modified),
        supportsDelete = true
    )

    @Test fun `size and age requirements exclude unknown metadata`() {
        val known = candidate("known", 20L * 1024L * 1024L, now - 100L * 24L * 60L * 60L * 1000L)
        val unknown = candidate("unknown", null, null)
        val result = CandidateFilter(size = SizeFilter.AT_LEAST_10_MIB, age = AgeFilter.OLDER_THAN_90_DAYS).apply(listOf(known, unknown), now)
        assertEquals(listOf("known"), result.map { it.uri })
    }

    @Test fun `selectable flag rejects candidate with missing change metadata`() {
        assertEquals(false, candidate("unknown", 1L, null).selectableForDeletion)
    }
}

