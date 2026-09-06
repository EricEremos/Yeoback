package com.yeoback.preview.domain

import java.util.Locale
import java.util.Collections

enum class ArtifactCategory(val label: String, val reason: String) {
    SVG_ARTWORK("SVG artwork", "SVG artwork · origin and project usage not verified"),
    DRAFT_EXPORT("Drafts & exports", "Draft/export name or folder · may still be used by a project"),
    WORK_RECORD("Work records", "Work-record filename · may contain useful history")
}

data class DocumentFingerprint(
    val documentId: String?,
    val displayName: String?,
    val sizeBytes: Long?,
    val lastModifiedMillis: Long?
) {
    val isReliable: Boolean
        get() = !documentId.isNullOrBlank() &&
            !displayName.isNullOrBlank() &&
            sizeBytes != null && sizeBytes >= 0L &&
            lastModifiedMillis != null && lastModifiedMillis > 0L
}

data class Candidate(
    val uri: String,
    val relativePath: String,
    val category: ArtifactCategory,
    val reason: String,
    val fingerprint: DocumentFingerprint,
    val supportsDelete: Boolean,
    val inaccessibleReason: String? = null
) {
    val selectableForDeletion: Boolean
        get() = inaccessibleReason == null && supportsDelete && fingerprint.isReliable
}

data class SourceGrant(
    val treeUri: String,
    val providerLabel: String,
    val hasReadWriteGrant: Boolean
)

data class ScanReport(
    val visited: Int = 0,
    val skipped: Int = 0,
    val issues: List<String> = emptyList(),
    val partial: Boolean = false,
    val cancelled: Boolean = false
)

data class ScanProgress(val visited: Int, val candidates: Int, val path: String)

data class ScanResult(val candidates: List<Candidate>, val report: ScanReport)

enum class SizeFilter(val label: String, val minimumBytes: Long?) {
    ANY_SIZE("Any size", null),
    AT_LEAST_10_MIB("10 MiB+", 10L * 1024L * 1024L),
    AT_LEAST_100_MIB("100 MiB+", 100L * 1024L * 1024L)
}

enum class AgeFilter(val label: String, val olderThanDays: Long?) {
    ANY_AGE("Any age", null),
    OLDER_THAN_30_DAYS("30 days+", 30),
    OLDER_THAN_90_DAYS("90 days+", 90)
}

enum class SortOrder(val label: String) { NAME("Name"), LARGEST("Largest"), OLDEST("Oldest"), CATEGORY("Category") }

data class CandidateFilter(
    val query: String = "",
    val categories: Set<ArtifactCategory> = emptySet(),
    val size: SizeFilter = SizeFilter.ANY_SIZE,
    val age: AgeFilter = AgeFilter.ANY_AGE,
    val sort: SortOrder = SortOrder.NAME
) {
    fun apply(items: List<Candidate>, nowMillis: Long): List<Candidate> = items
        .filter { candidate ->
            val queryMatches = query.isBlank() || candidate.relativePath.contains(query, ignoreCase = true)
            val categoryMatches = categories.isEmpty() || candidate.category in categories
            val sizeMatches = size.minimumBytes?.let { minimum -> candidate.fingerprint.sizeBytes?.let { it >= minimum } ?: false } ?: true
            val ageMatches = age.olderThanDays?.let { days ->
                candidate.fingerprint.lastModifiedMillis?.let { nowMillis - it >= days * MILLIS_PER_DAY } ?: false
            } ?: true
            queryMatches && categoryMatches && sizeMatches && ageMatches
        }
        .sortedWith(sortComparator())

    private fun sortComparator(): Comparator<Candidate> = when (sort) {
        SortOrder.NAME -> compareBy(String.CASE_INSENSITIVE_ORDER) { it.relativePath }
        SortOrder.LARGEST -> compareByDescending<Candidate> { it.fingerprint.sizeBytes ?: Long.MIN_VALUE }
            .thenBy(String.CASE_INSENSITIVE_ORDER) { it.relativePath }
        SortOrder.OLDEST -> compareBy<Candidate> { it.fingerprint.lastModifiedMillis ?: Long.MAX_VALUE }
            .thenBy(String.CASE_INSENSITIVE_ORDER) { it.relativePath }
        SortOrder.CATEGORY -> compareBy<Candidate> { it.category.ordinal }
            .thenBy(String.CASE_INSENSITIVE_ORDER) { it.relativePath }
    }

    private companion object { const val MILLIS_PER_DAY = 24L * 60L * 60L * 1000L }
}

object ArtifactClassifier {
    private val draftTokens = setOf(
        "draft", "drafts", "scratch", "tmp", "temp", "mockup", "mockups", "prototype", "prototypes",
        "iteration", "iterations", "export", "exports"
    )
    private val recordTokens = setOf("transcript", "conversation", "session", "prompt", "prompts", "checkpoint", "trace", "debug")
    private val recordExtensions = setOf("md", "markdown", "txt", "json", "jsonl", "log", "html")

    fun classify(displayName: String, relativePath: String): ArtifactCategory? {
        val normalizedPath = relativePath.lowercase(Locale.ROOT)
        val pathTokens = normalizedPath.split(Regex("[^a-z0-9]+"))
        if (pathTokens.any(draftTokens::contains)) return ArtifactCategory.DRAFT_EXPORT

        val extension = displayName.substringAfterLast('.', "").lowercase(Locale.ROOT)
        val stemTokens = displayName.substringBeforeLast('.', displayName)
            .lowercase(Locale.ROOT)
            .split(Regex("[^a-z0-9]+"))
        if (extension in recordExtensions && stemTokens.any(recordTokens::contains)) return ArtifactCategory.WORK_RECORD
        if (extension == "svg") return ArtifactCategory.SVG_ARTWORK
        return null
    }
}

data class ReviewedSelection(
    val source: SourceGrant,
    val reviewedAtMillis: Long,
    val items: List<Candidate>
)

object ReviewPlanner {
    fun freeze(source: SourceGrant, allCandidates: List<Candidate>, selectedUris: Set<String>, nowMillis: Long): ReviewedSelection =
        ReviewedSelection(
            source = source,
            reviewedAtMillis = nowMillis,
            items = Collections.unmodifiableList(
                allCandidates.filter { it.uri in selectedUris && it.selectableForDeletion }
                    .sortedBy { it.relativePath.lowercase(Locale.ROOT) }
            )
        )
}

data class CurrentDocument(
    val fingerprint: DocumentFingerprint?,
    val supportsDelete: Boolean
)

enum class RevalidationFailure(val message: String) {
    GRANT_REVOKED("Folder permission was revoked. Choose the folder again."),
    MISSING("This item is no longer available."),
    IDENTITY_CHANGED("The provider returned a different item identity."),
    CHANGED("This item changed after review. Refresh and review it again."),
    UNSUPPORTED("This provider no longer supports permanent deletion for this item."),
    UNVERIFIABLE("Metadata is incomplete, so this item cannot be safely revalidated.")
}

object RevalidationPolicy {
    fun evaluate(grantStillValid: Boolean, reviewed: Candidate, current: CurrentDocument?): RevalidationFailure? {
        if (!grantStillValid) return RevalidationFailure.GRANT_REVOKED
        val expected = reviewed.fingerprint
        val actual = current?.fingerprint ?: return RevalidationFailure.MISSING
        if (!expected.isReliable || !actual.isReliable) return RevalidationFailure.UNVERIFIABLE
        if (expected.documentId != actual.documentId) return RevalidationFailure.IDENTITY_CHANGED
        if (expected.displayName != actual.displayName || expected.sizeBytes != actual.sizeBytes || expected.lastModifiedMillis != actual.lastModifiedMillis) {
            return RevalidationFailure.CHANGED
        }
        if (current.supportsDelete.not()) return RevalidationFailure.UNSUPPORTED
        return null
    }
}

data class DeletionOutcome(val uri: String, val relativePath: String, val detail: String, val deleted: Boolean)
data class DeletionReport(val outcomes: List<DeletionOutcome>)
