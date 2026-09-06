import Foundation
import FoundationModels

enum LocalStorageAdvisor {
    static var unavailableReason: String? {
        guard #available(macOS 26.0, *) else { return "On-device AI requires macOS 26 or later. The measured forecast still works." }
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return "This Mac does not support Apple’s on-device model."
            case .appleIntelligenceNotEnabled: return "Apple Intelligence is not enabled on this Mac."
            case .modelNotReady: return "Apple’s on-device model is not ready. Try again later."
            @unknown default: return "Apple’s on-device model is unavailable."
            }
        }
    }

    static func explain(_ evidence: String) async throws -> String {
        guard #available(macOS 26.0, *) else { throw StorageError.message("On-device AI requires macOS 26 or later.") }
        if let reason = unavailableReason { throw StorageError.message(reason) }
        let session = LanguageModelSession(instructions: """
        Explain a storage observation in plain English in at most three short sentences.
        The supplied facts are the only evidence. Preserve their uncertainty.
        Do not calculate or invent numbers, causes, app names, files, or recovery guarantees.
        Do not repeat any quantities or predicted times; the app already displays those.
        Describe trends conditionally: recent behavior may change and cannot identify its cause.
        Never suggest commands, automatic removal, or emptying all Trash.
        If the reserve is below target, suggest reviewing cleanup candidates in Yeoback.
        If data is insufficient, uneven, or stale, explain that limitation.
        You have no tools or authority to select or remove files.
        """
        )
        let response = try await session.respond(to: evidence, options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 220))
        try Task.checkCancellation()
        return response.content
    }
}
