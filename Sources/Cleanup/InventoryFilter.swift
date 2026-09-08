import Foundation

enum FileCategory: String, CaseIterable, Identifiable {
    case all = "All types", documents = "Documents", images = "Images", media = "Video & audio", archives = "Archives & installers"
    case workArtifacts = "Work leftovers", svg = "SVG artwork", drafts = "Drafts & exports", records = "Work records"
    var id: String { rawValue }
    func matches(_ item: Candidate) -> Bool {
        let ext = item.url.pathExtension.lowercased()
        switch self {
        case .all: return true
        case .documents: return ["pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "pages", "key", "numbers", "rtf", "txt", "csv", "md", "markdown", "json", "jsonl", "ndjson", "log", "html"].contains(ext)
        case .images: return ["jpg", "jpeg", "png", "heic", "gif", "tiff", "svg", "webp"].contains(ext)
        case .media: return ["mp4", "mov", "mkv", "avi", "mp3", "wav", "m4a"].contains(ext)
        case .archives: return ["zip", "7z", "tar", "gz", "dmg", "pkg", "iso"].contains(ext)
        case .workArtifacts: return item.artifactReason != nil
        case .svg: return ext == "svg"
        case .drafts: return item.kind == .document && WorkArtifact.draftClue(item.url, root: item.root)
        case .records: return item.kind == .document && WorkArtifact.recordClue(item.url, root: item.root)
        }
    }
    var isArtifactView: Bool { [.workArtifacts, .svg, .drafts, .records].contains(self) }
}

enum MinimumSize: Int64, CaseIterable, Identifiable {
    case any = 0, mb25 = 25_000_000, mb100 = 100_000_000, gb1 = 1_000_000_000
    var id: Int64 { rawValue }
    var label: String { self == .any ? "Any size" : "At least \(sizeText(rawValue))" }
}

enum ModifiedAge: Int, CaseIterable, Identifiable {
    case any = 0, month = 30, halfYear = 180, year = 365
    var id: Int { rawValue }
    var label: String { self == .any ? "Any date" : "Unchanged \(rawValue)+ days" }
}

enum InventorySort: String, CaseIterable, Identifiable {
    case largest = "Largest first", smallest = "Smallest first", name = "Name A–Z", oldest = "Oldest first", newest = "Newest first"
    var id: String { rawValue }
}

struct InventoryFilter: Equatable {
    var search = ""
    var category: FileCategory = .all
    var minimumSize: MinimumSize = .any
    var age: ModifiedAge = .any
    var sort: InventorySort = .largest
    var selectedOnly = false
    var eligibleOnly = false
    var isRestricted: Bool { !search.isEmpty || category != .all || minimumSize != .any || age != .any || selectedOnly || eligibleOnly }

    func apply(_ items: [Candidate], selection: Set<String>, now: Date = Date()) -> [Candidate] {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = trimmed.hasPrefix("~/") ? (trimmed as NSString).expandingTildeInPath : trimmed
        return items.filter { item in
            (query.isEmpty || item.url.path.localizedCaseInsensitiveContains(query)) && category.matches(item) &&
            item.bytes >= minimumSize.rawValue && (age == .any || now.timeIntervalSince(item.modified) >= Double(age.rawValue) * 86400) &&
            (!selectedOnly || selection.contains(item.id)) && (!eligibleOnly || item.selectable)
        }.sorted { lhs, rhs in
            switch sort {
            case .largest: if lhs.bytes != rhs.bytes { return lhs.bytes > rhs.bytes }
            case .smallest: if lhs.bytes != rhs.bytes { return lhs.bytes < rhs.bytes }
            case .oldest: if lhs.modified != rhs.modified { return lhs.modified < rhs.modified }
            case .newest: if lhs.modified != rhs.modified { return lhs.modified > rhs.modified }
            case .name: break
            }
            let comparison = lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent)
            return comparison == .orderedSame ? lhs.id < rhs.id : comparison == .orderedAscending
        }
    }

    static func selectingVisible(_ visible: [Candidate], in selection: Set<String>, selected: Bool) -> Set<String> {
        let ids = Set(visible.filter(\.selectable).map(\.id))
        return selected ? selection.union(ids) : selection.subtracting(ids)
    }
}
