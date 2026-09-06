import SwiftUI
import AppKit

enum Section: String, CaseIterable, Identifiable {
    case overview = "Home", developer = "Clean up", applications = "Applications", documents = "Documents", growth = "Growth", review = "Review", activity = "Activity", reserve = "Reserve settings"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .developer: "externaldrive"
        case .applications: "app.dashed"
        case .documents: "doc"
        case .growth: "chart.line.uptrend.xyaxis"
        case .review: "checklist"
        case .activity: "clock.arrow.circlepath"
        case .reserve: "slider.horizontal.3"
        }
    }
}

struct Activity: Identifiable, Codable {
    let id: UUID
    let date: Date
    let name: String
    let detail: String
    let destination: String?
    let success: Bool
    var operation: String? = nil
}

struct CleanupResult {
    let succeeded: Int
    let failed: Int
    let before: Int64?
    let after: Int64?
    let caches: Int
    let trashed: Int
    var notStarted: Int = 0
}

struct SavedState: Codable {
    var targetGB: Double = 150
    var monitoring = true
    var history: [Capacity] = []
    var activity: [Activity] = []
    var pendingCleanup: [String]? = nil
}

@MainActor final class AppModel: ObservableObject {
    @Published var section: Section = .overview { didSet { refreshInventory() } }
    @Published var capacity: Capacity?
    @Published var state = SavedState()
    @Published var items: [Candidate] = [] { didSet { refreshInventory() } }
    @Published var selection = Set<String>() { didSet { if filter.selectedOnly { refreshInventory() } } }
    @Published var report: ScanReport?
    @Published var reports: [Section: ScanReport] = [:]
    @Published var scanSection: Section?
    @Published var busy = false
    @Published var removing = false
    @Published var stoppingCleanup = false
    @Published var filters: [Section: InventoryFilter] = [:] { didSet { refreshInventory() } }
    @Published private(set) var visibleItems: [Candidate] = []
    @Published var scanProgress = ScanProgress()
    @Published var scanStarted = Date()
    @Published var cancellingScan = false
    @Published var message: String?
    @Published var confirmation = false
    @Published var plan: [Candidate] = []
    @Published var documentRoot: URL?
    @Published var persistenceIssue: String?
    @Published var lastCleanup: CleanupResult?
    @Published var currentOperation = ""
    @Published var operationCompleted = 0
    @Published var operationTotal = 0
    @Published var returnSection: Section = .developer
    private var scanID = UUID()
    private var scanTask: Task<ScanReport, Never>?
    private var timer: Timer?
    private let stateURL: URL
    private var preservesUnreadableState = false

    init(stateURL: URL? = nil) {
        self.stateURL = stateURL ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Cleanup/state.json")
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: self.stateURL.path)
            guard let size = attributes[.size] as? NSNumber, size.intValue < 1_000_000 else {
                throw StorageError.message("The settings file exceeds the supported size.")
            }
            let saved = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: self.stateURL))
            state = saved
            state.targetGB = min(10_000, max(1, state.targetGB.isFinite ? state.targetGB : 150))
            state.history = Array(state.history.suffix(180))
            state.activity = Array(state.activity.prefix(100))
        } catch {
            let failure = error as NSError
            if !(failure.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(failure.code)) {
                preservesUnreadableState = true
                persistenceIssue = "Existing settings could not be read and have been preserved at \(self.stateURL.path). Changes in this session will not be saved. Repair or move that file, then reopen Yeoback. \(error.localizedDescription)"
            }
        }
        if !(state.pendingCleanup ?? []).isEmpty { section = .activity }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in if self?.state.monitoring == true { self?.refresh() } }
        }
    }

    var targetBytes: Int64 { Int64(state.targetGB * 1_000_000_000) }
    var shortfall: Int64 { max(0, targetBytes - (capacity?.free ?? 0)) }
    var selected: [Candidate] { items.filter { selection.contains($0.id) } }
    var selectedBytes: Int64 { selected.reduce(0) { $0 + $1.bytes } }
    var isInventory: Bool { [.documents, .applications, .developer].contains(section) }
    var inventoryKind: CandidateKind { section == .documents ? .document : section == .applications ? .application : .cache }
    var inventoryItems: [Candidate] { items.filter { $0.kind == inventoryKind } }
    var filter: InventoryFilter {
        get { filters[section] ?? InventoryFilter() }
        set { filters[section] = newValue }
    }
    private func refreshInventory() { visibleItems = filter.apply(inventoryItems, selection: selection) }
    var hiddenSelectionCount: Int { selection.subtracting(visibleItems.map(\.id)).count }

    func selectVisible(_ selected: Bool) {
        guard isInventory, !busy, !removing else { return }
        selection = InventoryFilter.selectingVisible(visibleItems, in: selection, selected: selected)
    }
    var candidateBytes: Int64 { items.filter(\.selectable).reduce(0) { $0 + $1.bytes } }
    var monitorLabel: String {
        guard let capacity else { return "Capacity unavailable" }
        return capacity.free >= targetBytes ? "Reserve met" : "Below reserve"
    }

    @discardableResult func save() -> Bool {
        guard !preservesUnreadableState else { return false }
        do {
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
            persistenceIssue = nil
            return true
        } catch {
            persistenceIssue = "Settings and activity could not be saved: \(error.localizedDescription)"
            return false
        }
    }

    func refresh() {
        do {
            let reading = try Capacity.read()
            capacity = reading
            state.history.append(reading)
            state.history = Array(state.history.suffix(180))
            save()
        } catch { message = error.localizedDescription }
    }

    func setTarget(_ value: Double) {
        guard value.isFinite else { return }
        state.targetGB = min(10_000, max(1, value))
        save()
    }

    func chooseFolder() {
        guard !busy, !removing else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose a folder to inspect"
        panel.message = "Only metadata is inspected. Files are never selected for removal automatically."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard Storage.documentRootAllowed(url) else { message = "Choose a personal document folder. System, app-data and symbolic-link paths are excluded."; return }
        documentRoot = url
        scan(.documents)
    }

    func scanDownloads() {
        guard !busy, !removing else { return }
        documentRoot = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        scan(.documents)
    }

    func scanHomeFolder() {
        guard !busy, !removing else { return }
        documentRoot = FileManager.default.homeDirectoryForCurrentUser
        scan(.documents)
    }

    func scan(_ destination: Section) {
        guard !busy, !removing else { return }
        if destination == .documents && documentRoot == nil { chooseFolder(); return }
        section = destination
        scanSection = destination
        busy = true
        cancellingScan = false
        scanStarted = Date()
        scanProgress = ScanProgress()
        let runID = UUID()
        scanID = runID
        let root = documentRoot
        let kind: CandidateKind = destination == .documents ? .document : destination == .applications ? .application : .cache
        let progress: @Sendable (ScanProgress) -> Void = { [weak self] value in
            Task { @MainActor in
                guard let self, self.busy, self.scanID == runID else { return }
                self.scanProgress = value
            }
        }
        let task = Task.detached(priority: .utility) {
            switch kind {
            case .document: return Storage.scanDocuments(root: root!, includeSmallFiles: true, progress: progress)
            case .application: return Storage.scanApplications(progress: progress)
            case .cache: return Storage.scanCaches(progress: progress)
            }
        }
        scanTask = task
        Task {
            let result = await task.value
            applyScan(result, kind: kind, root: root)
            report = result
            reports[destination] = result
            busy = false
            cancellingScan = false
            scanSection = nil
            scanTask = nil
        }
    }

    func cancelScan() { cancellingScan = true; scanTask?.cancel() }

    func applyScan(_ result: ScanReport, kind: CandidateKind, root: URL?) {
        let previous = items.filter { $0.kind == kind }
        let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        let fresh = Dictionary(uniqueKeysWithValues: result.items.map { ($0.id, $0) })
        // A partial report cannot prove absence. Retain only the same scan scope;
        // every retained candidate is still revalidated before a filesystem move.
        let retained = result.partial ? previous.filter {
            fresh[$0.id] == nil && (kind != .document || $0.root == root)
        } : []
        let replacement = result.items + retained
        let unchanged = Set(replacement.filter { item in
            item.selectable && previousByID[item.id]?.identity == item.identity && previousByID[item.id]?.treeStamp == item.treeStamp
        }.map(\.id))
        selection.subtract(Set(previous.map(\.id)).subtracting(unchanged))
        items.removeAll { $0.kind == kind }
        items.append(contentsOf: replacement)
    }

    func acknowledgeInterruptedCleanup() {
        guard !removing, let pending = state.pendingCleanup, !pending.isEmpty else { return }
        let prior = state
        state.activity.insert(Activity(id: UUID(), date: Date(), name: "Interrupted cleanup",
                                       detail: "Outcome unknown. Inspect these original locations and Trash before retrying:\n" + pending.joined(separator: "\n"),
                                       destination: nil, success: false, operation: "Reconciliation required"), at: 0)
        state.activity = Array(state.activity.prefix(100))
        state.pendingCleanup = nil
        if !save() { state = prior }
    }

    func toggle(_ item: Candidate) {
        guard item.selectable, !removing, !busy else { return }
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    func prepareReview() {
        guard !selected.isEmpty, !busy, !removing else { return }
        plan = selected
        confirmation = true
    }

    func prepareReview(_ item: Candidate) {
        guard item.selectable, !busy, !removing else { return }
        plan = [item]
        confirmation = true
    }

    func executePlan() {
        guard !removing, !busy, !plan.isEmpty else { return }
        guard state.pendingCleanup?.isEmpty != false else {
            confirmation = false
            section = .activity
            message = "Review the interrupted cleanup notice before starting another operation."
            return
        }
        guard save() else { confirmation = false; message = "Cleanup cannot start until its recovery record can be saved."; return }
        let approved = plan
        plan = []
        confirmation = false
        removing = true
        stoppingCleanup = false
        lastCleanup = nil
        returnSection = isInventory ? section : .developer
        operationCompleted = 0
        operationTotal = approved.count
        section = .activity
        Task {
            let before = try? Capacity.read().free
            var succeeded = 0
            var failed = 0
            var caches = 0
            var trashed = 0
            var removedIDs = Set<String>()
            var offset = 0
            while offset < approved.count && !stoppingCleanup {
                let end = CleanupExecutor.batchEnd(in: approved, from: offset)
                let batch = Array(approved[offset..<end])
                state.pendingCleanup = batch.map { $0.url.path }
                guard save() else { state.pendingCleanup = nil; break }
                currentOperation = batch[0].kind == .cache
                    ? "Cleaning \(batch[0].url.lastPathComponent)…"
                    : "Moving \(batch.count) \(batch.count == 1 ? "item" : "items") to Trash…"
                let outcomes = await Task.detached(priority: .userInitiated) { await CleanupExecutor.run(batch) }.value
                var entries: [Activity] = []
                for outcome in outcomes {
                    let item = outcome.item
                    if outcome.success {
                        succeeded += 1
                        if item.kind == .cache { caches += 1 } else { trashed += 1 }
                    } else { failed += 1 }
                    if outcome.success { removedIDs.insert(item.id) }
                    entries.append(Activity(id: UUID(), date: Date(), name: item.url.lastPathComponent,
                                            detail: outcome.detail, destination: outcome.destination?.path, success: outcome.success,
                                            operation: item.kind == .cache ? (outcome.success ? "Cache cleanup completed" : "Cache cleanup not completed") : (outcome.success ? nil : "Not moved to Trash")))
                }
                state.activity = Array((entries.reversed() + state.activity).prefix(100))
                operationCompleted += outcomes.count
                offset = end
                let pending = state.pendingCleanup
                state.pendingCleanup = nil
                if !save() { state.pendingCleanup = pending; break }
            }
            // Reconcile the inventory once, instead of filtering and sorting it for every file.
            selection.subtract(removedIDs)
            items.removeAll { removedIDs.contains($0.id) }
            removing = false
            currentOperation = ""
            refresh()
            lastCleanup = CleanupResult(succeeded: succeeded, failed: failed, before: before, after: try? Capacity.read().free, caches: caches, trashed: trashed, notStarted: approved.count - offset)
            stoppingCleanup = false
        }
    }

    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
}
