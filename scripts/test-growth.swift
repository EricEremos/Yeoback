import Foundation

@main
struct GrowthCheck {
    static func main() async throws {
        let fm = FileManager.default
        let parent = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(".build/cleanup-growth-\(UUID().uuidString)")
        let root = parent.appendingPathComponent("documents")
        let alpha = root.appendingPathComponent("Alpha")
        let beta = root.appendingPathComponent("Beta")
        let outside = parent.appendingPathComponent("outside.txt")
        try fm.createDirectory(at: alpha, withIntermediateDirectories: true)
        try fm.createDirectory(at: beta, withIntermediateDirectories: true)
        try Data(repeating: 65, count: 16_384).write(to: alpha.appendingPathComponent("baseline.bin"))
        try Data(repeating: 66, count: 8_192).write(to: beta.appendingPathComponent("remove.bin"))
        try Data(repeating: 67, count: 4_096).write(to: outside)
        try fm.createSymbolicLink(at: root.appendingPathComponent("OutsideLink"), withDestinationURL: outside)
        defer { try? fm.removeItem(at: parent) }

        func check(_ name: String, _ condition: @autoclosure () -> Bool) throws {
            guard condition() else { throw GrowthError.failed(name) }
            print("PASS: \(name)")
        }
        func snapshot(_ scan: GrowthScan, _ name: String) throws -> GrowthSnapshot {
            guard let value = scan.snapshot, scan.issue == nil else {
                throw GrowthError.failed("\(name): \(scan.issue ?? "missing snapshot")")
            }
            return value
        }

        let baseline = try snapshot(GrowthLedger.scan(root: root), "baseline")
        try check("baseline records files", baseline.buckets["Alpha", default: 0] > 0 && baseline.buckets["Beta", default: 0] > 0)
        try check("symlink target is excluded", baseline.buckets["(Files in folder)", default: 0] == 0)

        try Data(repeating: 68, count: 24_576).write(to: alpha.appendingPathComponent("increase.bin"))
        let increased = try snapshot(GrowthLedger.scan(root: root), "increase")
        let increase = GrowthLedger.changes(previous: baseline, current: increased)
        try check("increase reports positive Alpha delta", increase.contains { $0.name == "Alpha" && $0.delta > 0 })

        try fm.removeItem(at: alpha.appendingPathComponent("increase.bin"))
        let decreased = try snapshot(GrowthLedger.scan(root: root), "decrease")
        let decrease = GrowthLedger.changes(previous: increased, current: decreased)
        try check("decrease reports negative Alpha delta", decrease.contains { $0.name == "Alpha" && $0.delta < 0 })

        try fm.removeItem(at: beta.appendingPathComponent("remove.bin"))
        let removed = try snapshot(GrowthLedger.scan(root: root), "removal")
        let removal = GrowthLedger.changes(previous: decreased, current: removed)
        try check("removal reports negative Beta delta", removal.contains { $0.name == "Beta" && $0.delta < 0 })

        let capped = GrowthLedger.scan(root: root, maxEntries: 1)
        try check("entry cap withholds snapshot", capped.snapshot == nil && capped.issue != nil)

        let cancelledTask = Task {
            GrowthLedger.scan(root: root, progress: { count in
                if count == 1 { withUnsafeCurrentTask { $0?.cancel() } }
            })
        }
        let cancelled = await cancelledTask.value
        try check("cancellation withholds snapshot", cancelled.snapshot == nil && cancelled.issue != nil)

        let otherRoot = GrowthSnapshot(date: Date(), rootKey: "different:root", buckets: removed.buckets, visited: removed.visited)
        try check("identity mismatch suppresses changes", GrowthLedger.changes(previous: removed, current: otherRoot).isEmpty)

        let history = [
            GrowthSnapshot(date: Date(timeIntervalSince1970: 1), rootKey: baseline.rootKey, buckets: ["Alpha": 100], visited: 1),
            GrowthSnapshot(date: Date(timeIntervalSince1970: 2), rootKey: baseline.rootKey, buckets: ["Alpha": 80], visited: 1),
            GrowthSnapshot(date: Date(timeIntervalSince1970: 3), rootKey: baseline.rootKey, buckets: ["Alpha": 120], visited: 1)
        ]
        try check("recurrence follows measured fall", GrowthLedger.recurrenceLabel(history, name: "Alpha") == "Growth recurred")
        try check("no recurrence before measured fall", GrowthLedger.recurrenceLabel([history[0], history[2]], name: "Alpha") == nil)
        print("Growth checks passed")
    }
}

enum GrowthError: Error {
    case failed(String)
}
