/// Something thumbs-out can watch: an AI agent, an editor or terminal, or a local model runtime.
///
/// A data-driven catalog: adding support for a new agent is one entry in `allCases`.
public struct Agent: Hashable, Sendable, Identifiable, CaseIterable {
    public enum Category: Sendable, CaseIterable {
        /// Runs shell commands on its own. Watched by default.
        case agent
        /// Editors and terminals where any command counts, including your own. Opt-in.
        case editor
        /// Runs models, not commands; "busy" means using CPU. Opt-in.
        case modelRuntime

        public var title: String {
            switch self {
            case .agent: "Agents"
            case .editor: "Editors & Terminals"
            case .modelRuntime: "Local Models"
            }
        }
    }

    public struct App: Hashable, Sendable {
        public let bundle: String
        public let name: String
    }

    /// Stable key, used in settings (`watch.<id>`).
    public let id: String
    public let displayName: String
    public let category: Category
    /// Executable names, or script names when run by an interpreter (`node …/bin/gemini`).
    let processNames: Set<String>
    let pathFragments: [String]
    let argumentFragments: [String]
    public let apps: [App]
    public let commandLineTools: [String]
    public let bundleIdentifiers: [String]

    public var isWatchedByDefault: Bool { category == .agent }

    public static func == (lhs: Agent, rhs: Agent) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// Returns the catalog entry a process belongs to, if any.
    public static func agent(for record: ProcessRecord) -> Agent? {
        // A shell is never an agent, even if its command mentions one (`npm i -g @openai/codex`).
        guard !ActivityDetector.isShell(record) else { return nil }
        return allCases.first { $0.matches(record) }
    }

    func matches(_ record: ProcessRecord) -> Bool {
        if processNames.contains(record.name) || processNames.contains(record.launchName) { return true }
        if let script = record.scriptName, processNames.contains(script) { return true }
        if pathFragments.contains(where: record.path.contains) { return true }
        return argumentFragments.contains { fragment in record.arguments.contains { $0.contains(fragment) } }
    }
}

// MARK: - Catalog

extension Agent {
    public static let allCases: [Agent] = [
        .claudeCode, .chatGPT, .antigravity, .cursor, .windsurf, .kiro, .copilot, .opencode, .aider, .goose,
        .amp, .droid, .qwen, .crush, .vscode, .zed, .warp, .ollama, .lmStudio,
    ]

    public static let claudeCode = Agent(
        id: "claudeCode", displayName: "Claude Code", category: .agent,
        // The installer's binary is named after its version (…/claude/versions/2.1.72).
        processNames: ["claude"], pathFragments: ["/claude/versions/"], argumentFragments: ["@anthropic-ai/claude-code"],
        apps: [App(bundle: "Claude.app", name: "Claude app")], commandLineTools: ["claude"],
        bundleIdentifiers: ["com.anthropic.claudefordesktop"]
    )

    public static let chatGPT = Agent(
        id: "chatGPT", displayName: "ChatGPT / Codex", category: .agent,
        processNames: ["codex"], pathFragments: ["/ChatGPT.app/", "/Codex.app/"], argumentFragments: ["@openai/codex"],
        apps: [App(bundle: "ChatGPT.app", name: "ChatGPT app"), App(bundle: "Codex.app", name: "Codex app")],
        commandLineTools: ["codex"], bundleIdentifiers: ["com.openai.chat", "com.openai.codex"]
    )

    /// Google's agents: Antigravity and its `agy` CLI, plus Gemini CLI, which `agy` replaces.
    public static let antigravity = Agent(
        id: "antigravity", displayName: "Antigravity / Gemini", category: .agent,
        processNames: ["agy", "antigravity", "gemini"], pathFragments: ["/Antigravity.app/", "/Antigravity IDE.app/"],
        argumentFragments: ["@google/gemini-cli"],
        apps: [
            App(bundle: "Antigravity.app", name: "Antigravity"),
            App(bundle: "Antigravity IDE.app", name: "Antigravity IDE"),
        ],
        commandLineTools: ["agy", "antigravity", "gemini"],
        bundleIdentifiers: ["com.google.antigravity", "com.google.antigravity-ide"]
    )

    public static let cursor = Agent(
        id: "cursor", displayName: "Cursor", category: .agent,
        processNames: ["cursor-agent"], pathFragments: ["/Cursor.app/", "/cursor-agent/"], argumentFragments: [],
        apps: [App(bundle: "Cursor.app", name: "Cursor")], commandLineTools: ["cursor-agent"],
        bundleIdentifiers: ["com.todesktop.230313mzl4w4u92"]
    )

    public static let windsurf = Agent(
        id: "windsurf", displayName: "Windsurf", category: .agent,
        processNames: [], pathFragments: ["/Windsurf.app/"], argumentFragments: [],
        apps: [App(bundle: "Windsurf.app", name: "Windsurf")], commandLineTools: [],
        bundleIdentifiers: ["com.exafunction.windsurf"]
    )

    public static let kiro = Agent(
        id: "kiro", displayName: "Kiro", category: .agent,
        processNames: ["kiro-cli"], pathFragments: ["/Kiro.app/"], argumentFragments: [],
        apps: [App(bundle: "Kiro.app", name: "Kiro")], commandLineTools: ["kiro-cli"], bundleIdentifiers: []
    )

    // `copilot` is also AWS Copilot and `amp` a text editor, so these match by npm package only.
    public static let copilot = packageAgent("copilot", "GitHub Copilot CLI", package: "@github/copilot")
    public static let opencode = cliAgent("opencode", "OpenCode", tools: ["opencode"], package: "opencode-ai")
    public static let aider = cliAgent("aider", "Aider", tools: ["aider"])
    public static let amp = packageAgent("amp", "Amp", package: "@sourcegraph/amp")
    public static let droid = cliAgent("droid", "Factory Droid", tools: ["droid"])
    public static let qwen = cliAgent("qwen", "Qwen Code", tools: ["qwen"], package: "@qwen-code/qwen-code")
    public static let crush = cliAgent("crush", "Crush", tools: ["crush"])

    /// `goose` is also a popular database migration tool, so the bare name isn't enough:
    /// match the app, its `goosed` server, or Homebrew's `block-goose-cli`.
    public static let goose = Agent(
        id: "goose", displayName: "Goose", category: .agent,
        processNames: ["goosed"], pathFragments: ["/Goose.app/", "/block-goose-cli/"], argumentFragments: [],
        apps: [App(bundle: "Goose.app", name: "Goose app")], commandLineTools: [], bundleIdentifiers: []
    )

    public static let vscode = Agent(
        id: "vscode", displayName: "VS Code", category: .editor,
        processNames: [], pathFragments: ["/Visual Studio Code.app/", "/Visual Studio Code - Insiders.app/"],
        argumentFragments: [],
        apps: [
            App(bundle: "Visual Studio Code.app", name: "VS Code"),
            App(bundle: "Visual Studio Code - Insiders.app", name: "VS Code Insiders"),
        ],
        commandLineTools: [], bundleIdentifiers: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"]
    )

    public static let zed = Agent(
        id: "zed", displayName: "Zed", category: .editor,
        processNames: [], pathFragments: ["/Zed.app/", "/Zed Preview.app/"], argumentFragments: [],
        apps: [App(bundle: "Zed.app", name: "Zed"), App(bundle: "Zed Preview.app", name: "Zed Preview")],
        commandLineTools: [], bundleIdentifiers: ["dev.zed.Zed", "dev.zed.Zed-Preview"]
    )

    public static let warp = Agent(
        id: "warp", displayName: "Warp", category: .editor,
        processNames: [], pathFragments: ["/Warp.app/"], argumentFragments: [],
        apps: [App(bundle: "Warp.app", name: "Warp")], commandLineTools: [], bundleIdentifiers: ["dev.warp.Warp-Stable"]
    )

    public static let ollama = Agent(
        id: "ollama", displayName: "Ollama", category: .modelRuntime,
        processNames: ["ollama"], pathFragments: ["/Ollama.app/"], argumentFragments: [],
        apps: [App(bundle: "Ollama.app", name: "Ollama app")], commandLineTools: ["ollama"],
        bundleIdentifiers: ["com.electron.ollama"]
    )

    public static let lmStudio = Agent(
        id: "lmStudio", displayName: "LM Studio", category: .modelRuntime,
        processNames: ["lms", "llmster"], pathFragments: ["/LM Studio.app/"], argumentFragments: [],
        apps: [App(bundle: "LM Studio.app", name: "LM Studio")], commandLineTools: ["lms"],
        bundleIdentifiers: ["ai.elementlabs.lmstudio"]
    )

    /// A command-line agent whose name is too common to trust; recognised by its npm package.
    private static func packageAgent(_ id: String, _ name: String, package: String) -> Agent {
        Agent(
            id: id, displayName: name, category: .agent, processNames: [], pathFragments: [],
            argumentFragments: [package], apps: [], commandLineTools: [], bundleIdentifiers: []
        )
    }

    /// A command-line agent identified by its executable (or script) name and npm package.
    private static func cliAgent(_ id: String, _ name: String, tools: [String], package: String? = nil) -> Agent {
        Agent(
            id: id, displayName: name, category: .agent, processNames: Set(tools), pathFragments: [],
            argumentFragments: package.map { [$0] } ?? [], apps: [], commandLineTools: tools, bundleIdentifiers: []
        )
    }
}
