import AppKit
import SwiftUI

struct TrackedFolder: Codable, Identifiable {
    let id: UUID
    let path: String
    var snapshots: [GrowthSnapshot] = []
    var url: URL { URL(fileURLWithPath: path) }
}

@MainActor final class GrowthModel: ObservableObject {
    static let maximumFolders = 12
    @Published private(set) var folders: [TrackedFolder] = []
    @Published var selectedID: UUID? {
        didSet { issue = nil; incompleteMeasurement = nil; inaccessiblePaths = [] }
    }
    @Published private(set) var busy = false
    @Published private(set) var visited = 0
    @Published private(set) var issue: String?
    @Published private(set) var incompleteMeasurement: GrowthSnapshot?
    @Published private(set) var inaccessiblePaths: [String] = []
    @Published private(set) var persistenceIssue: String?
    private var task: Task<GrowthScan, Never>?
    private var choosingFolder = false
    private let stateURL: URL

    var selected: TrackedFolder? { folders.first { $0.id == selectedID } }

    init() {
        stateURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cleanup/growth.json")
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return }
        do {
            let values = try stateURL.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true, let bytes = values.fileSize, bytes < 4_000_000 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let saved = try JSONDecoder().decode([TrackedFolder].self, from: Data(contentsOf: stateURL))
            guard saved.count <= Self.maximumFolders, Set(saved.map(\.id)).count == saved.count,
                  saved.allSatisfy({ folder in
                      folder.path.hasPrefix("/") && folder.snapshots.count <= 12 &&
                      folder.snapshots.allSatisfy { snapshot in
                          snapshot.buckets.count <= 512 && snapshot.visited >= 0 &&
                          snapshot.buckets.values.allSatisfy { $0 >= 0 && $0 < Int64.max / 512 }
                      }
                  }) else { throw CocoaError(.fileReadCorruptFile) }
            folders = saved
            selectedID = saved.first?.id
        } catch {
            persistenceIssue = "Saved growth history could not be read. The original file has been preserved. \(error.localizedDescription)"
        }
    }

    func chooseFolder() {
        guard !busy, !choosingFolder, folders.count < Self.maximumFolders, persistenceIssue == nil else { return }
        choosingFolder = true
        defer { choosingFolder = false }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Track folder"
        panel.message = "Choose a folder to measure."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let existing = folders.first(where: { $0.path == url.standardizedFileURL.path }) {
            selectedID = existing.id
        } else {
            guard folders.count < Self.maximumFolders else { return }
            let folder = TrackedFolder(id: UUID(), path: url.standardizedFileURL.path)
            folders.append(folder)
            selectedID = folder.id
            save()
        }
        measure()
    }

    func measure() {
        guard !busy, persistenceIssue == nil, let selected else { return }
        busy = true
        visited = 0
        issue = nil
        incompleteMeasurement = nil
        inaccessiblePaths = []
        let id = selected.id
        let root = selected.url
        let owner = self
        let scan = Task.detached(priority: .utility) {
            GrowthLedger.scan(root: root) { count in
                if count % 256 == 0 {
                    Task { @MainActor in
                        if owner.busy { owner.visited = count }
                    }
                }
            }
        }
        task = scan
        Task {
            let result = await scan.value
            busy = false
            task = nil
            issue = result.issue
            inaccessiblePaths = result.inaccessiblePaths
            incompleteMeasurement = result.incompleteSnapshot
            if let partial = result.incompleteSnapshot { visited = partial.visited }
            guard let snapshot = result.snapshot,
                  let index = folders.firstIndex(where: { $0.id == id }) else { return }
            visited = snapshot.visited
            if let previous = folders[index].snapshots.last, previous.rootKey != snapshot.rootKey {
                folders[index].snapshots.removeAll()
                issue = "The folder identity changed. A new baseline was started."
            }
            folders[index].snapshots.append(snapshot)
            folders[index].snapshots = Array(folders[index].snapshots.suffix(12))
            save()
        }
    }

    func cancel() { task?.cancel() }

    func stopTracking() {
        guard !busy, let selectedID else { return }
        folders.removeAll { $0.id == selectedID }
        self.selectedID = folders.first?.id
        issue = nil
        save()
    }

    private func save() {
        guard persistenceIssue == nil else { return }
        do {
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(folders).write(to: stateURL, options: .atomic)
        } catch {
            persistenceIssue = "Growth history could not be saved. \(error.localizedDescription)"
        }
    }
}
