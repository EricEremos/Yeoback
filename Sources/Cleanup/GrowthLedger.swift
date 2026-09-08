import Foundation
import AppKit
import Darwin

struct GrowthSnapshot: Codable, Sendable, Equatable {
    let date: Date
    let rootKey: String
    let buckets: [String: Int64]
    let visited: Int
}

struct GrowthScan: Sendable {
    let snapshot: GrowthSnapshot?
    let issue: String?
    var incompleteSnapshot: GrowthSnapshot? = nil
    var inaccessiblePaths: [String] = []
}

struct GrowthChange: Codable, Sendable, Equatable {
    let name: String
    let bytes: Int64
    let delta: Int64
}

enum GrowthLedger {
    private static let maxBucketCount = 512
    private static let allocationBlockSize: Int64 = 512
    private static let filesInRoot = "(Files in folder)"

    static func scan(root rawRoot: URL,
                     maxEntries: Int = 10_000_000,
                     timeLimit: TimeInterval = 3_600,
                     progress: @Sendable (Int) -> Void = { _ in }) -> GrowthScan {
        guard maxEntries > 0 else { return GrowthScan(snapshot: nil, issue: "Growth scan entry limit must be positive.") }
        guard timeLimit > 0 else { return GrowthScan(snapshot: nil, issue: "Growth scan time limit must be positive.") }

        let root = rawRoot.standardizedFileURL
        guard noSymlinkAncestry(root) else {
            return GrowthScan(snapshot: nil, issue: "Growth scan requires a directory with no symbolic-link ancestors.")
        }
        guard let rootIdentity = lstatIdentity(root), rootIdentity.isDirectory else {
            return GrowthScan(snapshot: nil, issue: "Growth scan root is missing or is not a directory.")
        }
        guard let volume = try? root.resourceValues(forKeys: [.volumeIsLocalKey]),
              volume.volumeIsLocal == true else {
            return GrowthScan(snapshot: nil, issue: "macOS did not identify whether the volume is local.")
        }
        if isUbiquitous(root) {
            return GrowthScan(snapshot: nil, issue: "Cloud-synced roots are outside the growth scan scope.")
        }

        let started = Date()
        var visited = 0
        var buckets: [String: Int64] = [:]
        var seenFiles = Set<String>()
        var issue: String?
        var inaccessiblePaths: [String] = []

        func fail(_ message: String) {
            if issue == nil { issue = message }
        }

        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isUbiquitousItemKey],
            options: [],
            errorHandler: { url, error in
                let failure = error as NSError
                if (failure.domain == NSCocoaErrorDomain && failure.code == NSFileReadNoPermissionError) ||
                    (failure.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(failure.code)) {
                    if inaccessiblePaths.count < 8 && !inaccessiblePaths.contains(url.path) { inaccessiblePaths.append(url.path) }
                }
                fail("Could not inspect \(url.lastPathComponent): \(error.localizedDescription)")
                return true
            }
        )
        guard let enumerator else {
            return GrowthScan(snapshot: nil, issue: "macOS could not enumerate the growth scan root.")
        }

        while let url = enumerator.nextObject() as? URL {
            if Task.isCancelled {
                issue = "Growth scan was cancelled."
                break
            }
            if visited >= maxEntries {
                issue = "Growth scan reached its \(maxEntries.formatted())-entry limit."
                break
            }
            if Date().timeIntervalSince(started) >= timeLimit {
                issue = "Growth scan reached its \(timeLimit.formatted())-second limit."
                break
            }
            visited += 1
            progress(visited)

            guard let identity = lstatIdentity(url) else {
                if [EACCES, EPERM].contains(errno), inaccessiblePaths.count < 8, !inaccessiblePaths.contains(url.path) { inaccessiblePaths.append(url.path) }
                fail("Could not inspect \(url.lastPathComponent).")
                enumerator.skipDescendants()
                continue
            }
            guard identity.device == rootIdentity.device else {
                fail("A cross-volume entry was encountered; the aggregate is incomplete.")
                if identity.isDirectory { enumerator.skipDescendants() }
                continue
            }
            if identity.isSymlink {
                continue
            }
            guard let ubiquitous = ubiquitousValue(url) else {
                fail("Could not determine cloud-sync state for \(url.lastPathComponent).")
                if identity.isDirectory { enumerator.skipDescendants() }
                continue
            }
            if ubiquitous {
                fail("Cloud-synced content was skipped; the aggregate is incomplete.")
                if identity.isDirectory { enumerator.skipDescendants() }
                continue
            }
            if identity.isDirectory { continue }
            guard identity.isRegular else { continue }
            guard seenFiles.insert(identity.key).inserted else { continue }
            guard let allocated = allocatedBytes(identity) else {
                fail("Allocated size was unavailable for \(url.lastPathComponent).")
                continue
            }

            let bucket = firstBucket(for: url, under: root)
            if buckets[bucket] == nil && buckets.count >= maxBucketCount {
                fail("Growth scan found more than \(maxBucketCount) top-level buckets.")
                continue
            }
            let existing = buckets[bucket, default: 0]
            let (newValue, overflow) = existing.addingReportingOverflow(allocated)
            guard !overflow else {
                fail("Allocated size overflowed while aggregating \(bucket).")
                continue
            }
            buckets[bucket] = newValue
        }

        if Task.isCancelled { fail("Growth scan was cancelled.") }
        guard let finalIdentity = lstatIdentity(root), finalIdentity.isDirectory,
              finalIdentity.device == rootIdentity.device,
              finalIdentity.inode == rootIdentity.inode else {
            return GrowthScan(snapshot: nil, issue: "The scan root changed while it was being inspected.")
        }
        guard noSymlinkAncestry(root) else {
            return GrowthScan(snapshot: nil, issue: "The scan root acquired a symbolic-link ancestor while it was being inspected.")
        }
        let snapshot = GrowthSnapshot(date: Date(), rootKey: rootIdentity.key, buckets: buckets, visited: visited)
        return GrowthScan(snapshot: issue == nil ? snapshot : nil, issue: issue,
                          incompleteSnapshot: issue == nil ? nil : snapshot, inaccessiblePaths: inaccessiblePaths)
    }

    static func changes(previous: GrowthSnapshot, current: GrowthSnapshot) -> [GrowthChange] {
        guard previous.rootKey == current.rootKey else { return [] }
        let names = Set(previous.buckets.keys).union(current.buckets.keys)
        return names.compactMap { name in
            let oldValue = previous.buckets[name, default: 0]
            let newValue = current.buckets[name, default: 0]
            let (delta, overflow) = newValue.subtractingReportingOverflow(oldValue)
            guard !overflow, delta != 0 else { return nil }
            return GrowthChange(name: name, bytes: newValue, delta: delta)
        }.sorted {
            if $0.delta.magnitude != $1.delta.magnitude { return $0.delta.magnitude > $1.delta.magnitude }
            return $0.name < $1.name
        }
    }

    static func recurrenceLabel(_ history: [GrowthSnapshot], name: String) -> String? {
        guard history.count >= 3 else { return nil }
        var sawFall = false
        for pair in zip(history, history.dropFirst()) {
            guard pair.0.rootKey == pair.1.rootKey else {
                sawFall = false
                continue
            }
            let (delta, overflow) = pair.1.buckets[name, default: 0].subtractingReportingOverflow(pair.0.buckets[name, default: 0])
            guard !overflow else {
                sawFall = false
                continue
            }
            if delta < 0 {
                sawFall = true
            } else if sawFall && delta > 0 {
                return "Growth recurred"
            }
        }
        return nil
    }

    static func recurrence(_ history: [GrowthSnapshot], name: String) -> String? {
        recurrenceLabel(history, name: name)
    }

    private static func noSymlinkAncestry(_ url: URL) -> Bool {
        var cursor = url.standardizedFileURL
        while true {
            guard let identity = lstatIdentity(cursor), !identity.isSymlink else { return false }
            if cursor.path == "/" { return true }
            let parent = cursor.deletingLastPathComponent()
            guard parent.path != cursor.path else { return false }
            cursor = parent
        }
    }

    private static func lstatIdentity(_ url: URL) -> GrowthIdentity? {
        var value = stat()
        guard lstat(url.path, &value) == 0 else { return nil }
        return GrowthIdentity(device: value.st_dev, inode: value.st_ino, mode: value.st_mode,
                              blocks: value.st_blocks)
    }

    private static func ubiquitousValue(_ url: URL) -> Bool? {
        do {
            let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey])
            return values.isUbiquitousItem == true
        }
        catch { return nil }
    }

    private static func isUbiquitous(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true
    }

    private static func allocatedBytes(_ identity: GrowthIdentity) -> Int64? {
        guard identity.blocks >= 0 else { return nil }
        let (bytes, overflow) = identity.blocks.multipliedReportingOverflow(by: allocationBlockSize)
        return overflow ? nil : bytes
    }

    private static func firstBucket(for url: URL, under root: URL) -> String {
        let rootPath = root.path == "/" ? "/" : root.path + "/"
        let path = url.path
        guard path.hasPrefix(rootPath) else { return filesInRoot }
        let relative = String(path.dropFirst(rootPath.count))
        guard let first = relative.split(separator: "/", omittingEmptySubsequences: true).first else {
            return filesInRoot
        }
        return relative.contains("/") ? String(first) : filesInRoot
    }
}

private struct GrowthIdentity: Sendable {
    let device: Int32
    let inode: UInt64
    let mode: UInt16
    let blocks: Int64

    var key: String { "\(device):\(inode)" }
    var fileType: UInt16 { mode & UInt16(S_IFMT) }
    var isDirectory: Bool { fileType == UInt16(S_IFDIR) }
    var isRegular: Bool { fileType == UInt16(S_IFREG) }
    var isSymlink: Bool { fileType == UInt16(S_IFLNK) }
}
