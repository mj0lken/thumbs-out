/// The coding agents thumbs-out knows how to watch.
public enum Agent: String, CaseIterable, Codable, Sendable, Identifiable {
    case claudeCode
    case chatGPT
    case antigravity

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .chatGPT: "ChatGPT / Codex"
        case .antigravity: "Antigravity"
        }
    }

    /// Returns the agent a process belongs to, if any.
    public static func agent(for record: ProcessRecord) -> Agent? {
        allCases.first { $0.matches(record) }
    }

    func matches(_ record: ProcessRecord) -> Bool {
        switch self {
        case .claudeCode:
            // Native CLI (the installer's versioned binary, or the copy bundled with the Claude
            // desktop app) or the npm package.
            record.name == "claude" || record.launchName == "claude" || record.path.contains("/claude/versions/")
                || record.arguments.contains { $0.contains("@anthropic-ai/claude-code") }
        case .chatGPT:
            record.path.contains("/ChatGPT.app/") || record.path.contains("/Codex.app/")
                || record.name == "codex" || record.launchName == "codex"
                || record.arguments.contains { $0.contains("@openai/codex") }
        case .antigravity:
            record.path.contains("/Antigravity.app/") || record.path.contains("/Antigravity IDE.app/")
        }
    }
}
