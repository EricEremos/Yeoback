import XCTest
@testable import Yeoback

final class FolderEngineTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("Yeoback-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { if let root { try FileManager.default.removeItem(at: root) } }
    @discardableResult
    func file(_ name: String, bytes: Int = 16) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 65, count: bytes).write(to: url)
        return url
    }
    func testClassificationAndCompleteMatchingSelection() throws {
        for n in 0..<25 { try file("exports/draft-\(n).svg", bytes: n + 1) }
        try file("original.txt")
        try file("session.jsonl")
        let report = try FolderEngine.scan(root: root, cancellation: ScanCancellation())
        XCTAssertEqual(report.items.count, 27)
        var filter = FolderFilter()
        XCTAssertEqual(filter.apply(report, kept: []).count, 26)
        filter.group = .svg
        XCTAssertEqual(Set(filter.apply(report, kept: []).map(\.id)).count, 25)
        filter.query = "draft-24"
        XCTAssertEqual(filter.apply(report, kept: []).count, 1)
        filter.minimumBytes = 26
        XCTAssertEqual(filter.apply(report, kept: []).count, 0)
    }
    func testChangedFileIsKeptWhileUnchangedFileDeletes() throws {
        let changed = try file("draft.svg")
        let safe = try file("old.svg")
        let report = try FolderEngine.scan(root: root, cancellation: ScanCancellation())
        try Data("Changed after review".utf8).write(to: changed)
        let outcomes = FolderEngine.remove(report.items, inventory: report)
        XCTAssertEqual(outcomes.filter(\.deleted).count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: changed.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: safe.path))
    }
    func testParentReplacementAndSymlinkAreRejected() throws {
        try file("exports/draft.svg")
        let report = try FolderEngine.scan(root: root, cancellation: ScanCancellation())
        try FileManager.default.moveItem(at: root.appendingPathComponent("exports"), to: root.appendingPathComponent("saved"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("exports"), withDestinationURL: root.appendingPathComponent("saved"))
        let outcomes = FolderEngine.remove(report.items, inventory: report)
        XCTAssertTrue(outcomes.allSatisfy { !$0.deleted })
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("saved/draft.svg").path))
    }
    func testCancelledAndLimitedScansAreExplicitlyPartial() throws {
        for n in 0..<10 { try file("draft-\(n).svg") }
        let token = ScanCancellation(); token.cancel()
        let cancelled = try FolderEngine.scan(root: root, cancellation: token)
        XCTAssertTrue(cancelled.partial); XCTAssertEqual(cancelled.items.count, 0)
        let limited = try FolderEngine.scan(root: root, cancellation: ScanCancellation(), limit: 3)
        XCTAssertTrue(limited.partial); XCTAssertEqual(limited.visited, 3)
    }
    func testMissingFileAndDuplicateReviewCannotDeleteTwice() throws {
        let url = try file("draft.svg")
        let report = try FolderEngine.scan(root: root, cancellation: ScanCancellation())
        try FileManager.default.removeItem(at: url)
        let outcomes = FolderEngine.remove(report.items + report.items, inventory: report)
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertFalse(outcomes[0].deleted)
    }
}
