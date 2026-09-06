import Foundation
import AppKit

enum SelfCheck {
    static func run() -> Bool {
        let fm = FileManager.default
        let parent = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(".build/cleanup-check-\(UUID().uuidString)")
        let root = parent.appendingPathComponent("documents")
        var passed: [String] = []
        func expect(_ condition: Bool, _ description: String) throws {
            guard condition else { throw StorageError.message(description) }
            passed.append(description)
        }
        func rejected(_ operation: () throws -> Void) -> Bool {
            do { try operation(); return false } catch { return true }
        }
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: parent) }
            let document = root.appendingPathComponent("old-review.pdf")
            try Data(repeating: 65, count: 1_100_000).write(to: document)
            try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-200 * 86400)], ofItemAtPath: document.path)
            let outside = parent.appendingPathComponent("outside.pdf")
            try Data(repeating: 66, count: 1_100_000).write(to: outside)
            try fm.createSymbolicLink(at: root.appendingPathComponent("escape.pdf"), withDestinationURL: outside)
            let report = Storage.scanDocuments(root: root)
            try expect(report.items.count == 1, "Document scan skips symlinks and finds the old eligible file")
            guard let item = report.items.first else { throw StorageError.message("Missing fixture") }
            let small = root.appendingPathComponent("recent-small.txt")
            try Data("Disposable small document".utf8).write(to: small)
            try expect(!Storage.scanDocuments(root: root).items.contains { $0.url == small }, "Default document filter excludes recent small files")
            let expanded = Storage.scanDocuments(root: root, includeSmallFiles: true)
            guard let smallCandidate = expanded.items.first(where: { $0.url == small }) else { throw StorageError.message("Small-file filter did not expose fixture") }
            try expect(smallCandidate.selectable && !expanded.items.contains { $0.url.lastPathComponent == "escape.pdf" }, "Smaller-files option exposes selectable files without following symlinks")
            var filter = InventoryFilter()
            filter.search = "  RECENT-small  "
            try expect(filter.apply(expanded.items, selection: []).map(\.id) == [smallCandidate.id], "Search trims whitespace and matches names case-insensitively")
            filter = InventoryFilter()
            filter.minimumSize = .mb25
            try expect(filter.apply(expanded.items, selection: []).isEmpty, "Minimum allocated-size filter produces an honest empty result")
            filter = InventoryFilter()
            filter.age = .halfYear
            try expect(filter.apply(expanded.items, selection: []).map(\.id) == [item.id], "Modified-age filter excludes recent files")
            filter = InventoryFilter()
            filter.category = .images
            try expect(filter.apply(expanded.items, selection: []).isEmpty, "Type filter excludes other document formats")
            filter = InventoryFilter()
            filter.sort = .smallest
            try expect(filter.apply(expanded.items, selection: []).first?.id == smallCandidate.id, "Smallest-first sort uses allocated size")
            let outsideSelection: Set<String> = [outside.path]
            let batch = InventoryFilter.selectingVisible(expanded.items, in: outsideSelection, selected: true)
            try expect(batch == outsideSelection.union(expanded.items.map(\.id)), "Select all visible preserves selections outside the current results")
            try expect(InventoryFilter.selectingVisible([smallCandidate], in: batch, selected: false) == [outside.path, item.id], "Deselect visible removes only matching rows")
            filter = InventoryFilter()
            filter.selectedOnly = true
            try expect(filter.apply(expanded.items, selection: [smallCandidate.id]).map(\.id) == [smallCandidate.id], "Selected-only view includes exactly the selected result")
            guard let smallTrash = try Storage.trash(smallCandidate) else { throw StorageError.message("Small fixture moved, but no restore destination was returned.") }
            try expect(!fm.fileExists(atPath: small.path) && fm.fileExists(atPath: smallTrash.path), "Explicitly reviewed small document moves to native Trash")
            try fm.moveItem(at: smallTrash, to: small)
            try expect(!Storage.inside(outside, root: root), "Scope containment rejects siblings")
            try expect(!Storage.documentRootAllowed(URL(fileURLWithPath: NSHomeDirectory() + "/Library")), "App-data root is protected")
            try expect(!Storage.documentRootAllowed(URL(fileURLWithPath: "/")), "Filesystem root is protected")
            let artifacts = parent.appendingPathComponent("artifacts")
            try fm.createDirectory(at: artifacts, withIntermediateDirectories: true)
            for name in ["logo.svg", "screen-draft-v2.SVG", "session-notes.md", "app-config.json", "draftsmanship.txt"] {
                try Data("Test fixture".utf8).write(to: artifacts.appendingPathComponent(name))
            }
            try fm.createSymbolicLink(at: artifacts.appendingPathComponent("escape.svg"), withDestinationURL: outside)
            let artifactReport = Storage.scanDocuments(root: artifacts, includeSmallFiles: true)
            try expect(artifactReport.items.count == 5, "Artifact scan includes tiny SVG and work records, excludes symlinks")
            filter = InventoryFilter()
            filter.category = .svg
            try expect(filter.apply(artifactReport.items, selection: []).count == 2, "SVG filter is case-insensitive and includes artwork without draft claims")
            filter.category = .workArtifacts
            let leftovers = filter.apply(artifactReport.items, selection: [])
            try expect(leftovers.count == 3, "Work-artifact clues exclude ordinary config and partial-word false positives")
            filter.category = .records
            try expect(filter.apply(artifactReport.items, selection: []).first?.url.lastPathComponent == "session-notes.md", "Work records use explicit filename clues")
            filter.category = .drafts
            let drafts = filter.apply(artifactReport.items, selection: [])
            try expect(drafts.count == 1 && drafts[0].artifactReason?.contains("may still be used") == true, "Draft clues retain project-use uncertainty")
            guard let artwork = artifactReport.items.first(where: { $0.url.lastPathComponent == "logo.svg" }),
                  let artworkTrash = try Storage.trash(artwork) else { throw StorageError.message("SVG fixture did not move to Trash") }
            try expect(!fm.fileExists(atPath: artwork.url.path) && fm.fileExists(atPath: artworkTrash.path), "Reviewed SVG uses the existing validated Trash path")
            try fm.moveItem(at: artworkTrash, to: artwork.url)
            var firstCount = 0
            let firstTree = Storage.directorySize(root, deadline: Date().addingTimeInterval(10), count: &firstCount)
            let nested = root.appendingPathComponent("nested")
            try fm.createDirectory(at: nested, withIntermediateDirectories: true)
            try Data("bundle mutation".utf8).write(to: nested.appendingPathComponent("metadata"))
            var secondCount = 0
            let secondTree = Storage.directorySize(root, deadline: Date().addingTimeInterval(10), count: &secondCount)
            try expect(firstTree.1 && secondTree.1 && firstTree.2 != secondTree.2, "Tree fingerprint detects nested content changes")
            let partial = Storage.scanDocuments(root: root, limit: 1)
            try expect(partial.partial, "Entry limit produces a partial result")
            try Storage.validate(item)
            passed.append("Unchanged reviewed fixture validates")
            try Data("changed".utf8).write(to: document)
            try expect(rejected { try Storage.validate(item) }, "Changed file is rejected before removal")
            try Data(repeating: 65, count: 1_100_000).write(to: document)
            try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-200 * 86400)], ofItemAtPath: document.path)
            try fm.linkItem(at: document, to: root.appendingPathComponent("hard-link.pdf"))
            let hardLinks = Storage.scanDocuments(root: root)
            try expect(hardLinks.items.count == 1 && hardLinks.items.first?.selectable == false, "Hard links are deduplicated and excluded from removal")
            try expect(InventoryFilter.selectingVisible(hardLinks.items, in: [], selected: true).isEmpty, "Bulk selection cannot select protected hard-linked files")
            filter = InventoryFilter()
            filter.eligibleOnly = true
            try expect(filter.apply(hardLinks.items, selection: []).isEmpty, "Eligible-only filter hides protected entries")
            try fm.removeItem(at: root.appendingPathComponent("hard-link.pdf"))
            guard let fresh = Storage.scanDocuments(root: root).items.first else { throw StorageError.message("Missing refreshed fixture") }
            guard let trashed = try Storage.trash(fresh) else { throw StorageError.message("Document fixture moved, but no restore destination was returned.") }
            try expect(!fm.fileExists(atPath: document.path) && fm.fileExists(atPath: trashed.path), "Native Trash returns a real destination and moves only the fixture")
            try fm.moveItem(at: trashed, to: document)
            try expect(fm.fileExists(atPath: outside.path), "Unselected sibling survives the operation")
            let appRoot = fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
            let app = appRoot.appendingPathComponent("Cleanup-Check-\(UUID().uuidString).app")
            let contents = app.appendingPathComponent("Contents")
            try fm.createDirectory(at: contents, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: app) }
            let bundleID = "dev.blueock.cleanup.fixture.\(UUID().uuidString)"
            let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": bundleID, "CFBundlePackageType": "APPL"], format: .xml, options: 0)
            try plist.write(to: contents.appendingPathComponent("Info.plist"))
            var appCount = 0
            let appTree = Storage.directorySize(app, deadline: Date().addingTimeInterval(10), count: &appCount)
            let appCandidate = Candidate(url: app, root: appRoot, rootIdentity: try Identity.read(appRoot), identity: try Identity.read(app), bytes: appTree.0, modified: Date(), kind: .application, reason: "Disposable verification fixture", selectable: true, bundleID: bundleID, treeStamp: appTree.2)
            try Storage.validate(appCandidate)
            guard let appTrash = try Storage.trash(appCandidate) else { throw StorageError.message("App fixture moved, but no restore destination was returned.") }
            try expect(!fm.fileExists(atPath: app.path) && fm.fileExists(atPath: appTrash.path), "Disposable app bundle uninstalls through native Trash")
            try fm.moveItem(at: appTrash, to: app)
            try Data("nested change".utf8).write(to: contents.appendingPathComponent("changed"))
            try expect(rejected { try Storage.validate(appCandidate) }, "Changed app bundle is refused before uninstall")
            let capacity = try Capacity.read()
            try expect(capacity.total > 0 && capacity.free >= 0 && capacity.free <= capacity.total, "Live volume reading has valid bounds")
            try expect(CacheProvider.matching(root) == nil, "Cache cleanup rejects arbitrary document roots")
            let fakeCache = Candidate(url: root, root: parent, rootIdentity: try Identity.read(parent), identity: try Identity.read(root), bytes: 0, modified: Date(), kind: .cache, reason: "Fixture", selectable: true, bundleID: nil)
            try expect(rejected { try CacheProvider.uv.validate(fakeCache) }, "Production cache validator refuses an unapproved location")
            for provider in [CacheProvider.uv, .pip] {
                guard let executable = provider.executable else { throw StorageError.message("Install \(provider.rawValue) before running provider fixture verification.") }
                let cache = parent.appendingPathComponent("\(provider.rawValue)-fixture")
                let bucket = cache.appendingPathComponent(provider == .uv ? "archive-v0" : "wheels")
                try fm.createDirectory(at: bucket, withIntermediateDirectories: true)
                let payload = bucket.appendingPathComponent(provider == .uv ? "obsolete-fixture" : "cleanup_fixture-0-py3-none-any.whl")
                try Data(repeating: 67, count: 1_100_000).write(to: payload)
                let output = try provider.run(at: cache, executable: executable)
                try expect(!fm.fileExists(atPath: payload.path) && output.contains("completed"), "\(provider.rawValue) provider removes only disposable cache payload")
                try expect(fm.fileExists(atPath: outside.path), "\(provider.rawValue) cleanup preserves the sibling outside its cache")
            }
            try expect(rejected { _ = try CacheProvider.uv.run(at: parent, executable: URL(fileURLWithPath: "/usr/bin/false")) }, "Nonzero provider exit is reported as failure")
            let data = try JSONSerialization.data(withJSONObject: ["passed": passed, "count": passed.count, "success": true], options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data, as: UTF8.self))
            return true
        } catch {
            print("SELF-CHECK FAILED: \(error.localizedDescription); passed: \(passed)")
            return false
        }
    }
}
