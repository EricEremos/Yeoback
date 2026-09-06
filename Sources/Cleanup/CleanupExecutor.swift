import Foundation

struct CleanupOutcome: Sendable {
    let item: Candidate
    let success: Bool
    let detail: String
    let destination: URL?
}

enum CleanupExecutor {
    static let batchSize = 32
    static let documentConcurrency = 4

    // Document workers retain the validation immediately before each native Trash call.
    // App bundles and provider commands stay isolated from other operations.
    static func batchEnd(in items: [Candidate], from start: Int) -> Int {
        guard items[start].kind == .document else { return start + 1 }
        var end = start
        while end < min(start + batchSize, items.count), items[end].kind == .document { end += 1 }
        return end
    }

    static func run(_ items: [Candidate]) async -> [CleanupOutcome] {
        await withTaskGroup(of: CleanupOutcome.self) { group in
            var iterator = items.makeIterator()
            let workers = items.allSatisfy { $0.kind == .document } ? documentConcurrency : 1
            for _ in 0..<workers {
                if let item = iterator.next() { group.addTask { perform(item) } }
            }
            var outcomes: [CleanupOutcome] = []
            for await outcome in group {
                outcomes.append(outcome)
                if let item = iterator.next() { group.addTask { perform(item) } }
            }
            return outcomes
        }
    }

    private static func perform(_ item: Candidate) -> CleanupOutcome {
        do {
            if item.kind == .cache {
                guard let provider = CacheProvider.matching(item.url) else {
                    throw StorageError.message("This cache is not supported for cleanup.")
                }
                let detail = try provider.clean(item)
                return CleanupOutcome(item: item, success: true, detail: "\(detail)\nLocation: \(item.url.path)", destination: nil)
            }
            let destination = try Storage.trash(item)
            return CleanupOutcome(item: item, success: true,
                                  detail: "Moved to Trash · allocated estimate \(sizeText(item.bytes)). Original: \(item.url.path)" + (destination == nil ? " macOS did not return a destination; inspect Trash in Finder." : ""), destination: destination)
        } catch {
            return CleanupOutcome(item: item, success: false, detail: error.localizedDescription, destination: nil)
        }
    }
}
