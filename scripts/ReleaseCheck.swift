import Foundation
import AppKit

@main struct ReleaseCheck {
    @MainActor static func main() async throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(".build/release-check-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        func expect(_ condition: Bool, _ message: String) {
            guard condition else { fatalError(message) }
            print("PASS: \(message)")
        }
        let corruptURL = root.appendingPathComponent("corrupt.json")
        let corrupt = Data("{invalid disposable settings".utf8)
        try corrupt.write(to: corruptURL)
        let corruptModel = AppModel(stateURL: corruptURL)
        corruptModel.setTarget(230)
        corruptModel.refresh()
        expect(try Data(contentsOf: corruptURL) == corrupt, "Malformed state survives initialization, refresh and settings changes byte-for-byte")
        expect(corruptModel.persistenceIssue != nil, "Malformed state exposes a persistent recovery warning")
        let oversizedURL = root.appendingPathComponent("oversized.json")
        let oversized = Data(repeating: 32, count: 1_000_001)
        try oversized.write(to: oversizedURL)
        let oversizedModel = AppModel(stateURL: oversizedURL)
        oversizedModel.save()
        expect(try Data(contentsOf: oversizedURL) == oversized && oversizedModel.persistenceIssue != nil, "Oversized state is preserved and reported")
        let directoryURL = root.appendingPathComponent("directory.json")
        try fm.createDirectory(at: directoryURL, withIntermediateDirectories: false)
        let unreadableModel = AppModel(stateURL: directoryURL)
        unreadableModel.save()
        var directory: ObjCBool = false
        expect(fm.fileExists(atPath: directoryURL.path, isDirectory: &directory) && directory.boolValue && unreadableModel.persistenceIssue != nil, "Unreadable state path is not replaced")
        let stateURL = root.appendingPathComponent("new/state.json")
        let model = AppModel(stateURL: stateURL)
        model.setTarget(205)
        let saved = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: stateURL))
        expect(saved.targetGB == 205 && model.persistenceIssue == nil, "Missing state initializes and persists normally")
        let loaded = AppModel(stateURL: stateURL)
        expect(loaded.state.targetGB == 205 && loaded.persistenceIssue == nil, "Valid state loads without reset")
        let file = root.appendingPathComponent("refused-cache.txt")
        try Data("Disposable rejected candidate; no provider will run".utf8).write(to: file)
        let candidate = Candidate(url: file, root: root, rootIdentity: try Identity.read(root), identity: try Identity.read(file), bytes: 1,
                                  modified: Date(), kind: .cache, reason: "Refused fixture", selectable: false, bundleID: nil)
        model.items = [candidate]
        model.selection = [candidate.id]
        model.plan = [candidate]
        model.executePlan()
        while model.removing { try await Task.sleep(nanoseconds: 10_000_000) }
        expect(model.lastCleanup?.failed == 1 && model.lastCleanup?.succeeded == 0, "Rejected cache job reports failure")
        expect(model.items.map(\.id) == [candidate.id] && model.selection == [candidate.id] && fm.fileExists(atPath: file.path), "Failed cache candidate and selection remain; fixture is untouched")
        let delegate = AppDelegate()
        delegate.model = model
        expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow, "Idle termination remains allowed")
        let lockURL = root.appendingPathComponent("application.lock")
        var firstLock: ApplicationLock? = ApplicationLock()
        let secondLock = ApplicationLock()
        expect(try firstLock!.acquire(at: lockURL), "First process lock succeeds")
        expect(try !secondLock.acquire(at: lockURL), "Second writer is refused")
        firstLock = nil
        expect(try secondLock.acquire(at: lockURL), "Lock is released when its owner exits")

        let documents = root.appendingPathComponent("documents")
        try fm.createDirectory(at: documents, withIntermediateDirectories: true)
        for index in 0..<65 { try Data("Disposable document \(index)".utf8).write(to: documents.appendingPathComponent("item-\(index).txt")) }
        let inventory = Storage.scanDocuments(root: documents, includeSmallFiles: true)
        expect(inventory.items.count == 65 && !inventory.partial, "Complete fixture scan discovers all 65 files")
        model.items = inventory.items
        model.selection = Set(inventory.items.map(\.id))
        model.applyScan(ScanReport(items: Array(inventory.items.prefix(1)), partial: true), kind: .document, root: documents)
        expect(model.items.count == 65 && model.selection.count == 65, "Partial rescan preserves same-scope unseen results and selections")
        model.applyScan(ScanReport(partial: true), kind: .document, root: root.appendingPathComponent("different"))
        expect(model.items.isEmpty && model.selection.isEmpty, "Changing folders does not retain old-scope results")

        model.items = inventory.items
        model.selection = Set(inventory.items.map(\.id))
        model.plan = inventory.items
        model.executePlan()
        model.stoppingCleanup = true
        while model.removing { try await Task.sleep(nanoseconds: 10_000_000) }
        expect(model.lastCleanup?.notStarted == 65 && model.selection.count == 65, "Stop before first batch leaves every file selected and untouched")
        expect(inventory.items.allSatisfy { fm.fileExists(atPath: $0.url.path) }, "Stopped plan performs no mutation")

        model.state.pendingCleanup = [documents.appendingPathComponent("item-0.txt").path]
        expect(model.save(), "Pending cleanup is persisted before mutations")
        let recovered = AppModel(stateURL: stateURL)
        expect(recovered.state.pendingCleanup?.count == 1, "Relaunch retains interrupted paths without replay")
        expect(recovered.section == .activity, "Relaunch immediately presents the interrupted cleanup notice")
        recovered.plan = inventory.items
        recovered.executePlan()
        expect(!recovered.removing && recovered.section == .activity, "Unresolved recovery blocks another cleanup")
        recovered.acknowledgeInterruptedCleanup()
        expect(recovered.state.pendingCleanup == nil && recovered.state.activity.first?.operation == "Reconciliation required", "Acknowledgement preserves unknown outcomes in Activity")
        expect(inventory.items.allSatisfy { fm.fileExists(atPath: $0.url.path) }, "Recovery never replays filesystem operations")
    }
}
