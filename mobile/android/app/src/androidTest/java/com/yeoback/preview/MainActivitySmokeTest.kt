package com.yeoback.preview

import android.graphics.Bitmap
import androidx.core.graphics.ColorUtils
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.hasScrollToNodeAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performScrollToNode
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.yeoback.preview.domain.ArtifactCategory
import com.yeoback.preview.domain.Candidate
import com.yeoback.preview.domain.DeletionOutcome
import com.yeoback.preview.domain.DeletionReport
import com.yeoback.preview.domain.DocumentFingerprint
import com.yeoback.preview.domain.ReviewPlanner
import com.yeoback.preview.domain.ScanReport
import com.yeoback.preview.domain.SourceGrant
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.io.FileOutputStream

@RunWith(AndroidJUnit4::class)
class MainActivitySmokeTest {
    @get:Rule val composeRule = createAndroidComposeRule<MainActivity>()

    @Test fun launchShowsScopedFolderStart() {
        composeRule.onNodeWithText("Candidates in a folder").assertIsDisplayed()
        composeRule.onNodeWithText("Choose a folder").assertIsDisplayed()
    }
}

@RunWith(AndroidJUnit4::class)
class FixtureSurfaceTest {
    @get:Rule val composeRule = createComposeRule()

    @Test fun lightInventoryAndProviderResultsRenderAndCapture() {
        val candidate = fixtureCandidate()
        val state = mutableStateOf(
            YeobackUiState(
                source = fixtureSource(),
                phase = ScanPhase.Complete,
                candidates = listOf(candidate),
                selectedUris = setOf(candidate.uri),
                report = ScanReport(visited = 3, skipped = 0)
            )
        )
        composeRule.setContent {
            YeobackTheme(darkTheme = false) {
                CandidateScreen(
                    state = state.value,
                    chooseFolder = {}, cancelScan = {}, updateQuery = {}, updateCategory = {},
                    updateSize = {}, updateAge = {}, updateSort = {}, toggleSelection = {},
                    selectAll = {}, clearSelection = {}, review = {}
                )
            }
        }

        composeRule.onNode(hasScrollToNodeAction()).performScrollToNode(hasText("drafts/export.svg"))
        composeRule.onNodeWithText("drafts/export.svg").assertIsDisplayed()
        captureSurface("light-inventory")
        composeRule.runOnIdle {
            state.value = state.value.copy(
                candidates = emptyList(),
                selectedUris = emptySet(),
                deletionReport = DeletionReport(
                    listOf(DeletionOutcome(candidate.uri, candidate.relativePath, "Deleted by the selected provider.", deleted = true))
                )
            )
        }
        composeRule.onNode(hasScrollToNodeAction()).performScrollToNode(hasText("Provider outcomes"))
        composeRule.onNodeWithText("Provider outcomes").assertIsDisplayed()
        composeRule.onNodeWithText("Deleted by the selected provider.").performScrollTo().assertIsDisplayed()
        captureSurface("light-results")
        composeRule.runOnIdle {
            state.value = state.value.copy(
                candidates = listOf(candidate),
                deletionReport = DeletionReport(
                    listOf(DeletionOutcome(candidate.uri, candidate.relativePath, "File changed after review; not deleted.", deleted = false))
                )
            )
        }
        composeRule.onNode(hasScrollToNodeAction()).performScrollToNode(hasText("File changed after review; not deleted."))
        composeRule.onNodeWithText("File changed after review; not deleted.").assertIsDisplayed()
    }

    @Test fun darkExactReviewRendersAndCaptures() {
        val candidate = fixtureCandidate()
        val review = ReviewPlanner.freeze(fixtureSource(), listOf(candidate), setOf(candidate.uri), 1_700_000_000_000L)
        composeRule.setContent {
            YeobackTheme(darkTheme = true) {
                ReviewScreen(review = review, deleting = false, back = {}, delete = {})
            }
        }

        composeRule.onNodeWithText("Review exact selection").assertIsDisplayed()
        composeRule.onNodeWithText("Delete permanently").assertIsDisplayed()
        composeRule.onNodeWithText("drafts/export.svg").assertIsDisplayed()
        val background = composeRule.onRoot().captureToImage().asAndroidBitmap().getPixel(0, 0)
        val cardBackground = composeRule.onNodeWithText("drafts/export.svg").captureToImage().asAndroidBitmap().getPixel(0, 0)
        assertTrue("Dark review must paint a dark canvas.", ColorUtils.calculateLuminance(background) < 0.1)
        assertTrue("Dark cards must not inherit Light container defaults.", ColorUtils.calculateLuminance(cardBackground) < 0.1)
        assertTrue("Dark card text needs at least 4.5:1 contrast.", ColorUtils.calculateContrast(0xFFF1EEE8.toInt(), cardBackground) >= 4.5)
        captureSurface("dark-review")
    }

    @Test fun fixtureWithUnknownMetadataStaysReviewOnly() {
        val fixture = fixtureCandidate().copy(
            fingerprint = DocumentFingerprint("fixture-id", "draft.svg", null, null)
        )
        composeRule.setContent {
            YeobackTheme { CandidateRow(fixture, selected = false, toggleSelection = {}) }
        }
        composeRule.onNodeWithText("Review only; metadata is incomplete, so identity cannot be revalidated.").assertIsDisplayed()
    }

    @Test fun selectionReviewCancelAndConfirmedDeleteDispatchesOnlyOnConfirmation() {
        val candidate = fixtureCandidate()
        var deleteDispatches = 0
        composeRule.setContent {
            val state = remember {
                mutableStateOf(
                    YeobackUiState(source = fixtureSource(), phase = ScanPhase.Complete, candidates = listOf(candidate))
                )
            }
            YeobackTheme {
                val review = state.value.review
                if (review == null) {
                    CandidateScreen(
                        state = state.value,
                        chooseFolder = {}, cancelScan = {}, updateQuery = {}, updateCategory = {},
                        updateSize = {}, updateAge = {}, updateSort = {},
                        toggleSelection = { uri -> state.value = state.value.copy(selectedUris = state.value.selectedUris + uri) },
                        selectAll = {
                            state.value = state.value.copy(
                                selectedUris = state.value.selectionAfterSelectAllVisible(System.currentTimeMillis())
                            )
                        },
                        clearSelection = { state.value = state.value.copy(selectedUris = emptySet()) },
                        review = {
                            state.value = state.value.copy(
                                review = ReviewPlanner.freeze(
                                    requireNotNull(state.value.source),
                                    state.value.candidates,
                                    state.value.selectedUris,
                                    System.currentTimeMillis()
                                )
                            )
                        }
                    )
                } else {
                    ReviewScreen(
                        review = review,
                        deleting = false,
                        back = { state.value = state.value.copy(review = null) },
                        delete = { deleteDispatches += 1 }
                    )
                }
            }
        }

        composeRule.onNodeWithText("Select all matches").performClick()
        composeRule.onNodeWithText("1 matching · 1 selected").assertIsDisplayed()
        composeRule.onNodeWithText("Review exact selection").performClick()
        composeRule.onNodeWithText("Delete permanently").assertIsDisplayed()
        composeRule.onNodeWithText("Cancel review").performClick()
        composeRule.onNodeWithText("1 matching · 1 selected").assertIsDisplayed()
        assertTrue("Canceling review must not dispatch a provider deletion.", deleteDispatches == 0)

        composeRule.onNodeWithText("Review exact selection").performClick()
        composeRule.onNodeWithText("Delete permanently").performClick()
        composeRule.onNodeWithTag("confirm-provider-deletion").performClick()
        assertTrue("Deletion dispatch occurs only after the irreversible confirmation.", deleteDispatches == 1)
    }

    private fun captureSurface(name: String) {
        val outputDirectory = requireNotNull(
            InstrumentationRegistry.getInstrumentation().targetContext.getExternalFilesDir("yeoback-screenshots")
        )
        val imageFile = File(outputDirectory, "$name.png")
        FileOutputStream(imageFile).use { output ->
            assertTrue(
                "Could not write screenshot: ${imageFile.absolutePath}",
                composeRule.onRoot().captureToImage().asAndroidBitmap().compress(Bitmap.CompressFormat.PNG, 100, output)
            )
        }
        assertTrue("Screenshot was empty: ${imageFile.absolutePath}", imageFile.length() > 0)
    }

    private fun fixtureCandidate() = Candidate(
        uri = "content://fixture/document/export",
        relativePath = "drafts/export.svg",
        category = ArtifactCategory.DRAFT_EXPORT,
        reason = ArtifactCategory.DRAFT_EXPORT.reason,
        fingerprint = DocumentFingerprint("fixture-export", "export.svg", 2_048L, 1_699_000_000_000L),
        supportsDelete = true
    )

    private fun fixtureSource() = SourceGrant(
        treeUri = "content://fixture/tree/root",
        providerLabel = "Fixture documents",
        hasReadWriteGrant = true
    )
}
