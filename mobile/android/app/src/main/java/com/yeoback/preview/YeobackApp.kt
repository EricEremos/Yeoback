package com.yeoback.preview

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.yeoback.preview.domain.AgeFilter
import com.yeoback.preview.domain.ArtifactCategory
import com.yeoback.preview.domain.Candidate
import com.yeoback.preview.domain.ReviewedSelection
import com.yeoback.preview.domain.SizeFilter
import com.yeoback.preview.domain.SortOrder
import java.text.DateFormat
import java.util.Date

@Composable
fun YeobackApp(viewModel: YeobackViewModel = viewModel()) {
    val state by viewModel.state.collectAsState()
    val folderLauncher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree(), viewModel::onTreePicked)
    YeobackTheme {
        Surface(modifier = Modifier.fillMaxSize()) {
            val reviewedSelection = state.review
            if (reviewedSelection != null) {
                ReviewScreen(reviewedSelection, state.phase == ScanPhase.Deleting, viewModel::closeReview, viewModel::deleteReviewed)
            } else {
                CandidateScreen(
                    state = state,
                    chooseFolder = { folderLauncher.launch(null) },
                    cancelScan = viewModel::cancelScan,
                    updateQuery = { query -> viewModel.updateFilter { it.copy(query = query) } },
                    updateCategory = { category -> viewModel.updateFilter { filter ->
                        val next = filter.categories.toMutableSet().apply { if (!add(category)) remove(category) }
                        filter.copy(categories = next)
                    } },
                    updateSize = { size -> viewModel.updateFilter { it.copy(size = size) } },
                    updateAge = { age -> viewModel.updateFilter { it.copy(age = age) } },
                    updateSort = { sort -> viewModel.updateFilter { it.copy(sort = sort) } },
                    toggleSelection = viewModel::toggleSelection,
                    selectAll = { viewModel.selectAllVisibleEligible(System.currentTimeMillis()) },
                    clearSelection = viewModel::clearSelection,
                    review = { viewModel.openReview(System.currentTimeMillis()) }
                )
            }
        }
    }
}

@Composable
internal fun CandidateScreen(
    state: YeobackUiState,
    chooseFolder: () -> Unit,
    cancelScan: () -> Unit,
    updateQuery: (String) -> Unit,
    updateCategory: (ArtifactCategory) -> Unit,
    updateSize: (SizeFilter) -> Unit,
    updateAge: (AgeFilter) -> Unit,
    updateSort: (SortOrder) -> Unit,
    toggleSelection: (String) -> Unit,
    selectAll: () -> Unit,
    clearSelection: () -> Unit,
    review: () -> Unit
) {
    val now = remember(state.candidates, state.filter) { System.currentTimeMillis() }
    val visible = state.visibleCandidates(now)
    Scaffold(
        modifier = Modifier.fillMaxSize(),
        bottomBar = {
            if (state.candidates.isNotEmpty()) {
                SelectionActionBar(
                    matchingCount = visible.size,
                    selectedCount = state.selectedUris.size,
                    canReview = state.selectedUris.isNotEmpty() && state.phase == ScanPhase.Complete,
                    selectAll = selectAll,
                    clearSelection = clearSelection,
                    review = review
                )
            }
        }
    ) { scaffoldPadding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(scaffoldPadding),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
        item {
            Text("YEOBACK", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            Text("Candidates in a folder", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
            Text("Choose a folder to inspect portable filename and folder clues. This preview does not scan Photos or the whole device.")
        }
        item {
            Button(
                onClick = chooseFolder,
                enabled = state.phase != ScanPhase.Scanning && state.phase != ScanPhase.Deleting,
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
            ) { Text("Choose a folder") }
        }
        state.source?.let { source -> item { Text("Source: ${source.providerLabel} · selected through Android’s folder picker") } }
        state.notice?.let { notice -> item { StatusCard(notice) } }
        if (state.phase == ScanPhase.Scanning) {
            item {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("Scanning selected folder", fontWeight = FontWeight.SemiBold)
                        Text("${state.progress?.visited ?: 0} entries inspected · ${state.progress?.candidates ?: 0} candidates")
                        state.progress?.path?.takeIf(String::isNotBlank)?.let { Text(it, maxLines = 1, overflow = TextOverflow.Ellipsis) }
                        OutlinedButton(onClick = cancelScan, modifier = Modifier.heightIn(min = 48.dp)) { Text("Cancel scan") }
                    }
                }
            }
        }
        state.report?.let { report -> item { ScanReportCard(report) } }
        if (state.candidates.isNotEmpty()) {
            item {
                FilterPanel(state, updateQuery, updateCategory, updateSize, updateAge, updateSort)
            }
            items(visible, key = { "candidate:${it.uri}" }) { candidate ->
                CandidateRow(candidate, candidate.uri in state.selectedUris, toggleSelection)
            }
        }
        state.deletionReport?.let { report ->
            item { Text("Provider outcomes", style = MaterialTheme.typography.titleLarge) }
            items(report.outcomes, key = { "outcome:${it.uri}" }) { outcome ->
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text(outcome.relativePath, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        Text(outcome.detail)
                    }
                }
            }
        }
        }
    }
}

@Composable
private fun SelectionActionBar(
    matchingCount: Int,
    selectedCount: Int,
    canReview: Boolean,
    selectAll: () -> Unit,
    clearSelection: () -> Unit,
    review: () -> Unit
) {
    Surface(tonalElevation = 3.dp) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text("$matchingCount matching · $selectedCount selected", style = MaterialTheme.typography.labelLarge)
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = selectAll, modifier = Modifier.weight(1f).heightIn(min = 48.dp)) { Text("Select all matches") }
                OutlinedButton(onClick = clearSelection, modifier = Modifier.weight(1f).heightIn(min = 48.dp)) { Text("Clear") }
            }
            Button(onClick = review, enabled = canReview, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                Text("Review exact selection")
            }
        }
    }
}

@Composable
private fun FilterPanel(
    state: YeobackUiState,
    updateQuery: (String) -> Unit,
    updateCategory: (ArtifactCategory) -> Unit,
    updateSize: (SizeFilter) -> Unit,
    updateAge: (AgeFilter) -> Unit,
    updateSort: (SortOrder) -> Unit
) {
    var expanded by rememberSaveable { mutableStateOf(false) }
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            TextButton(onClick = { expanded = !expanded }, modifier = Modifier.heightIn(min = 48.dp)) {
                Text(if (expanded) "Hide filters & sort" else "Filters & sort")
            }
            if (expanded) {
                OutlinedTextField(value = state.filter.query, onValueChange = updateQuery, label = { Text("Search name or path") }, modifier = Modifier.fillMaxWidth())
                Text("Category")
                FlowChips(ArtifactCategory.entries.toList(), state.filter.categories, { it.label }, updateCategory)
                Text("Size · unknown size never matches a minimum")
                FlowChips(SizeFilter.entries.toList(), setOf(state.filter.size), { it.label }, updateSize)
                Text("Age · unknown modification time never matches an age filter")
                FlowChips(AgeFilter.entries.toList(), setOf(state.filter.age), { it.label }, updateAge)
                Text("Sort")
                FlowChips(SortOrder.entries.toList(), setOf(state.filter.sort), { it.label }, updateSort)
            }
        }
    }
}

@Composable
@OptIn(ExperimentalLayoutApi::class)
private fun <T> FlowChips(values: List<T>, selected: Set<T>, label: (T) -> String, onClick: (T) -> Unit) {
    FlowRow(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        values.forEach { value ->
            FilterChip(
                selected = value in selected,
                onClick = { onClick(value) },
                label = { Text(label(value)) },
                modifier = Modifier.heightIn(min = 48.dp)
            )
        }
    }
}

@Composable
internal fun CandidateRow(candidate: Candidate, selected: Boolean, toggleSelection: (String) -> Unit) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .semantics { contentDescription = "${candidate.relativePath}. ${candidate.reason}" }
    ) {
        Column(modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Checkbox(checked = selected, enabled = candidate.selectableForDeletion, onCheckedChange = { toggleSelection(candidate.uri) })
                Spacer(Modifier.width(8.dp))
                Text(candidate.relativePath, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
            Column(modifier = Modifier.padding(start = 52.dp)) {
                Text(candidate.category.label)
                Text(candidate.reason, style = MaterialTheme.typography.bodySmall)
                Text(candidateEligibilityText(candidate), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.secondary)
            }
        }
    }
}

private fun candidateEligibilityText(candidate: Candidate): String = when {
    candidate.selectableForDeletion -> "Eligible for review; provider deletion remains revalidated."
    !candidate.supportsDelete -> "Review only; provider did not advertise deletion."
    !candidate.fingerprint.isReliable -> "Review only; metadata is incomplete, so identity cannot be revalidated."
    else -> "Review only."
}

@Composable
private fun ScanReportCard(report: com.yeoback.preview.domain.ScanReport) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text("${report.visited} inspected · ${report.skipped} skipped" + if (report.partial) " · Partial scan" else " · Scan complete")
            report.issues.forEach { Text(it, style = MaterialTheme.typography.bodySmall) }
        }
    }
}

@Composable
private fun StatusCard(message: String) {
    Card(modifier = Modifier.fillMaxWidth()) { Text(message, modifier = Modifier.padding(16.dp)) }
}

@Composable
internal fun ReviewScreen(review: ReviewedSelection, deleting: Boolean, back: () -> Unit, delete: () -> Unit) {
    var deleteConfirmationOpen by remember { mutableStateOf(false) }
    Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background, contentColor = MaterialTheme.colorScheme.onBackground) {
        LazyColumn(modifier = Modifier.fillMaxSize(), contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item {
                Text("Review exact selection", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                Text("${review.items.size} items frozen at ${DateFormat.getDateTimeInstance().format(Date(review.reviewedAtMillis))}. The list below will be revalidated before every provider mutation.")
            }
            item { StatusCard("Deletion is irreversible from this preview. The provider may not offer Trash or Undo. Canceling this review deletes nothing.") }
            items(review.items, key = Candidate::uri) { candidate ->
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text(candidate.relativePath, fontWeight = FontWeight.SemiBold)
                        Text(candidate.reason)
                        val modified = candidate.fingerprint.lastModifiedMillis?.let { DateFormat.getDateTimeInstance().format(Date(it)) } ?: "Unknown"
                        Text("${candidate.fingerprint.sizeBytes ?: "Unknown"} bytes · Modified $modified")
                    }
                }
            }
            item {
                OutlinedButton(onClick = back, enabled = !deleting, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("Cancel review") }
            }
            item {
                Button(onClick = { deleteConfirmationOpen = true }, enabled = !deleting && review.items.isNotEmpty(), modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                    Text(if (deleting) "Deleting…" else "Delete permanently")
                }
            }
        }
    }
    if (deleteConfirmationOpen) {
        AlertDialog(
            onDismissRequest = { deleteConfirmationOpen = false },
            title = { Text("Permanently delete ${review.items.size} reviewed items?") },
            text = { Text("This sends each item to its provider for irreversible deletion. The preview does not promise Trash or Undo. Every item will be revalidated first.") },
            dismissButton = { TextButton(onClick = { deleteConfirmationOpen = false }) { Text("Keep files") } },
            confirmButton = {
                TextButton(modifier = Modifier.testTag("confirm-provider-deletion"), onClick = {
                    deleteConfirmationOpen = false
                    delete()
                }) { Text("Delete permanently") }
            }
        )
    }
}

private val LightColors = lightColorScheme(
    primary = Color(0xFFAE3529), onPrimary = Color(0xFFFFFEFA), primaryContainer = Color(0xFFE6E9E1), onPrimaryContainer = Color(0xFF252C27),
    inversePrimary = Color(0xFFFF9988), secondary = Color(0xFF62675F), onSecondary = Color(0xFFFFFEFA), secondaryContainer = Color(0xFFE6E9E1), onSecondaryContainer = Color(0xFF252C27),
    tertiary = Color(0xFF62675F), onTertiary = Color(0xFFFFFEFA), tertiaryContainer = Color(0xFFE6E9E1), onTertiaryContainer = Color(0xFF252C27),
    background = Color(0xFFF5F3EF), onBackground = Color(0xFF252C27), surface = Color(0xFFFFFEFA), onSurface = Color(0xFF252C27), surfaceVariant = Color(0xFFE6E9E1), onSurfaceVariant = Color(0xFF62675F),
    surfaceTint = Color(0xFFAE3529), inverseSurface = Color(0xFF252C27), inverseOnSurface = Color(0xFFFFFEFA), error = Color(0xFFAE3529), onError = Color(0xFFFFFEFA), errorContainer = Color(0xFFFFDAD5), onErrorContainer = Color(0xFF3B0804),
    outline = Color(0xFFC5C9BF), outlineVariant = Color(0xFFE6E9E1), scrim = Color.Black,
    surfaceDim = Color(0xFFE6E9E1), surfaceBright = Color(0xFFFFFEFA),
    surfaceContainerLowest = Color(0xFFFFFEFA), surfaceContainerLow = Color(0xFFF5F3EF),
    surfaceContainer = Color(0xFFEFF0E9), surfaceContainerHigh = Color(0xFFE6E9E1), surfaceContainerHighest = Color(0xFFDDE1D7)
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFFFF9988), onPrimary = Color(0xFF52110B), primaryContainer = Color(0xFF7B2118), onPrimaryContainer = Color(0xFFFFDAD5),
    inversePrimary = Color(0xFFAE3529), secondary = Color(0xFFB8BDB4), onSecondary = Color(0xFF252725), secondaryContainer = Color(0xFF353A35), onSecondaryContainer = Color(0xFFF1EEE8),
    tertiary = Color(0xFFB8BDB4), onTertiary = Color(0xFF252725), tertiaryContainer = Color(0xFF353A35), onTertiaryContainer = Color(0xFFF1EEE8),
    background = Color(0xFF1D1F1E), onBackground = Color(0xFFF1EEE8), surface = Color(0xFF252725), onSurface = Color(0xFFF1EEE8), surfaceVariant = Color(0xFF353A35), onSurfaceVariant = Color(0xFFB8BDB4),
    surfaceTint = Color(0xFFFF9988), inverseSurface = Color(0xFFF1EEE8), inverseOnSurface = Color(0xFF1D1F1E), error = Color(0xFFFF9988), onError = Color(0xFF52110B), errorContainer = Color(0xFF7B2118), onErrorContainer = Color(0xFFFFDAD5),
    outline = Color(0xFF535D52), outlineVariant = Color(0xFF353A35), scrim = Color.Black,
    surfaceDim = Color(0xFF1D1F1E), surfaceBright = Color(0xFF353A35),
    surfaceContainerLowest = Color(0xFF171918), surfaceContainerLow = Color(0xFF252725),
    surfaceContainer = Color(0xFF2B2F2B), surfaceContainerHigh = Color(0xFF353A35), surfaceContainerHighest = Color(0xFF40463F)
)

@Composable
internal fun YeobackTheme(
    darkTheme: Boolean = androidx.compose.foundation.isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    MaterialTheme(colorScheme = if (darkTheme) DarkColors else LightColors, content = content)
}
