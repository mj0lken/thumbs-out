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

/// Looks for installed agents in the usual places. File access is injected for testing.
public enum AgentDiscovery {
    /// Launch Services also knows about copies users never see: auto-updater staging folders,
    /// caches, the Trash and translocated quarantine copies.
    public static func isUserFacingApp(path: String) -> Bool {
        !["/Library/", "/.Trash/", "/AppTranslocation/"].contains(where: path.contains)
    }

    public static func installations(
        home: String,
        nodeVersions: [String],
        fileExists: (String) -> Bool
    ) -> [AgentInstallation] {
        let appDirectories = ["/Applications", "\(home)/Applications"]
        let binDirectories = [
            "\(home)/.local/bin", "\(home)/.claude/local", "/opt/homebrew/bin", "/usr/local/bin",
            "\(home)/.npm-global/bin", "\(home)/.bun/bin", "\(home)/.opencode/bin", "\(home)/.lmstudio/bin",
            "\(home)/.cargo/bin", "\(home)/go/bin",
        ] + nodeVersions.map { "\(home)/.nvm/versions/node/\($0)/bin" }

        return Agent.allCases.flatMap { agent in
            let apps = agent.apps.compactMap { app in
                appDirectories.lazy.map { "\($0)/\(app.bundle)" }.first(where: fileExists).map {
                    AgentInstallation(agent: agent, kind: .app, name: app.name, path: $0)
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

    /// The app or CLI is running, idle or not.
    public var isOpen: Bool {
        switch self {
        case .running, .working: true
        case .installed, .notFound: false
        }
    }
}

/// The menu's agent list: what's open now, what else is installed, and the rest of the catalog.
public struct AgentGroups: Equatable, Sendable {
    public let open: [Agent]
    public let installed: [Agent]
    public let notInstalled: [Agent]

    /// Editors and local models only count as open while watched: an editor left open doesn't keep
    /// the Mac awake, so it waits with the installed ones. Each group keeps catalog order.
    public static func group(
        _ catalog: [Agent] = Agent.allCases, watched: Set<Agent>, status: (Agent) -> AgentStatus
    ) -> AgentGroups {
        let open = catalog.filter { agent in
            status(agent).isOpen && (agent.category == .agent || watched.contains(agent))
        }
        return AgentGroups(
            open: open,
            installed: catalog.filter { status($0).isFound && !open.contains($0) },
            notInstalled: catalog.filter { !status($0).isFound }
        )
    }
}
