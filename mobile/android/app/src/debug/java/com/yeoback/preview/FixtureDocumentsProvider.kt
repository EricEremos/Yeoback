package com.yeoback.preview

import android.app.Activity
import android.content.Intent
import android.database.Cursor
import android.database.MatrixCursor
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.DocumentsProvider
import java.io.FileNotFoundException

class FixtureDocumentsProvider : DocumentsProvider() {
    override fun onCreate(): Boolean = true

    override fun queryRoots(projection: Array<String>?): Cursor {
        val columns = projection ?: arrayOf(
            DocumentsContract.Root.COLUMN_ROOT_ID,
            DocumentsContract.Root.COLUMN_DOCUMENT_ID,
            DocumentsContract.Root.COLUMN_TITLE,
            DocumentsContract.Root.COLUMN_FLAGS
        )
        return MatrixCursor(columns).also { cursor ->
            val row = cursor.newRow()
            columns.forEach { column ->
                row.add(column, when (column) {
                    DocumentsContract.Root.COLUMN_ROOT_ID -> ROOT_ID
                    DocumentsContract.Root.COLUMN_DOCUMENT_ID -> ROOT_ID
                    DocumentsContract.Root.COLUMN_TITLE -> "Yeoback fixture"
                    DocumentsContract.Root.COLUMN_FLAGS -> DocumentsContract.Root.FLAG_SUPPORTS_CREATE or DocumentsContract.Root.FLAG_SUPPORTS_IS_CHILD
                    else -> null
                })
            }
        }
    }

    override fun queryDocument(documentId: String, projection: Array<String>?): Cursor = synchronized(lock) {
        documentCursor(projection, listOf(requireNode(documentId)))
    }

    override fun queryChildDocuments(parentDocumentId: String, projection: Array<String>?, sortOrder: String?): Cursor = synchronized(lock) {
        documentCursor(projection, documents.values.filter { it.parentId == parentDocumentId })
    }

    override fun getDocumentType(documentId: String): String = synchronized(lock) {
        if (requireNode(documentId).directory) DocumentsContract.Document.MIME_TYPE_DIR else "image/svg+xml"
    }

    override fun openDocument(documentId: String, mode: String, signal: CancellationSignal?): ParcelFileDescriptor {
        throw FileNotFoundException(documentId)
    }

    override fun deleteDocument(documentId: String) {
        synchronized(lock) {
            val node = requireNode(documentId)
            if (!node.deletable || node.directory) throw FileNotFoundException(documentId)
            documents.remove(node.id)
        }
    }

    override fun isChildDocument(parentDocumentId: String, documentId: String): Boolean = synchronized(lock) {
        var current = documents[documentId]
        while (current != null) {
            if (current.id == parentDocumentId) return@synchronized true
            current = documents[current.parentId]
        }
        false
    }

    private fun documentCursor(projection: Array<String>?, nodes: List<Node>): Cursor {
        val columns = projection ?: DOCUMENT_COLUMNS
        return MatrixCursor(columns).also { cursor ->
            nodes.forEach { node ->
                val row = cursor.newRow()
                columns.forEach { column ->
                    row.add(column, when (column) {
                        DocumentsContract.Document.COLUMN_DOCUMENT_ID -> node.id
                        DocumentsContract.Document.COLUMN_DISPLAY_NAME -> node.name
                        DocumentsContract.Document.COLUMN_MIME_TYPE -> if (node.directory) DocumentsContract.Document.MIME_TYPE_DIR else "image/svg+xml"
                        DocumentsContract.Document.COLUMN_SIZE -> if (node.directory) null else node.sizeBytes
                        DocumentsContract.Document.COLUMN_LAST_MODIFIED -> node.modifiedMillis
                        DocumentsContract.Document.COLUMN_FLAGS -> if (node.deletable) DocumentsContract.Document.FLAG_SUPPORTS_DELETE else 0
                        else -> null
                    })
                }
            }
        }
    }

    private fun requireNode(documentId: String): Node = documents[documentId] ?: throw FileNotFoundException(documentId)

    private data class Node(
        val id: String,
        val name: String,
        val parentId: String?,
        val directory: Boolean,
        val deletable: Boolean,
        var sizeBytes: Long?,
        var modifiedMillis: Long
    )

    companion object {
        const val AUTHORITY = "com.yeoback.preview.fixture.documents"
        const val ROOT_ID = "root"
        const val EXPORT_ID = "export"
        const val CHANGING_ID = "changing"
        const val ORIGINAL_ID = "original"
        private val lock = Any()
        private val documents = linkedMapOf<String, Node>()
        private val DOCUMENT_COLUMNS = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            DocumentsContract.Document.COLUMN_FLAGS
        )

        fun resetForTest() = synchronized(lock) {
            val now = 1_700_000_000_000L
            documents.clear()
            documents[ROOT_ID] = Node(ROOT_ID, "Fixture root", null, true, false, null, now)
            documents["drafts"] = Node("drafts", "drafts", ROOT_ID, true, false, null, now)
            documents[EXPORT_ID] = Node(EXPORT_ID, "export.svg", "drafts", false, true, 48L, now)
            documents[CHANGING_ID] = Node(CHANGING_ID, "changing.svg", "drafts", false, true, 64L, now)
            documents[ORIGINAL_ID] = Node(ORIGINAL_ID, "original.txt", ROOT_ID, false, true, 96L, now)
        }

        fun rewriteForTest(documentId: String) = synchronized(lock) {
            val node = requireTestNode(documentId)
            node.sizeBytes = (node.sizeBytes ?: 0L) + 1L
            node.modifiedMillis += 1L
        }

        fun containsForTest(documentId: String): Boolean = synchronized(lock) { documents.containsKey(documentId) }

        private fun requireTestNode(documentId: String): Node = documents[documentId] ?: error("Missing fixture document: $documentId")
    }
}

class FixtureGrantHostActivity : androidx.activity.ComponentActivity() {
    private val picker = registerForActivityResult(androidx.activity.result.contract.ActivityResultContracts.StartActivityForResult()) { result ->
        onTreeReturned?.invoke(result.data?.data)
    }
    var onTreeReturned: ((android.net.Uri?) -> Unit)? = null

    fun requestFixtureTree() {
        picker.launch(Intent(this, FixtureTreePickerActivity::class.java))
    }
}

class FixtureTreePickerActivity : Activity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        val treeUri = DocumentsContract.buildTreeDocumentUri(FixtureDocumentsProvider.AUTHORITY, FixtureDocumentsProvider.ROOT_ID)
        setResult(
            RESULT_OK,
            Intent().setData(treeUri).addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
            )
        )
        finish()
    }
}
