import Foundation
import Combine

@main struct BatchCheck {
    @MainActor static func main() async throws {
        let fm = FileManager.default
        let parent = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(".build/batch-check-\(UUID())")
        let root = parent.appendingPathComponent("documents")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: parent) }
        for index in 0..<97 {
            try Data("Disposable batch fixture \(index)".utf8).write(to: root.appendingPathComponent("\(index).txt"))
        }
        let inventory = Storage.scanDocuments(root: root, includeSmallFiles: true).items
        guard inventory.count == 97 else { fatalError("Fixture inventory mismatch") }
        let approved = Array(inventory.prefix(96))
        let changed = approved[0]
        try Data("This item changed after review and must survive".utf8).write(to: changed.url)
        let model = AppModel(stateURL: parent.appendingPathComponent("state.json"))
        model.items = inventory
        model.selection = Set(inventory.map(\.id))
        model.section = .documents
        model.plan = approved
        var inventoryUpdates = 0
        var saves = 0
        var journalSizes: [Int] = []
        var completed: [Int] = []
        let subscriptions: [AnyCancellable] = [
            model.$items.dropFirst().sink { _ in inventoryUpdates += 1 },
            model.$persistenceIssue.dropFirst().sink { _ in
                saves += 1
                journalSizes.append(model.state.pendingCleanup?.count ?? 0)
            },
            model.$operationCompleted.dropFirst().sink { completed.append($0) }
        ]
        let start = Date()
        model.executePlan()
        while model.removing { try await Task.sleep(nanoseconds: 10_000_000) }
        let elapsed = Date().timeIntervalSince(start)
        let entries = model.state.activity
        defer {
            for entry in entries where entry.success {
                if let path = entry.destination,
                   let original = approved.first(where: { $0.url.lastPathComponent == entry.name })?.url {
                    try? fm.moveItem(at: URL(fileURLWithPath: path), to: original)
                }
            }
        }
        func expect(_ condition: Bool, _ message: String) {
            guard condition else { fatalError(message) }
            print("PASS: \(message)")
        }
        expect(model.lastCleanup?.succeeded == 95 && model.lastCleanup?.failed == 1, "95 successes and one changed-file refusal are reported separately")
        expect(model.operationCompleted == 96 && completed == [0, 32, 64, 96], "Progress counts only completed batches and reaches the approved total")
        expect(inventoryUpdates == 1, "Inventory is reconciled once for 96 outcomes")
        expect(saves == 8 && journalSizes == [0, 32, 0, 32, 0, 32, 0, 0], "Each batch is journaled before mutation and cleared after outcomes, using eight writes for 96 items")
        expect(Set(model.items.map(\.id)) == [changed.id, inventory[96].id], "Failed and unapproved documents remain in the inventory")
        expect(model.selection == [changed.id, inventory[96].id], "Failed and unapproved selections survive")
        expect(fm.fileExists(atPath: changed.url.path) && fm.fileExists(atPath: inventory[96].url.path), "Changed and unapproved files remain on disk")
        expect(entries.count == 96 && entries.filter(\.success).count == 95, "Every batch outcome has its own activity record")
        expect(entries.filter(\.success).allSatisfy { entry in
            guard let destination = entry.destination,
                  let item = approved.first(where: { $0.url.lastPathComponent == entry.name }) else { return false }
            return fm.fileExists(atPath: destination) && !fm.fileExists(atPath: item.url.path)
        }, "Every reported success has a real native Trash destination")
        let saved = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: parent.appendingPathComponent("state.json")))
        expect(saved.activity.count == 96 && model.persistenceIssue == nil, "Batch outcomes persist to the isolated state file")
        expect(model.returnSection == .documents && model.section == .activity, "Result flow preserves its originating inventory")
        let cached = Candidate(url: changed.url, root: changed.root, rootIdentity: changed.rootIdentity, identity: changed.identity,
                               bytes: changed.bytes, modified: changed.modified, kind: .cache, reason: "Boundary fixture", selectable: false, bundleID: nil)
        expect(CleanupExecutor.batchEnd(in: [approved[1], cached, approved[2]], from: 0) == 1
               && CleanupExecutor.batchEnd(in: [cached, approved[1]], from: 0) == 1, "Provider operations remain isolated from document batches")
        withExtendedLifetime(subscriptions) {}
        print("96 reviewed fixtures completed in \(String(format: "%.3f", elapsed)) seconds; all moved fixtures restored afterward.")
    }
}
