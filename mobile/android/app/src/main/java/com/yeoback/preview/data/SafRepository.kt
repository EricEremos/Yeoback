package com.yeoback.preview.data

import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import com.yeoback.preview.domain.ArtifactClassifier
import com.yeoback.preview.domain.Candidate
import com.yeoback.preview.domain.CurrentDocument
import com.yeoback.preview.domain.DeletionOutcome
import com.yeoback.preview.domain.DeletionReport
import com.yeoback.preview.domain.DocumentFingerprint
import com.yeoback.preview.domain.RevalidationPolicy
import com.yeoback.preview.domain.ScanProgress
import com.yeoback.preview.domain.ScanReport
import com.yeoback.preview.domain.ScanResult
import com.yeoback.preview.domain.SourceGrant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.util.ArrayDeque
import kotlin.coroutines.coroutineContext

class SafRepository(private val context: Context) {
    private val resolver: ContentResolver get() = context.contentResolver

    fun takeReadWriteGrant(treeUri: Uri): SourceGrant? {
        val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        return try {
            resolver.takePersistableUriPermission(treeUri, flags)
            sourceFor(treeUri)
        } catch (_: Exception) {
            null
        }
    }

    fun sourceFor(treeUri: Uri): SourceGrant {
        val permission = resolver.persistedUriPermissions.firstOrNull { it.uri == treeUri }
        return SourceGrant(
            treeUri = treeUri.toString(),
            providerLabel = treeUri.authority ?: "selected provider",
            hasReadWriteGrant = permission?.isReadPermission == true && permission.isWritePermission
        )
    }

    suspend fun scan(
        source: SourceGrant,
        cancelled: () -> Boolean,
        onProgress: (ScanProgress) -> Unit
    ): ScanResult = withContext(Dispatchers.IO) {
        val rootUri = Uri.parse(source.treeUri)
        if (!hasReadWriteGrant(rootUri)) {
            return@withContext ScanResult(emptyList(), ScanReport(partial = true, issues = listOf("Folder permission is unavailable. Choose the folder again.")))
        }
        val candidates = mutableListOf<Candidate>()
        val issues = mutableListOf<String>()
        val queue = ArrayDeque<QueuedDocument>()
        var visited = 0
        var skipped = 0
        var partial = false
        var wasCancelled = false
        val startedAt = System.nanoTime()
        var lastProgressNanos = 0L
        val enqueuedDocumentIds = mutableSetOf<String>()
        val rootDocumentId = try {
            DocumentsContract.getTreeDocumentId(rootUri)
        } catch (_: Exception) {
            return@withContext ScanResult(emptyList(), ScanReport(partial = true, issues = listOf("The selected provider returned an invalid folder identity.")))
        }
        queue.addLast(
            QueuedDocument(
                DocumentsContract.buildDocumentUriUsingTree(rootUri, rootDocumentId),
                rootDocumentId,
                ""
            )
        )
        enqueuedDocumentIds += rootDocumentId

        while (queue.isNotEmpty()) {
            coroutineContext.ensureActive()
            if (cancelled()) {
                partial = true
                wasCancelled = true
                issues.add("Scan cancelled. Results below cover only inspected entries.")
                break
            }
            if (visited >= ENTRY_LIMIT || elapsedSeconds(startedAt) >= TIME_LIMIT_SECONDS) {
                partial = true
                issues.add("Scan reached its 75,000-entry or 45-second limit. Choose a smaller folder for complete coverage.")
                break
            }

            val queued = queue.removeFirst()
            visited += 1
            val nowNanos = System.nanoTime()
            if (nowNanos - lastProgressNanos >= PROGRESS_INTERVAL_NANOS) {
                onProgress(ScanProgress(visited, candidates.size, queued.relativePath))
                lastProgressNanos = nowNanos
            }

            val metadata = queryMetadata(queued.uri)
            if (metadata == null) {
                skipped += 1
                partial = true
                addIssue(issues, "${queued.label()}: metadata is unavailable")
                continue
            }
            if (metadata.isDirectory) {
                if (metadata.displayName in EXCLUDED_FOLDERS || metadata.displayName.startsWith(".")) continue
                val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(rootUri, metadata.fingerprint.documentId ?: queued.documentId)
                try {
                    resolver.query(childrenUri, PROJECTION, null, null, null)?.use { cursor ->
                        while (cursor.moveToNext()) {
                            coroutineContext.ensureActive()
                            if (cancelled()) {
                                partial = true
                                wasCancelled = true
                                addIssue(issues, "Scan cancelled. Results below cover only inspected entries.")
                                break
                            }
                            if (visited + queue.size >= ENTRY_LIMIT || elapsedSeconds(startedAt) >= TIME_LIMIT_SECONDS) {
                                partial = true
                                addIssue(issues, "Scan reached its 75,000-entry or 45-second limit. Choose a smaller folder for complete coverage.")
                                break
                            }
                            val childDocumentId = cursor.stringOrNull(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                            val childName = cursor.stringOrNull(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                            if (childDocumentId.isNullOrBlank() || childName.isNullOrBlank()) {
                                skipped += 1
                                partial = true
                                addIssue(issues, "${queued.label()}: provider returned child metadata without a stable identity.")
                                continue
                            }
                            if (enqueuedDocumentIds.add(childDocumentId)) {
                                val childPath = if (queued.relativePath.isBlank()) childName else "${queued.relativePath}/$childName"
                                queue.addLast(
                                    QueuedDocument(
                                        DocumentsContract.buildDocumentUriUsingTree(rootUri, childDocumentId),
                                        childDocumentId,
                                        childPath
                                    )
                                )
                            }
                        }
                    } ?: run {
                        skipped += 1
                        partial = true
                        addIssue(issues, "${queued.label()}: provider did not return a child listing.")
                    }
                } catch (error: Exception) {
                    skipped += 1
                    partial = true
                    addIssue(issues, "${queued.label()}: ${error.safeMessage()}")
                }
                if (wasCancelled) break
                if (reachedLimit(visited, queue.size, startedAt)) {
                    partial = true
                    addIssue(issues, "Scan reached its 75,000-entry or 45-second limit. Choose a smaller folder for complete coverage.")
                    break
                }
                continue
            }
            if (metadata.displayName.startsWith(".")) continue
            val category = ArtifactClassifier.classify(metadata.displayName, queued.relativePath) ?: continue
            candidates += Candidate(
                uri = queued.uri.toString(),
                relativePath = queued.relativePath,
                category = category,
                reason = category.reason,
                fingerprint = metadata.fingerprint,
                supportsDelete = metadata.supportsDelete
            )
        }
        onProgress(ScanProgress(visited, candidates.size, "selected folder"))
        ScanResult(candidates, ScanReport(visited, skipped, issues, partial, wasCancelled))
    }

    suspend fun deleteReviewed(review: com.yeoback.preview.domain.ReviewedSelection): DeletionReport = withContext(Dispatchers.IO) {
        val treeUri = Uri.parse(review.source.treeUri)
        val outcomes = review.items.map { reviewed ->
            if (!hasReadWriteGrant(treeUri)) {
                return@map DeletionOutcome(reviewed.uri, reviewed.relativePath, "Not deleted: folder permission was revoked.", false)
            }
            val uri = Uri.parse(reviewed.uri)
            val current = queryMetadata(uri)?.let { CurrentDocument(it.fingerprint, it.supportsDelete) }
            val revalidation = RevalidationPolicy.evaluate(true, reviewed, current)
            when {
                revalidation != null -> DeletionOutcome(reviewed.uri, reviewed.relativePath, "Not deleted: ${revalidation.message}", false)
                !isStillChild(treeUri, uri) -> DeletionOutcome(reviewed.uri, reviewed.relativePath, "Not deleted: the provider could not prove this item is still inside the reviewed folder.", false)
                else -> try {
                    val deleted = DocumentsContract.deleteDocument(resolver, uri)
                    if (deleted) DeletionOutcome(reviewed.uri, reviewed.relativePath, "Deleted by provider. Recovery or undo was not promised.", true)
                    else DeletionOutcome(reviewed.uri, reviewed.relativePath, "Not deleted: the provider declined the request.", false)
                } catch (error: Exception) {
                    DeletionOutcome(reviewed.uri, reviewed.relativePath, "Not deleted: ${error.safeMessage()}", false)
                }
            }
        }
        DeletionReport(outcomes)
    }

    private fun hasReadWriteGrant(treeUri: Uri): Boolean = resolver.persistedUriPermissions.any {
        it.uri == treeUri && it.isReadPermission && it.isWritePermission
    }

    private fun isStillChild(treeUri: Uri, documentUri: Uri): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        return try {
            val treeDocumentUri = DocumentsContract.buildDocumentUriUsingTree(
                treeUri,
                DocumentsContract.getTreeDocumentId(treeUri)
            )
            DocumentsContract.isChildDocument(resolver, treeDocumentUri, documentUri)
        } catch (_: Exception) {
            false
        }
    }

    private fun queryMetadata(uri: Uri): ProviderMetadata? = try {
        resolver.query(uri, PROJECTION, null, null, null)?.use { cursor ->
            if (!cursor.moveToFirst()) return@use null
            val displayName = cursor.stringOrNull(DocumentsContract.Document.COLUMN_DISPLAY_NAME) ?: return@use null
            val documentId = cursor.stringOrNull(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val mimeType = cursor.stringOrNull(DocumentsContract.Document.COLUMN_MIME_TYPE)
            val flags = cursor.longOrNull(DocumentsContract.Document.COLUMN_FLAGS)?.toInt() ?: 0
            ProviderMetadata(
                displayName = displayName,
                isDirectory = mimeType == DocumentsContract.Document.MIME_TYPE_DIR,
                fingerprint = DocumentFingerprint(
                    documentId = documentId,
                    displayName = displayName,
                    sizeBytes = cursor.longOrNull(DocumentsContract.Document.COLUMN_SIZE),
                    lastModifiedMillis = cursor.longOrNull(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
                ),
                supportsDelete = flags and DocumentsContract.Document.FLAG_SUPPORTS_DELETE != 0
            )
        }
    } catch (_: Exception) {
        null
    }

    private fun android.database.Cursor.stringOrNull(column: String): String? {
        val index = getColumnIndex(column)
        return if (index >= 0 && !isNull(index)) getString(index) else null
    }

    private fun android.database.Cursor.longOrNull(column: String): Long? {
        val index = getColumnIndex(column)
        return if (index >= 0 && !isNull(index)) getLong(index) else null
    }

    private fun Throwable.safeMessage(): String = message?.takeIf { it.isNotBlank() } ?: javaClass.simpleName
    private fun elapsedSeconds(startedAt: Long): Long = (System.nanoTime() - startedAt) / 1_000_000_000L
    private fun reachedLimit(visited: Int, queued: Int, startedAt: Long): Boolean = visited + queued >= ENTRY_LIMIT || elapsedSeconds(startedAt) >= TIME_LIMIT_SECONDS
    private fun addIssue(issues: MutableList<String>, message: String) { if (issues.size < MAX_ISSUES) issues.add(message) }

    private data class QueuedDocument(val uri: Uri, val documentId: String, val relativePath: String) {
        fun label(): String = relativePath.ifBlank { "selected folder" }
    }
    private data class ProviderMetadata(val displayName: String, val isDirectory: Boolean, val fingerprint: DocumentFingerprint, val supportsDelete: Boolean)

    private companion object {
        const val ENTRY_LIMIT = 75_000
        const val TIME_LIMIT_SECONDS = 45L
        const val PROGRESS_INTERVAL_NANOS = 150_000_000L
        const val MAX_ISSUES = 8
        val EXCLUDED_FOLDERS = setOf("Library", "node_modules", "vendor", "Pods", "build", "dist")
        val PROJECTION = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            DocumentsContract.Document.COLUMN_FLAGS
        )
    }
}
