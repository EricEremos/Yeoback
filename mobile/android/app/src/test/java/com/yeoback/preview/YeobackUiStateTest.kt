package com.yeoback.preview

import com.yeoback.preview.domain.ArtifactCategory
import com.yeoback.preview.domain.Candidate
import com.yeoback.preview.domain.CandidateFilter
import com.yeoback.preview.domain.DocumentFingerprint
import org.junit.Assert.assertEquals
import org.junit.Test

class YeobackUiStateTest {
    private fun candidate(uri: String, path: String, selectable: Boolean): Candidate = Candidate(
        uri = uri,
        relativePath = path,
        category = ArtifactCategory.SVG_ARTWORK,
        reason = ArtifactCategory.SVG_ARTWORK.reason,
        fingerprint = DocumentFingerprint(uri, path.substringAfterLast('/'), if (selectable) 1L else null, if (selectable) 2L else null),
        supportsDelete = true
    )

    @Test fun `select all matches retains eligible selections made under earlier filters`() {
        val prior = candidate("prior", "drafts/prior.svg", selectable = true)
        val visible = candidate("visible", "exports/visible.svg", selectable = true)
        val reviewOnly = candidate("review-only", "exports/incomplete.svg", selectable = false)
        val state = YeobackUiState(
            candidates = listOf(prior, visible, reviewOnly),
            filter = CandidateFilter(query = "exports"),
            selectedUris = setOf(prior.uri)
        )

        assertEquals(setOf(prior.uri, visible.uri), state.selectionAfterSelectAllVisible(nowMillis = 10L))
    }
}
