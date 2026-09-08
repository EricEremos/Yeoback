import Foundation

/// Local filename and folder clues, never a claim of AI origin or non-use.
enum WorkArtifact {
    static let hiddenRecordFolders: Set<String> = [".planning", ".omo", ".sisyphus", ".codex", ".claude"]
    private static let agentRecordSubfolders: [String: Set<String>] = [
        ".codex": ["sessions", "archived_sessions", "log"],
        ".claude": ["projects", "debug", "todos"]
    ]

    static func allowsRecordTraversal(_ url: URL) -> Bool {
        let components = url.standardizedFileURL.pathComponents.map { $0.lowercased() }
        for index in components.indices {
            if let allowed = agentRecordSubfolders[components[index]], index + 1 < components.count,
               !allowed.contains(components[index + 1]) { return false }
        }
        return true
    }

    static func isProtectedRecord(_ url: URL) -> Bool {
        url.standardizedFileURL.pathComponents.contains { hiddenRecordFolders.contains($0.lowercased()) }
    }

    static func draftClue(_ url: URL, root: URL) -> Bool {
        let relative = String(url.path.dropFirst(root.path.count)).lowercased()
        let tokens = relative.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return tokens.contains { ["draft", "drafts", "scratch", "tmp", "temp", "mockup", "mockups", "prototype", "prototypes", "iteration", "iterations", "export", "exports"].contains($0) }
    }

    static func recordClue(_ url: URL, root: URL? = nil) -> Bool {
        guard allowsRecordTraversal(url), ["md", "markdown", "txt", "json", "jsonl", "ndjson", "log", "html"].contains(url.pathExtension.lowercased()) else { return false }
        let tokens = url.deletingPathExtension().lastPathComponent.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        if tokens.contains(where: { ["config", "settings", "readme", "agents", "claude", "skill", "license", "auth", "credentials", "secret", "secrets"].contains($0) }) { return false }
        if isProtectedRecord(url) { return true }
        if tokens.contains(where: { ["transcript", "transcripts", "conversation", "conversations", "session", "sessions", "prompt", "prompts", "checkpoint", "checkpoints", "trace", "traces", "debug", "chat", "chats", "rollout", "rollouts", "handoff", "handoffs", "walkthrough"].contains($0) }) { return true }
        guard let root else { return false }
        let base = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(base == "/" ? "/" : base + "/") else { return false }
        let relative = String(path.dropFirst(base == "/" ? 1 : base.count + 1))
        let folders = [root.lastPathComponent.lowercased()] + relative.lowercased().split(separator: "/").dropLast().map(String.init)
        return folders.contains { hiddenRecordFolders.contains($0) || ["transcripts", "conversations", "sessions", "chat-history", "chat_history", "rollouts", "handoffs", "checkpoints", "traces", "task-records", "task_records"].contains($0) }
    }

    static func reason(for url: URL, root: URL) -> String? {
        if draftClue(url, root: root) { return "Draft/export name or folder · may still be used by a project" }
        if recordClue(url, root: root) { return "Work-record name or folder · may contain useful history" }
        if url.pathExtension.lowercased() == "svg" { return "SVG artwork · origin and project usage not verified" }
        return nil
    }
}
