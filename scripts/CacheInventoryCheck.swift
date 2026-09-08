import Foundation

@main struct CacheInventoryCheck {
    static func main() throws {
        if CommandLine.arguments.contains("--live") {
            let report = Storage.scanCaches(timeLimit: 180, locationTimeLimit: 15)
            print("\(report.items.count) locations; \(report.summary)")
            for item in report.items.sorted(by: { $0.bytes > $1.bytes }).prefix(20) {
                print("\(item.bytes)\t\(item.sizeComplete)\t\(item.reason)\t\(item.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
            }
            return
        }
        let fm = FileManager.default
        let home = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(".build/cache-inventory-\(UUID())")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        func expect(_ condition: Bool, _ message: String) throws {
            guard condition else { throw StorageError.message(message) }
            print("PASS: \(message)")
        }
        let folders = [".codex/sessions", ".codex/worktrees", ".codex/log", ".codex/plugins",
            "Library/Caches/example", "Library/Application Support/Example", "Library/Containers/example",
            "Library/Developer/Xcode/DerivedData", "Library/Logs/Example", ".cache/uv"]
        for path in folders {
            let folder = home.appendingPathComponent(path)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(repeating: 42, count: 8192).write(to: folder.appendingPathComponent("fixture.bin"))
        }
        let state = home.appendingPathComponent(".codex/state.sqlite")
        try Data(repeating: 1, count: 4096).write(to: state)
        try fm.linkItem(at: home.appendingPathComponent(".codex/sessions/fixture.bin"),
                        to: home.appendingPathComponent(".codex/sessions/hardlink.bin"))
        try fm.createSymbolicLink(at: home.appendingPathComponent(".codex/sessions/elsewhere"),
                                  withDestinationURL: home.appendingPathComponent("Library"))
        let report = Storage.scanCaches(home: home)
        try expect(!report.partial && report.items.count == folders.count + 1, "all Codex and Library buckets discovered")
        try expect(Set(report.items.map(\.id)).count == report.items.count, "inventory contains no duplicate paths")
        for path in folders {
            let item = report.items.first { $0.url == home.appendingPathComponent(path) }
            try expect(item != nil && item!.bytes > 0 && item!.sizeComplete, "measured \(path)")
        }
        let sessions = report.items.first { $0.url == home.appendingPathComponent(".codex/sessions") }!
        try expect(sessions.bytes == Storage.allocated(home.appendingPathComponent(".codex/sessions/fixture.bin")),
                   "hard links counted once and symlinks not followed")
        try expect(report.items.allSatisfy { !$0.selectable }, "app state and synthetic provider paths cannot be selected")
        for item in report.items {
            do { try Storage.validate(item); throw StorageError.message("Unexpected deletion eligibility") }
            catch let error as StorageError {
                try expect(!error.localizedDescription.contains("Unexpected"), "mutation rejects \(item.url.lastPathComponent)")
            }
        }
        let limited = Storage.scanCaches(home: home, maxEntries: 1)
        try expect(limited.partial && limited.items.count == report.items.count && limited.visited == 1,
                   "entry limit retains later locations as unmeasured")
        try expect(limited.items.filter { !$0.sizeComplete }.allSatisfy { !$0.selectable }, "partial sizes cannot authorize cleanup")
        let expired = Storage.scanCaches(home: home, timeLimit: 0)
        try expect(expired.items.count == report.items.count && expired.items.allSatisfy { !$0.sizeComplete && $0.bytes == 0 },
                   "expired deadline does not hide storage owners or claim zero complete size")
        let cloud = home.appendingPathComponent("Library/CloudStorage/Provider")
        try fm.createDirectory(at: cloud, withIntermediateDirectories: true)
        try Data(repeating: 42, count: 8192).write(to: cloud.appendingPathComponent("fixture.bin"))
        let cloudReport = Storage.scanCaches(home: home)
        let excluded = cloudReport.items.first { $0.url.lastPathComponent == "CloudStorage" }
        try expect(excluded != nil && excluded!.bytes == 0 && !excluded!.sizeComplete && !excluded!.selectable,
                   "cloud roots remain visible without traversing or claiming reclaimed space")
        try expect(fm.fileExists(atPath: state.path), "agent database remains untouched")
    }
}
