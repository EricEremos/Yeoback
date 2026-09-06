import Foundation

@main struct MobileCoreCheck {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("Yeoback-core-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("exports"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let changed = root.appendingPathComponent("exports/draft.svg")
        let unchanged = root.appendingPathComponent("exports/old.svg")
        let original = root.appendingPathComponent("original.txt")
        for url in [changed, unchanged, original] { try Data("fixture".utf8).write(to: url) }
        let scan = try FolderEngine.scan(root: root, cancellation: ScanCancellation())
        precondition(scan.items.count == 3 && !scan.partial)
        let matching = FolderFilter().apply(scan, kept: [])
        precondition(matching.count == 2)
        try Data("changed fixture".utf8).write(to: changed)
        let outcomes = FolderEngine.remove(matching, inventory: scan)
        for outcome in outcomes { print("\(outcome.name): \(outcome.message)") }
        precondition(outcomes.filter(\.deleted).count == 1)
        precondition(FileManager.default.fileExists(atPath: changed.path))
        precondition(FileManager.default.fileExists(atPath: original.path))
        precondition(!FileManager.default.fileExists(atPath: unchanged.path))
        let token = ScanCancellation(); token.cancel()
        let partial = try FolderEngine.scan(root: root, cancellation: token)
        precondition(partial.partial && partial.items.isEmpty)
        print("PASS: native folder scan, artifact filter, changed-file rejection, exact removal, original preservation and cancellation")
    }
}
