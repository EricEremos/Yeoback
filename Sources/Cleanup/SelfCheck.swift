import Foundation
import AppKit

enum SelfCheck {
    static func run() -> Bool {
        let fm = FileManager.default
        // Fixtures live outside the repository: files inside a version-controlled tree are view-only by design.
        let parent = Storage.disposableFixtureParent("cleanup-check")
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
            let homeCandidate = Candidate(url: fm.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions"),
                                          root: root, rootIdentity: smallCandidate.rootIdentity, identity: smallCandidate.identity,
                                          bytes: 0, modified: Date(), kind: .cache, reason: "Synthetic search fixture",
                                          selectable: false, bundleID: nil)
            filter.search = "  ~/.codex/  "
            try expect(filter.apply([homeCandidate], selection: []).count == 1, "Search accepts the displayed home-relative path")
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
            let smallTrash = try Storage.trash(smallCandidate)
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
            guard let artwork = artifactReport.items.first(where: { $0.url.lastPathComponent == "logo.svg" }) else { throw StorageError.message("SVG fixture missing") }
            let artworkTrash = try Storage.trash(artwork)
            try expect(!fm.fileExists(atPath: artwork.url.path) && fm.fileExists(atPath: artworkTrash.path), "Reviewed SVG uses the existing validated Trash path")
            try fm.moveItem(at: artworkTrash, to: artwork.url)
            let recordNames = ["chat-history.ndjson", "rollout-20260908.jsonl", "handoff.md", "sessions/2026/opaque.jsonl", "conversations/opaque.json", ".planning/phases/01/summary.md", ".omo/plans/next.md", ".sisyphus/notepads/notes.md", ".codex/sessions/2026/opaque.jsonl", ".codex/archived_sessions/rollout.jsonl", ".codex/log/codex-tui.log", ".claude/projects/workspace/opaque.jsonl", ".claude/debug/opaque.txt", ".claude/todos/opaque.json"]
            let ordinaryNames = ["conversationist.md", "assistantship.json", "session.png", "app-config.json", "sessions/settings.json", "sessions/README.md"]
            let excludedNames = [".git/session.md", ".codex/auth.json", ".codex/session-index.json", ".codex/skills/session.md", ".codex/sessions/auth.json", ".claude/settings.json", ".claude/plugins/session.md", "node_modules/session.md", ".planning/config.json", ".planning/.secret.json"]
            for name in recordNames + ordinaryNames + excludedNames {
                let url = artifacts.appendingPathComponent(name)
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("Disposable record fixture".utf8).write(to: url)
            }
            let records = Storage.scanDocuments(root: artifacts, includeSmallFiles: true)
            filter.category = .records
            let recordPaths = Set(filter.apply(records.items, selection: []).map(\.url.path))
            let missingRecords = recordNames.filter { !recordPaths.contains(artifacts.appendingPathComponent($0).path) }
            try expect(missingRecords.isEmpty, "Record filter finds plural folders, opaque logs, NDJSON, handoffs and hidden agent records\(missingRecords.isEmpty ? "" : ": missing \(missingRecords.joined(separator: ", "))")")
            try expect(ordinaryNames.allSatisfy { !recordPaths.contains(artifacts.appendingPathComponent($0).path) }, "Record clues reject partial words, binary files, config and canonical instructions")
            try expect(excludedNames.allSatisfy { name in !records.items.contains { $0.url.path == artifacts.appendingPathComponent(name).path } }, "Hidden credentials, Git, dependencies and hidden configuration stay excluded")
            let protected = records.items.filter { WorkArtifact.isProtectedRecord($0.url) }
            try expect(protected.count == 9 && protected.allSatisfy { item in !item.selectable && rejected { try Storage.validate(item) } }, "Hidden agent records are view-only and rejected by cleanup validation")
            let directRecords = Storage.scanDocuments(root: artifacts.appendingPathComponent(".codex"), includeSmallFiles: true)
            try expect(directRecords.items.count == 3 && directRecords.items.allSatisfy { !$0.selectable }, "Direct agent-root scan includes only named record subfolders, all view-only")
            try expect(InventoryFilter.selectingVisible(protected, in: [], selected: true).isEmpty, "Bulk selection cannot include agent workspace records")
            try expect(WorkArtifact.recordClue(artifacts.appendingPathComponent("sessions/opaque.jsonl"), root: artifacts.appendingPathComponent("sessions")), "Choosing the record folder itself preserves the clue")
            try expect(WorkArtifact.reason(for: artifacts.appendingPathComponent("drafts/chat-history.jsonl"), root: artifacts)?.hasPrefix("Draft/export") == true, "Draft reason retains precedence over record clues")
            var firstCount = 0
            let firstTree = Storage.directorySize(root, deadline: Date().addingTimeInterval(10), count: &firstCount)
            let nested = root.appendingPathComponent("nested")
            try fm.createDirectory(at: nested, withIntermediateDirectories: true)
            try Data("bundle mutation".utf8).write(to: nested.appendingPathComponent("metadata"))
            var secondCount = 0
            let secondTree = Storage.directorySize(root, deadline: Date().addingTimeInterval(10), count: &secondCount)
            try expect(firstTree.1 && secondTree.1 && firstTree.2 != secondTree.2, "Tree fingerprint detects nested content changes")
            let partial = Storage.scanDocuments(root: root, limit: 1)
            try expect(partial.partial && partial.issues.contains { $0.contains("1-entry limit") }, "Entry limit reports its actual configured value")
            let timedOut = Storage.scanDocuments(root: root, timeLimit: .leastNonzeroMagnitude)
            try expect(timedOut.partial && timedOut.items.isEmpty, "Document timeout discloses incomplete coverage")
            try expect(Storage.scanDocuments(root: root, limit: 0).partial, "Invalid document budget is rejected")
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
            let trashed = try Storage.trash(fresh)
            try expect(!fm.fileExists(atPath: document.path) && fm.fileExists(atPath: trashed.path), "Native Trash returns a real destination and moves only the fixture")
            try fm.moveItem(at: trashed, to: document)
            try expect(fm.fileExists(atPath: outside.path), "Unselected sibling survives the operation")
            // Regression fixtures modeled on the 2026-09-07 sweep of a git-tracked project tree.
            let repo = parent.appendingPathComponent("repo")
            try fm.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
            try Data("ref: refs/heads/main".utf8).write(to: repo.appendingPathComponent(".git/HEAD"))
            let evidence = repo.appendingPathComponent("data/raw/evidence.json")
            try fm.createDirectory(at: evidence.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("{\"kept\": true}".utf8).write(to: evidence)
            try Data("# Tracked notes".utf8).write(to: repo.appendingPathComponent("README.md"))
            let tracked = Storage.scanDocuments(root: repo, includeSmallFiles: true)
            try expect(tracked.items.count == 2 && tracked.items.allSatisfy { !$0.selectable && $0.versionControlled && $0.reason.contains("version-controlled") }, "Files inside a git working tree are listed view-only with a visible reason")
            try expect(tracked.items.allSatisfy { item in rejected { try Storage.validate(item) } }, "Cleanup validation refuses files inside a version-controlled project")
            try expect(InventoryFilter.selectingVisible(tracked.items, in: [], selected: true).isEmpty, "Bulk selection cannot include version-controlled files")
            let nestedRoot = Storage.scanDocuments(root: repo.appendingPathComponent("data"), includeSmallFiles: true)
            try expect(nestedRoot.items.count == 1 && nestedRoot.items[0].selectable == false, "A scan root inside a git working tree inherits the protection")
            let stale = Candidate(url: evidence, root: repo, rootIdentity: try Identity.read(repo), identity: try Identity.read(evidence), bytes: 0, modified: Date(), kind: .document, reason: "Stale fixture", selectable: true, bundleID: nil)
            try expect(rejected { _ = try Storage.trash(stale) } && fm.fileExists(atPath: evidence.path), "A stale selectable candidate inside a git tree is refused at Trash time and stays in place")
            let worktree = parent.appendingPathComponent("worktree")
            try fm.createDirectory(at: worktree, withIntermediateDirectories: true)
            try Data("gitdir: ../repo/.git/worktrees/wt".utf8).write(to: worktree.appendingPathComponent(".git"))
            try Data("export".utf8).write(to: worktree.appendingPathComponent("draft.svg"))
            try expect(Storage.scanDocuments(root: worktree, includeSmallFiles: true).items.allSatisfy { !$0.selectable }, "A .git file (linked worktree) also protects its tree")
            try expect(rejected { _ = try Storage.confirmedTrashDestination(for: outside, reported: nil) }, "A missing Trash destination is reported as unconfirmed, not success")
            try expect(rejected { _ = try Storage.confirmedTrashDestination(for: outside, reported: parent.appendingPathComponent("ghost.txt")) }, "A destination that does not exist is reported as unconfirmed")
            try expect(rejected { _ = try Storage.confirmedTrashDestination(for: outside, reported: outside) }, "An original that still exists is reported as unconfirmed")
            let movedSource = parent.appendingPathComponent("moved.txt")
            let movedDestination = parent.appendingPathComponent("moved-destination.txt")
            try Data("moved".utf8).write(to: movedSource)
            try fm.moveItem(at: movedSource, to: movedDestination)
            try expect(try Storage.confirmedTrashDestination(for: movedSource, reported: movedDestination) == movedDestination, "A verified move returns its destination")
            try expect(Storage.syncedFolderNote(for: parent.appendingPathComponent("plain.txt")) == nil, "Folders outside iCloud-managed locations carry no sync note")
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
            let appTrash = try Storage.trash(appCandidate)
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
