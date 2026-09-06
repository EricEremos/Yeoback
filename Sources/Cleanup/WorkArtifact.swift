import Foundation

/// Local filename and folder clues, never a claim of AI origin or non-use.
enum WorkArtifact {
    static func draftClue(_ url: URL, root: URL) -> Bool {
        let relative = String(url.path.dropFirst(root.path.count)).lowercased()
        let tokens = relative.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return tokens.contains { ["draft", "drafts", "scratch", "tmp", "temp", "mockup", "mockups", "prototype", "prototypes", "iteration", "iterations", "export", "exports"].contains($0) }
    }

    static func recordClue(_ url: URL) -> Bool {
        guard ["md", "markdown", "txt", "json", "jsonl", "log", "html"].contains(url.pathExtension.lowercased()) else { return false }
        let tokens = url.deletingPathExtension().lastPathComponent.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        return tokens.contains { ["transcript", "conversation", "session", "prompt", "prompts", "checkpoint", "trace", "debug"].contains($0) }
    }

    static func reason(for url: URL, root: URL) -> String? {
        if draftClue(url, root: root) { return "Draft/export name or folder · may still be used by a project" }
        if recordClue(url) { return "Work-record filename · may contain useful history" }
        if url.pathExtension.lowercased() == "svg" { return "SVG artwork · origin and project usage not verified" }
        return nil
    }
}
