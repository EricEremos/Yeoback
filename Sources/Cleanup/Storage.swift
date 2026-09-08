import Foundation
import AppKit
import Darwin
import CryptoKit

struct Capacity: Codable, Sendable {
    let date: Date
    let total: Int64
    let free: Int64
    static func read() throws -> Capacity {
        let values = try URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        guard let total = values.volumeTotalCapacity, let free = values.volumeAvailableCapacity else {
            throw StorageError.message("macOS did not return volume capacity.")
        }
        return Capacity(date: Date(), total: Int64(total), free: Int64(free))
    }
}

enum StorageError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

struct Identity: Equatable, Sendable {
    let device: Int32
    let inode: UInt64
    let size: Int64
    let modifiedSeconds: Int64
    let modifiedNanos: Int64
    let mode: UInt16
    let links: UInt16
    var key: String { "\(device):\(inode)" }
    var isDirectory: Bool { mode & UInt16(S_IFMT) == UInt16(S_IFDIR) }
    var isRegular: Bool { mode & UInt16(S_IFMT) == UInt16(S_IFREG) }
    static func read(_ url: URL) throws -> Identity {
        var value = stat()
        guard lstat(url.path, &value) == 0 else { throw StorageError.message("Cannot inspect \(url.lastPathComponent): \(String(cString: strerror(errno)))") }
        return Identity(device: value.st_dev, inode: value.st_ino, size: value.st_size,
                        modifiedSeconds: Int64(value.st_mtimespec.tv_sec), modifiedNanos: Int64(value.st_mtimespec.tv_nsec),
                        mode: value.st_mode, links: value.st_nlink)
    }
}

enum CandidateKind: String, Sendable { case document, application, cache }

struct Candidate: Identifiable, Sendable {
    var id: String { url.path }
    let url: URL
    let root: URL
    let rootIdentity: Identity
    let identity: Identity
    let bytes: Int64
    let modified: Date
    let kind: CandidateKind
    let reason: String
    let selectable: Bool
    let bundleID: String?
    var treeStamp: String? = nil
    var sizeComplete: Bool = true
    var name: String { url.deletingPathExtension().lastPathComponent }
    var artifactReason: String? { kind == .document ? WorkArtifact.reason(for: url, root: root) : nil }
}

struct ScanReport: Sendable {
    var items: [Candidate] = []
    var visited = 0
    var skipped = 0
    var issues: [String] = []
    var partial = false
    var summary: String {
        "\(visited.formatted()) entries inspected · \(skipped.formatted()) skipped" + (partial ? " · Partial scan" : " · Scan complete")
    }
}

struct ScanProgress: Sendable {
    var visited = 0
    var candidates = 0
    var path = ""
}

private struct ProgressReporter {
    let callback: (@Sendable (ScanProgress) -> Void)?
    private var last = Date.distantPast
    init(_ callback: (@Sendable (ScanProgress) -> Void)?) { self.callback = callback }
    mutating func update(_ visited: Int, _ candidates: Int, _ path: String, force: Bool = false) {
        guard callback != nil, force || Date().timeIntervalSince(last) >= 0.15 else { return }
        last = Date()
        callback?(ScanProgress(visited: visited, candidates: candidates, path: path))
    }
}

enum Storage {
    static let documentExtensions: Set<String> = ["pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "pages", "key", "numbers", "rtf", "txt", "csv", "jpg", "jpeg", "png", "heic", "gif", "tiff", "mp4", "mov", "mkv", "avi", "mp3", "wav", "m4a", "zip", "7z", "tar", "gz", "dmg", "pkg", "iso", "svg", "webp", "md", "markdown", "json", "jsonl", "ndjson", "log", "html"]

    static func inside(_ url: URL, root: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let base = root.standardizedFileURL.path
        return path != base && path.hasPrefix(base == "/" ? "/" : base + "/")
    }

    static func noLinkAncestry(_ url: URL) -> Bool {
        var cursor = url.standardizedFileURL
        while cursor.path != "/" {
            guard let value = try? Identity.read(cursor), value.mode & UInt16(S_IFMT) != UInt16(S_IFLNK) else { return false }
            cursor.deleteLastPathComponent()
        }
        return true
    }

    static func documentRootAllowed(_ root: URL) -> Bool {
        let path = root.standardizedFileURL.path
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path
        let forbidden = ["/System", "/Library", "/Applications", "/bin", "/sbin", "/usr", "/private", "/dev", home + "/Library", home + "/Applications"]
        return path != "/" && !forbidden.contains { path == $0 || path.hasPrefix($0 + "/") } && noLinkAncestry(root)
    }

    static func allocated(_ url: URL) -> Int64 {
        guard let value = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]) else { return 0 }
        return Int64(value.totalFileAllocatedSize ?? value.fileAllocatedSize ?? 0)
    }

    static func scanDocuments(root raw: URL, limit: Int = 10_000_000, timeLimit: TimeInterval = 3_600, includeSmallFiles: Bool = false, progress: (@Sendable (ScanProgress) -> Void)? = nil) -> ScanReport {
        let root = raw.standardizedFileURL
        var result = ScanReport()
        var reporter = ProgressReporter(progress)
        defer { reporter.update(result.visited, result.items.count, root.path, force: true) }
        guard limit > 0, timeLimit > 0 else {
            result.partial = true
            result.issues = ["Scan entry and time limits must be positive."]
            return result
        }
        guard documentRootAllowed(root), let rootID = try? Identity.read(root), rootID.isDirectory else {
            result.issues = ["Choose a personal document folder with no symbolic-link ancestors. System and application-data folders are excluded."]
            result.partial = true
            return result
        }
        let start = Date()
        var seen = Set<String>()
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isPackageKey, .isUbiquitousItemKey, .isHiddenKey], options: [.skipsPackageDescendants], errorHandler: { url, error in
            if result.issues.count < 8 { result.issues.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            result.partial = true
            return true
        })
        while let url = enumerator?.nextObject() as? URL {
            if Task.isCancelled || result.visited >= limit || Date().timeIntervalSince(start) >= timeLimit {
                result.partial = true
                let cause = Task.isCancelled ? "Scan cancelled." : result.visited >= limit ? "Scan reached its \(limit.formatted())-entry limit." : "Scan reached its \(timeLimit.formatted())-second limit."
                result.issues.append(cause + " Results cover only inspected entries; choose a smaller folder to continue.")
                break
            }
            result.visited += 1
            reporter.update(result.visited, result.items.count, url.deletingLastPathComponent().path)
            guard let identity = try? Identity.read(url), identity.device == rootID.device else { result.skipped += 1; enumerator?.skipDescendants(); continue }
            let values = try? url.resourceValues(forKeys: [.isHiddenKey, .isUbiquitousItemKey])
            let hidden = url.lastPathComponent.hasPrefix(".") || values?.isHidden == true
            let recordFolder = includeSmallFiles && identity.isDirectory && WorkArtifact.hiddenRecordFolders.contains(url.lastPathComponent.lowercased())
            if values?.isUbiquitousItem == true || (hidden && !recordFolder) || !WorkArtifact.allowsRecordTraversal(url) {
                result.skipped += 1
                if identity.isDirectory { enumerator?.skipDescendants() }
                continue
            }
            if identity.isDirectory {
                if ["Library", "node_modules", "vendor", "Pods", "build", "dist"].contains(url.lastPathComponent) { enumerator?.skipDescendants() }
                continue
            }
            guard identity.isRegular, documentExtensions.contains(url.pathExtension.lowercased()), seen.insert(identity.key).inserted else { result.skipped += 1; continue }
            let protectedRecord = WorkArtifact.isProtectedRecord(url)
            if protectedRecord && !WorkArtifact.recordClue(url, root: root) { result.skipped += 1; continue }
            let date = Date(timeIntervalSince1970: TimeInterval(identity.modifiedSeconds))
            let old = Date().timeIntervalSince(date) > 180 * 86400
            guard includeSmallFiles || identity.size >= 25_000_000 || (old && identity.size >= 1_000_000) else { continue }
            let reason = identity.size >= 25_000_000 ? "Large file · review whether you still need it" : old && identity.size >= 1_000_000 ? "Unchanged for over 180 days · age does not imply unused" : "Personal file · review whether you still need it"
            result.items.append(Candidate(url: url, root: root, rootIdentity: rootID, identity: identity, bytes: allocated(url), modified: date, kind: .document,
                                          reason: protectedRecord ? "Agent workspace record · inspect in Finder; excluded from removal" : identity.links > 1 ? "Hard-linked file · inspect in Finder; excluded from removal" : reason,
                                          selectable: identity.links == 1 && !protectedRecord, bundleID: nil))
        }
        if enumerator == nil { result.partial = true; result.issues.append("macOS could not enumerate this folder. Check access in System Settings.") }
        result.items.sort { $0.bytes > $1.bytes }
        return result
    }

    static func directorySize(_ root: URL, deadline: Date, count: inout Int, progress: (@Sendable (ScanProgress) -> Void)? = nil, candidates: Int = 0) -> (Int64, Bool, String) {
        guard let rootID = try? Identity.read(root), noLinkAncestry(root) else { return (0, false, "") }
        var bytes: Int64 = 0
        var seen = Set<String>()
        var records: [String] = []
        var complete = true
        var reporter = ProgressReporter(progress)
        let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [], errorHandler: { _, _ in complete = false; return true })
        while let url = e?.nextObject() as? URL {
            if Task.isCancelled || count >= 1_000_000 || Date() > deadline { return (bytes, false, "") }
            count += 1
            reporter.update(count, candidates, root.path)
            guard let identity = try? Identity.read(url), identity.device == rootID.device else { e?.skipDescendants(); complete = false; continue }
            records.append("\(url.path.dropFirst(root.path.count))|\(identity.device)|\(identity.inode)|\(identity.size)|\(identity.modifiedSeconds)|\(identity.modifiedNanos)|\(identity.mode)|\(identity.links)")
            if identity.isRegular && seen.insert(identity.key).inserted { bytes += allocated(url) }
        }
        let stamp = SHA256.hash(data: Data(records.sorted().joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
        return (bytes, complete && e != nil, stamp)
    }

    static func scanApplications(progress: (@Sendable (ScanProgress) -> Void)? = nil) -> ScanReport {
        var report = ScanReport()
        let deadline = Date().addingTimeInterval(45)
        for root in [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")] {
            guard let rootID = try? Identity.read(root), let children = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for url in children.sorted(by: { $0.path < $1.path }) where url.pathExtension == "app" {
                if Task.isCancelled || Date() > deadline || report.visited >= 1_000_000 { report.partial = true; break }
                guard noLinkAncestry(url), let identity = try? Identity.read(url), identity.isDirectory else { report.skipped += 1; continue }
                let size = directorySize(url, deadline: deadline, count: &report.visited, progress: progress, candidates: report.items.count)
                let identifier = Bundle(url: url)?.bundleIdentifier
                let protected = identifier == nil || identifier?.hasPrefix("com.apple.") == true || url.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
                report.items.append(Candidate(url: url, root: root, rootIdentity: rootID, identity: identity, bytes: size.0,
                                              modified: Date(timeIntervalSince1970: TimeInterval(identity.modifiedSeconds)), kind: .application,
                                              reason: protected ? "Protected application · view only" : (size.1 ? "App bundle only · documents and support data stay in place" : "Partial size estimate · rescan before removal"),
                                              selectable: !protected && size.1, bundleID: identifier, treeStamp: size.1 ? size.2 : nil))
                if !size.1 { report.partial = true }
            }
        }
        report.items.sort { $0.bytes > $1.bytes }
        if report.partial { report.issues.append("Inventory reached a time/entry limit or encountered unreadable content. Partial bundles cannot be selected.") }
        return report
    }

    static func scanCaches(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                           maxEntries: Int = 10_000_000, timeLimit: TimeInterval = 3_600,
                           locationTimeLimit: TimeInterval = 120,
                           progress: (@Sendable (ScanProgress) -> Void)? = nil) -> ScanReport {
        var report = ScanReport()
        let deadline = Date().addingTimeInterval(max(0, timeLimit))
        // Expand storage owners once so a large early folder cannot hide later locations.
        let expanded: Set<String> = ["Library", "Library/Caches", "Library/Application Support",
            "Library/Containers", "Library/Group Containers", "Library/Logs", "Library/Developer",
            "Library/Developer/Xcode", ".codex", ".claude", ".cache", ".npm", ".ollama"]
        var locations: [URL] = []
        func discover(_ url: URL) {
            guard noLinkAncestry(url), let identity = try? Identity.read(url) else {
                report.skipped += 1; return
            }
            let relative = String(url.path.dropFirst(home.path.count + 1))
            if identity.isDirectory && expanded.contains(relative) {
                do {
                    let children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                    for child in children.sorted(by: { $0.path < $1.path }) { discover(child) }
                } catch {
                    locations.append(url)
                }
            } else if identity.isDirectory || identity.isRegular { locations.append(url) }
        }
        for path in [".codex", ".claude", ".cache", ".npm", ".ollama", "Library"] {
            let url = home.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: url.path) { discover(url) }
        }
        for url in locations {
            if Task.isCancelled { report.partial = true; break }
            guard let identity = try? Identity.read(url),
                  let rootID = try? Identity.read(url.deletingLastPathComponent()) else { continue }
            let relative = String(url.path.dropFirst(home.path.count + 1))
            let cloud = relative == "Library/CloudStorage" || relative == "Library/Mobile Documents"
            let size = cloud ? (Int64(0), false) : storageSize(url,
                deadline: min(deadline, Date().addingTimeInterval(max(0, locationTimeLimit))),
                maxEntries: maxEntries, count: &report.visited, progress: progress, candidates: report.items.count)
            let provider = CacheProvider.matching(url)
            let supported = provider?.executable != nil && size.1 && size.0 > 0
            let category: String
            if relative.hasPrefix(".codex/") || relative.hasPrefix(".claude/") {
                let name = url.lastPathComponent
                category = ["sessions", "archived_sessions", "projects"].contains(name) ? "Saved conversations"
                    : name == "worktrees" ? "Project worktrees"
                    : ["log", "logs", "debug"].contains(name) ? "Agent logs"
                    : "Agent data"
            } else if relative.hasPrefix("Library/Caches/") || relative.hasPrefix(".cache/") || relative.hasPrefix(".npm/") {
                category = "App-managed cache"
            } else if relative.hasPrefix("Library/Logs/") { category = "App logs" }
            else if relative.hasPrefix("Library/Developer/") { category = "Developer data" }
            else { category = "App data" }
            let reason = cloud ? "Cloud-managed files · inspect in Finder"
                : !size.1 ? "\(category) · partial size · inspect in Finder"
                : supported ? "\(provider!.action) · permanent cache cleanup"
                : "\(category) · view only"
            report.items.append(Candidate(url: url, root: url.deletingLastPathComponent(), rootIdentity: rootID, identity: identity, bytes: size.0,
                                          modified: Date(timeIntervalSince1970: TimeInterval(identity.modifiedSeconds)), kind: .cache,
                                          reason: reason, selectable: supported, bundleID: nil, sizeComplete: size.1))
            report.partial = report.partial || !size.1
        }
        report.items.sort { $0.selectable != $1.selectable ? $0.selectable : $0.bytes > $1.bytes }
        if report.partial { report.issues.append("Some sizes are incomplete: access, cloud storage, cancellation or scan limits. Inspect the marked locations in Finder.") }
        return report
    }

    // Inspection needs allocated blocks, not the sorted content fingerprint used for app removal.
    private static func storageSize(_ root: URL, deadline: Date, maxEntries: Int, count: inout Int,
                                    progress: (@Sendable (ScanProgress) -> Void)?, candidates: Int) -> (Int64, Bool) {
        guard noLinkAncestry(root), let rootID = try? Identity.read(root) else { return (0, false) }
        var bytes: Int64 = 0
        var complete = true
        var seen = Set<UInt64>()
        var reporter = ProgressReporter(progress)
        func inspect(_ url: URL) -> Bool {
            var info = stat()
            guard lstat(url.path, &info) == 0, info.st_dev == rootID.device else { complete = false; return false }
            guard info.st_mode & UInt16(S_IFMT) != UInt16(S_IFLNK) else { return false }
            if info.st_mode & UInt16(S_IFMT) == UInt16(S_IFDIR) {
                guard let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey]), values.isUbiquitousItem != true else {
                    complete = false; return false
                }
            }
            if info.st_mode & UInt16(S_IFMT) == UInt16(S_IFREG), seen.insert(info.st_ino).inserted {
                bytes += Int64(info.st_blocks) * 512
            }
            return true
        }
        guard !Task.isCancelled, count < maxEntries, Date() < deadline else { return (0, false) }
        count += 1
        guard inspect(root) else { return (bytes, complete) }
        if rootID.isDirectory {
            guard let entries = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                options: [], errorHandler: { _, _ in complete = false; return true }) else { return (bytes, false) }
            while let url = entries.nextObject() as? URL {
                if Task.isCancelled || count >= maxEntries || Date() >= deadline { complete = false; break }
                count += 1
                reporter.update(count, candidates, root.path)
                if !inspect(url) { entries.skipDescendants() }
            }
        }
        reporter.update(count, candidates, root.path, force: true)
        return (bytes, complete)
    }

    static func validate(_ item: Candidate) throws {
        guard item.selectable, item.kind != .cache, inside(item.url, root: item.root), noLinkAncestry(item.url),
              let rootID = try? Identity.read(item.root), rootID.device == item.rootIdentity.device, rootID.inode == item.rootIdentity.inode,
              try Identity.read(item.url) == item.identity else { throw StorageError.message("File changed, scope changed, or item is protected. Scan and review it again.") }
        if item.kind == .document {
            guard documentRootAllowed(item.root), !WorkArtifact.isProtectedRecord(item.url), item.identity.isRegular, item.identity.links == 1,
                  documentExtensions.contains(item.url.pathExtension.lowercased()) else { throw StorageError.message("This is not an eligible personal document.") }
        } else {
            let roots = ["/Applications", NSHomeDirectory() + "/Applications"]
            guard roots.contains(item.root.path), item.url.deletingLastPathComponent() == item.root,
                  item.url.pathExtension == "app", item.identity.isDirectory,
                  Bundle(url: item.url)?.bundleIdentifier == item.bundleID,
                  item.bundleID?.hasPrefix("com.apple.") != true,
                  item.url.standardizedFileURL != Bundle.main.bundleURL.standardizedFileURL else { throw StorageError.message("Application is outside the allowed uninstall scope.") }
            guard !NSWorkspace.shared.runningApplications.contains(where: { $0.bundleURL?.standardizedFileURL == item.url.standardizedFileURL || (item.bundleID != nil && $0.bundleIdentifier == item.bundleID) }) else {
                throw StorageError.message("Quit this application before uninstalling it.")
            }
            var inspected = 0
            let current = directorySize(item.url, deadline: Date().addingTimeInterval(15), count: &inspected)
            guard current.1, let stamp = item.treeStamp, current.2 == stamp else {
                throw StorageError.message("Application contents changed or could not be fully revalidated. Scan and review it again.")
            }
        }
    }

    static func trash(_ item: Candidate) throws -> URL? {
        try validate(item)
        guard try Identity.read(item.url) == item.identity, noLinkAncestry(item.url) else {
            throw StorageError.message("The reviewed item changed during validation. Scan again.")
        }
        if item.kind == .application && NSWorkspace.shared.runningApplications.contains(where: { $0.bundleURL?.standardizedFileURL == item.url.standardizedFileURL || (item.bundleID != nil && $0.bundleIdentifier == item.bundleID) }) {
            throw StorageError.message("The application is now running. Quit it before uninstalling.")
        }
        var destination: NSURL?
        try FileManager.default.trashItem(at: item.url, resultingItemURL: &destination)
        return destination as URL?
    }
}

func sizeText(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .decimal)
}
