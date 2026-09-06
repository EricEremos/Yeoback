package com.yeoback.preview

import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.yeoback.preview.data.SafRepository
import com.yeoback.preview.domain.ReviewPlanner
import com.yeoback.preview.domain.SourceGrant
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class SafRepositoryFixtureTest {
    private lateinit var scenario: ActivityScenario<FixtureGrantHostActivity>
    private lateinit var repository: SafRepository
    private lateinit var source: SourceGrant

    @Before fun setUp() {
        FixtureDocumentsProvider.resetForTest()
        scenario = ActivityScenario.launch(FixtureGrantHostActivity::class.java)
        source = selectPersistedTree()
    }

    @After fun tearDown() {
        scenario.close()
    }

    @Test fun scansFixtureAndDeletesRevalidatedReviewedFile() = runBlocking {
        val scan = repository.scan(source, cancelled = { false }, onProgress = {})
        assertFalse(scan.report.partial)
        val export = scan.candidates.single { it.fingerprint.documentId == FixtureDocumentsProvider.EXPORT_ID }
        val review = ReviewPlanner.freeze(source, scan.candidates, setOf(export.uri), 1L)

        val deletion = repository.deleteReviewed(review)

        assertTrue(deletion.outcomes.single().deleted)
        assertFalse(FixtureDocumentsProvider.containsForTest(FixtureDocumentsProvider.EXPORT_ID))
        assertTrue("Unreviewed original must remain untouched.", FixtureDocumentsProvider.containsForTest(FixtureDocumentsProvider.ORIGINAL_ID))
        assertTrue(repository.sourceFor(android.net.Uri.parse(source.treeUri)).hasReadWriteGrant)
    }

    @Test fun refusesChangedFileAndPreservesSourceDocument() = runBlocking {
        val scan = repository.scan(source, cancelled = { false }, onProgress = {})
        val changing = scan.candidates.single { it.fingerprint.documentId == FixtureDocumentsProvider.CHANGING_ID }
        val review = ReviewPlanner.freeze(source, scan.candidates, setOf(changing.uri), 1L)
        FixtureDocumentsProvider.rewriteForTest(FixtureDocumentsProvider.CHANGING_ID)

        val deletion = repository.deleteReviewed(review)

        assertFalse(deletion.outcomes.single().deleted)
        assertTrue(deletion.outcomes.single().detail.contains("changed after review"))
        assertTrue(FixtureDocumentsProvider.containsForTest(FixtureDocumentsProvider.CHANGING_ID))
        assertTrue("Unreviewed original must remain untouched.", FixtureDocumentsProvider.containsForTest(FixtureDocumentsProvider.ORIGINAL_ID))
    }

    private fun selectPersistedTree(): SourceGrant {
        val latch = CountDownLatch(1)
        var selected: SourceGrant? = null
        scenario.onActivity { activity ->
            repository = SafRepository(activity)
            activity.onTreeReturned = { uri ->
                selected = uri?.let(repository::takeReadWriteGrant)
                latch.countDown()
            }
            activity.requestFixtureTree()
        }
        assertTrue("Fixture picker did not return a selected tree.", latch.await(5, TimeUnit.SECONDS))
        assertNotNull("Fixture tree was not granted persistable read/write access.", selected)
        return requireNotNull(selected)
    }
}
