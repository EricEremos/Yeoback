import Foundation
import Darwin

struct FileStamp: Equatable, Sendable {
    let device: Int32
    let inode: UInt64
    let bytes: Int64
    let modified: Int64
    let nanos: Int64
    let changed: Int64
    let changeNanos: Int64
    let mode: UInt16
    let links: UInt16
    var regular: Bool { mode & UInt16(S_IFMT) == UInt16(S_IFREG) }
    var directory: Bool { mode & UInt16(S_IFMT) == UInt16(S_IFDIR) }
    static func read(_ url: URL) throws -> Self {
        var s = stat()
        guard lstat(url.path, &s) == 0 else { throw FolderError.message("File is unavailable or permission was revoked.") }
        return Self(device: s.st_dev, inode: s.st_ino, bytes: s.st_size,
                    modified: Int64(s.st_mtimespec.tv_sec), nanos: Int64(s.st_mtimespec.tv_nsec),
                    changed: Int64(s.st_ctimespec.tv_sec), changeNanos: Int64(s.st_ctimespec.tv_nsec),
                    mode: s.st_mode, links: s.st_nlink)
    }
}

enum FolderError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

struct FolderItem: Identifiable, Sendable {
    var id: String { url.path }
    let url: URL
    let relativePath: String
    let stamp: FileStamp
    let ancestors: [String: FileStamp]
    let clue: String?
    var bytes: Int64 { stamp.bytes }
    var modified: Date { Date(timeIntervalSince1970: TimeInterval(stamp.modified)) }
}

struct FolderInventory: Sendable {
    let root: URL
    let rootStamp: FileStamp
    var items: [FolderItem] = []
    var visited = 0
    var skipped = 0
    var issues: [String] = []
    var partial = false
}

final class ScanCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

enum ArtifactGroup: String, CaseIterable, Identifiable {
    case all = "All files", artifacts = "Work leftovers", svg = "SVG", drafts = "Drafts & exports", records = "Work records"
    var id: String { rawValue }
    func matches(_ item: FolderItem, root: URL) -> Bool {
        switch self {
        case .all: return true
        case .artifacts: return item.clue != nil
        case .svg: return item.url.pathExtension.lowercased() == "svg"
        case .drafts: return WorkArtifact.draftClue(item.url, root: root)
        case .records: return WorkArtifact.recordClue(item.url, root: root)
        }
    }
}

enum FolderSort: String, CaseIterable, Identifiable {
    case largest = "Largest first", smallest = "Smallest first", oldest = "Oldest first", newest = "Newest first", name = "Name"
    var id: String { rawValue }
}

struct FolderFilter {
    var query = ""
    var group: ArtifactGroup = .artifacts
    var minimumBytes: Int64 = 0
    var olderThanDays = 0
    var sort: FolderSort = .largest
    func apply(_ inventory: FolderInventory, kept: Set<String>, now: Date = Date()) -> [FolderItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return inventory.items.filter {
            !kept.contains($0.id) && group.matches($0, root: inventory.root) && $0.bytes >= minimumBytes &&
            (needle.isEmpty || $0.relativePath.localizedCaseInsensitiveContains(needle)) &&
            (olderThanDays == 0 || $0.modified <= now.addingTimeInterval(-Double(olderThanDays) * 86400))
        }.sorted {
            switch sort {
            case .largest: if $0.bytes != $1.bytes { return $0.bytes > $1.bytes }
            case .smallest: if $0.bytes != $1.bytes { return $0.bytes < $1.bytes }
            case .oldest: if $0.modified != $1.modified { return $0.modified < $1.modified }
            case .newest: if $0.modified != $1.modified { return $0.modified > $1.modified }
            case .name: break
            }
            return $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
    }
}

struct RemovalOutcome: Identifiable, Sendable {
    let id: String
    let name: String
    let deleted: Bool
    let message: String
    let logicalBytes: Int64
}

enum FolderEngine {
    static func sameDirectory(_ current: FileStamp, _ original: FileStamp) -> Bool {
        current.directory && original.directory && current.device == original.device && current.inode == original.inode
    }

    static func scan(root: URL, cancellation: ScanCancellation, limit: Int = 20_000,
                     seconds: TimeInterval = 30, progress: @Sendable (Int, Int) -> Void = { _, _ in }) throws -> FolderInventory {
        let root = root.standardizedFileURL
        let rootStamp = try FileStamp.read(root)
        guard rootStamp.directory, root.resolvingSymlinksInPath().path == root.path else {
            throw FolderError.message("Choose a regular folder, not a symbolic link.")
        }
        var inventory = FolderInventory(root: root, rootStamp: rootStamp)
        var queue: [(URL, [String: FileStamp])] = [(root, [:])]
        let start = Date()
        var lastProgress = Date.distantPast
        while let (folder, ancestors) = queue.popLast() {
            if cancellation.cancelled || inventory.visited >= limit || Date().timeIntervalSince(start) >= seconds {
                inventory.partial = true; break
            }
            do {
                let coordinator = NSFileCoordinator(filePresenter: nil)
                var coordinationError: NSError?
                var folderError: Error?
                coordinator.coordinate(readingItemAt: folder, options: .withoutChanges, error: &coordinationError) { location in
                    do {
                        guard let values = FileManager.default.enumerator(at: location, includingPropertiesForKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .isPackageKey], options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants], errorHandler: { _, error in
                            folderError = error
                            return false
                        }) else { throw FolderError.message("The folder could not be enumerated.") }
                        while let rawURL = values.nextObject() as? URL {
                            let url = rawURL.standardizedFileURL
                            if cancellation.cancelled || inventory.visited >= limit || Date().timeIntervalSince(start) >= seconds {
                                inventory.partial = true; break
                            }
                            inventory.visited += 1
                            do {
                                guard url.standardizedFileURL.path.hasPrefix(root.path + "/") else { inventory.skipped += 1; continue }
                                let metadata = try url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .isPackageKey])
                                if metadata.isUbiquitousItem == true && metadata.ubiquitousItemDownloadingStatus != .current {
                                    inventory.skipped += 1; continue
                                }
                                let stamp = try FileStamp.read(url)
                                if stamp.directory {
                                    guard metadata.isPackage != true, stamp.device == rootStamp.device else { inventory.skipped += 1; continue }
                                    var nextAncestors = ancestors
                                    nextAncestors[url.path] = stamp
                                    queue.append((url, nextAncestors))
                                } else if stamp.regular && stamp.links == 1 && stamp.bytes >= 0 && stamp.device == rootStamp.device {
                                    inventory.items.append(FolderItem(url: url, relativePath: String(url.path.dropFirst(root.path.count + 1)), stamp: stamp, ancestors: ancestors, clue: WorkArtifact.reason(for: url, root: root)))
                                } else { inventory.skipped += 1 }
                            } catch { inventory.skipped += 1; inventory.partial = true }
                            if Date().timeIntervalSince(lastProgress) > 0.15 {
                                progress(inventory.visited, inventory.items.count); lastProgress = Date()
                            }
                        }
                    } catch { folderError = error }
                }
                if let error = coordinationError ?? folderError as NSError? { throw error }
            } catch {
                inventory.partial = true
                if inventory.issues.count < 8 { inventory.issues.append("\(folder.lastPathComponent): \(error.localizedDescription)") }
            }
        }
        progress(inventory.visited, inventory.items.count)
        return inventory
    }

    static func validate(_ item: FolderItem, inventory: FolderInventory, at location: URL) throws {
        guard location.standardizedFileURL.path == item.url.path,
              item.url.path.hasPrefix(inventory.root.path + "/"),
              item.url.resolvingSymlinksInPath().path == item.url.path,
              sameDirectory(try FileStamp.read(inventory.root), inventory.rootStamp) else {
            throw FolderError.message("Folder access or location changed. Scan again.")
        }
        for (path, original) in item.ancestors {
            guard sameDirectory(try FileStamp.read(URL(fileURLWithPath: path)), original) else {
                throw FolderError.message("A parent folder changed. Scan again.")
            }
        }
        guard try FileStamp.read(location) == item.stamp else {
            throw FolderError.message("File changed since scanning. Kept for a new review.")
        }
    }

    static func remove(_ reviewed: [FolderItem], inventory: FolderInventory,
                       progress: @Sendable (Int, Int) -> Void = { _, _ in }) -> [RemovalOutcome] {
        var outcomes: [RemovalOutcome] = []
        var seen: Set<String> = []
        for item in reviewed where seen.insert(item.id).inserted {
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var coordinationError: NSError?
            var resultError: Error?
            var removed = false
            coordinator.coordinate(writingItemAt: item.url, options: .forDeleting, error: &coordinationError) { location in
                do {
                    try validate(item, inventory: inventory, at: location)
                    try FileManager.default.removeItem(at: location)
                    removed = !FileManager.default.fileExists(atPath: location.path)
                    if !removed { throw FolderError.message("Provider did not confirm removal.") }
                } catch { resultError = error }
            }
            let error = coordinationError ?? resultError as NSError?
            outcomes.append(RemovalOutcome(id: item.id, name: item.relativePath, deleted: removed && error == nil,
                message: error?.localizedDescription ?? (removed ? "Deleted" : "Provider did not complete deletion."), logicalBytes: item.bytes))
            progress(outcomes.count, reviewed.count)
        }
        return outcomes
    }
}
