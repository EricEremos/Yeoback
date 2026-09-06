package com.yeoback.preview

import android.app.Application
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.yeoback.preview.data.SafRepository
import com.yeoback.preview.domain.Candidate
import com.yeoback.preview.domain.CandidateFilter
import com.yeoback.preview.domain.DeletionReport
import com.yeoback.preview.domain.ReviewPlanner
import com.yeoback.preview.domain.ReviewedSelection
import com.yeoback.preview.domain.ScanProgress
import com.yeoback.preview.domain.ScanReport
import com.yeoback.preview.domain.SourceGrant
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicBoolean

sealed interface ScanPhase {
    data object Idle : ScanPhase
    data object Scanning : ScanPhase
    data object Complete : ScanPhase
    data object Deleting : ScanPhase
}

data class YeobackUiState(
    val source: SourceGrant? = null,
    val phase: ScanPhase = ScanPhase.Idle,
    val candidates: List<Candidate> = emptyList(),
    val report: ScanReport? = null,
    val progress: ScanProgress? = null,
    val filter: CandidateFilter = CandidateFilter(),
    val selectedUris: Set<String> = emptySet(),
    val review: ReviewedSelection? = null,
    val deletionReport: DeletionReport? = null,
    val notice: String? = null
) {
    fun visibleCandidates(nowMillis: Long): List<Candidate> = filter.apply(candidates, nowMillis)

    fun selectionAfterSelectAllVisible(nowMillis: Long): Set<String> =
        selectedUris + visibleCandidates(nowMillis)
            .asSequence()
            .filter(Candidate::selectableForDeletion)
            .map(Candidate::uri)
            .toSet()
}

class YeobackViewModel(application: Application) : AndroidViewModel(application) {
    private val repository = SafRepository(application)
    private val cancelRequested = AtomicBoolean(false)
    private val _state = MutableStateFlow(YeobackUiState())
    val state: StateFlow<YeobackUiState> = _state.asStateFlow()

    fun onTreePicked(uri: Uri?) {
        if (_state.value.phase == ScanPhase.Scanning || _state.value.phase == ScanPhase.Deleting) return
        if (uri == null) {
            _state.value = _state.value.copy(notice = "Folder chooser cancelled. No source was added.")
            return
        }
        val source = repository.takeReadWriteGrant(uri)
        if (source == null || !source.hasReadWriteGrant) {
            _state.value = _state.value.copy(notice = "This preview needs a read/write folder grant to scan and later offer provider deletion. No source was added.")
            return
        }
        beginScan(source)
    }

    fun cancelScan() {
        if (_state.value.phase == ScanPhase.Scanning) cancelRequested.set(true)
    }

    fun updateFilter(transform: (CandidateFilter) -> CandidateFilter) {
        _state.value = _state.value.copy(filter = transform(_state.value.filter))
    }

    fun toggleSelection(uri: String) {
        val current = _state.value
        if (current.phase != ScanPhase.Complete || current.review != null) return
        val candidate = current.candidates.firstOrNull { it.uri == uri } ?: return
        if (!candidate.selectableForDeletion) return
        _state.value = current.copy(selectedUris = current.selectedUris.toMutableSet().apply {
            if (!add(uri)) remove(uri)
        })
    }

    fun selectAllVisibleEligible(nowMillis: Long) {
        val current = _state.value
        if (current.phase != ScanPhase.Complete || current.review != null) return
        _state.value = current.copy(
            selectedUris = current.selectionAfterSelectAllVisible(nowMillis)
        )
    }

    fun clearSelection() {
        val current = _state.value
        if (current.phase == ScanPhase.Complete && current.review == null) {
            _state.value = current.copy(selectedUris = emptySet())
        }
    }

    fun openReview(nowMillis: Long) {
        val current = _state.value
        if (current.phase != ScanPhase.Complete || current.review != null) return
        val source = current.source ?: return
        val frozen = ReviewPlanner.freeze(source, current.candidates, current.selectedUris, nowMillis)
        _state.value = current.copy(review = frozen, notice = if (frozen.items.isEmpty()) "No currently eligible items are selected." else null)
    }

    fun closeReview() { _state.value = _state.value.copy(review = null) }

    fun deleteReviewed() {
        val current = _state.value
        if (current.phase != ScanPhase.Complete) return
        val review = current.review ?: return
        _state.value = _state.value.copy(phase = ScanPhase.Deleting, notice = null)
        viewModelScope.launch {
            val deletion = repository.deleteReviewed(review)
            val deletedUris = deletion.outcomes.asSequence().filter { it.deleted }.map { it.uri }.toSet()
            _state.value = _state.value.copy(
                phase = ScanPhase.Complete,
                review = null,
                candidates = _state.value.candidates.filterNot { it.uri in deletedUris },
                selectedUris = emptySet(),
                deletionReport = deletion,
                notice = "Deletion finished. Each provider outcome is listed below."
            )
        }
    }

    private fun beginScan(source: SourceGrant) {
        if (_state.value.phase == ScanPhase.Scanning || _state.value.phase == ScanPhase.Deleting) return
        cancelRequested.set(false)
        _state.value = YeobackUiState(source = source, phase = ScanPhase.Scanning, notice = "Scanning metadata in the selected folder.")
        viewModelScope.launch {
            val result = repository.scan(source, cancelRequested::get) { progress ->
                _state.value = _state.value.copy(progress = progress)
            }
            _state.value = _state.value.copy(
                phase = ScanPhase.Complete,
                candidates = result.candidates,
                report = result.report,
                progress = null,
                notice = if (result.report.partial) "Partial scan. Review the boundary and errors below." else "Scan complete. Candidates are clues, not deletion advice."
            )
        }
    }
}
