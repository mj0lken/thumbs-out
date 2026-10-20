/// Something on this Mac through which an agent can run commands.
public struct AgentInstallation: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case app
        case commandLine
    }

    public let agent: Agent
    public let kind: Kind
    public let name: String
    public let path: String

    public var id: String { path }

    public init(agent: Agent, kind: Kind, name: String, path: String) {
        self.agent = agent
        self.kind = kind
        self.name = name
        self.path = path
    }
}

extension Agent {
    /// App bundles, so the app layer can also ask Launch Services for apps installed elsewhere.
    public var bundleIdentifiers: [String] {
        switch self {
        case .claudeCode: ["com.anthropic.claudefordesktop"]
        case .chatGPT: ["com.openai.chat", "com.openai.codex"]
        case .antigravity: ["com.google.antigravity", "com.google.antigravity-ide"]
        }
    }

    var appBundleNames: [(bundle: String, name: String)] {
        switch self {
        case .claudeCode: [("Claude.app", "Claude app")]
        case .chatGPT: [("ChatGPT.app", "ChatGPT app"), ("Codex.app", "Codex app")]
        case .antigravity: [("Antigravity.app", "Antigravity"), ("Antigravity IDE.app", "Antigravity IDE")]
        }
    }

    var commandLineTools: [String] {
        switch self {
        case .claudeCode: ["claude"]
        case .chatGPT: ["codex"]
        case .antigravity: ["agy", "antigravity"]
        }
    }
}

/// Looks for installed agents in the usual places. File access is injected for testing.
public enum AgentDiscovery {
    public static func installations(
        home: String,
        nodeVersions: [String],
        fileExists: (String) -> Bool
    ) -> [AgentInstallation] {
        let appDirectories = ["/Applications", "\(home)/Applications"]
        let binDirectories = [
            "\(home)/.local/bin", "\(home)/.claude/local", "/opt/homebrew/bin", "/usr/local/bin",
            "\(home)/.npm-global/bin", "\(home)/.bun/bin",
        ] + nodeVersions.map { "\(home)/.nvm/versions/node/\($0)/bin" }

        return Agent.allCases.flatMap { agent in
            let apps = agent.appBundleNames.compactMap { bundle, name in
                appDirectories.lazy.map { "\($0)/\(bundle)" }.first(where: fileExists).map {
                    AgentInstallation(agent: agent, kind: .app, name: name, path: $0)
                }
            }
            let tools = agent.commandLineTools.compactMap { tool in
                binDirectories.lazy.map { "\($0)/\(tool)" }.first(where: fileExists).map {
                    AgentInstallation(agent: agent, kind: .commandLine, name: "\(tool) CLI", path: $0)
                }
            }
            return apps + tools
        }
    }
}

/// How an agent shows up in the menu and onboarding.
public enum AgentStatus: Sendable, Equatable {
    case notFound
    case installed
    case running
    case working(Int)

    public static func resolve(
        _ agent: Agent,
        installations: [AgentInstallation],
        runningAgents: Set<Agent>,
        commands: [DetectedCommand]
    ) -> AgentStatus {
        let commandCount = commands.filter { $0.agent == agent }.count
        if commandCount > 0 { return .working(commandCount) }
        if runningAgents.contains(agent) { return .running }
        if installations.contains(where: { $0.agent == agent }) { return .installed }
        return .notFound
    }

    public var isFound: Bool { self != .notFound }
}
