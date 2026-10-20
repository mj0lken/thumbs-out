/// A command an agent is currently running.
public struct DetectedCommand: Sendable, Equatable, Identifiable {
    public let agent: Agent
    public let pid: Int32
    public let summary: String

    public var id: Int32 { pid }

    public init(agent: Agent, pid: Int32, summary: String) {
        self.agent = agent
        self.pid = pid
        self.summary = summary
    }
}

/// Finds agents that are running shell commands by walking the process tree.
///
/// Agents run commands through a shell: Claude Code and Codex spawn `zsh -c …` / `bash -lc …`,
/// Antigravity runs them in an interactive terminal shell. So below each agent process we look for
/// - a non-interactive command shell (`-c`), which exists only while the command runs, or
/// - an interactive shell that currently has a child process (a command in the terminal).
///
/// Long-lived helpers such as MCP servers are skipped so they do not keep the Mac awake forever.
public struct ActivityDetector: Sendable {
    public static let shellNames: Set<String> = ["sh", "bash", "zsh", "fish", "dash", "ksh", "tcsh", "csh", "nu"]

    /// Package runners that agents use to start long-running MCP servers.
    static let serviceLauncherNames: Set<String> = ["npx", "uvx", "bunx", "pnpx"]

    /// Background helpers that interactive shells keep alive without the user running anything.
    public static let defaultIgnoredProcessNames: Set<String> = [
        "gitstatusd", "gitstatusd-darwin-arm64", "gitstatusd-darwin-x86_64", "starship", "direnv", "zsh-autosuggest",
    ]

    public let ignoredProcessNames: Set<String>

    public init(ignoredProcessNames: Set<String> = defaultIgnoredProcessNames) {
        self.ignoredProcessNames = ignoredProcessNames
    }

    public func activeCommands(in snapshot: [ProcessRecord], watching agents: Set<Agent>) -> [DetectedCommand] {
        let tree = ProcessTree(snapshot)
        return tree.roots(for: agents).flatMap { root, agent in
            commands(below: root, agent: agent, tree: tree)
        }
    }

    /// Agents with any process running, whether or not they're busy.
    public static func runningAgents(in snapshot: [ProcessRecord]) -> Set<Agent> {
        Set(ProcessTree(snapshot).roots(for: Set(Agent.allCases)).map(\.1))
    }

    private func commands(below root: ProcessRecord, agent: Agent, tree: ProcessTree) -> [DetectedCommand] {
        var found: [DetectedCommand] = []
        var visited: Set<Int32> = [root.pid]
        var stack = tree.children(of: root.pid)

        while let process = stack.popLast() {
            guard visited.insert(process.pid).inserted else { continue }

            if Self.isShell(process) {
                if let command = command(in: process, agent: agent, tree: tree) {
                    found.append(command)
                }
                continue // A shell's subtree belongs to the command it is running.
            }
            if Agent.agent(for: process) == nil, isBackgroundService(process) {
                continue
            }
            stack.append(contentsOf: tree.children(of: process.pid))
        }
        return found.sorted { $0.pid < $1.pid }
    }

    private func command(in shell: ProcessRecord, agent: Agent, tree: ProcessTree) -> DetectedCommand? {
        if Self.isCommandShell(shell) {
            guard !isBackgroundCommandShell(shell) else { return nil }
            return DetectedCommand(agent: agent, pid: shell.pid, summary: summary(of: shell))
        }
        let running = tree.children(of: shell.pid).filter { !ignoredProcessNames.contains($0.name) }
        guard let child = running.min(by: { $0.pid < $1.pid }) else { return nil }
        return DetectedCommand(agent: agent, pid: child.pid, summary: summary(of: child))
    }

    /// Processes we may not inspect (e.g. `sudo` children) have no arguments.
    private func summary(of process: ProcessRecord) -> String {
        let text = CommandSummary.summarize(process.arguments)
        return text.isEmpty ? "process \(process.pid)" : text
    }

    /// A `sh -c` used to start an MCP server rather than to run a command. Claude Code's own
    /// `eval '…'` wrapper always means a real command, even if it mentions MCP.
    func isBackgroundCommandShell(_ shell: ProcessRecord) -> Bool {
        guard let script = CommandSummary.shellScript(shell.arguments),
              CommandSummary.unwrapEval(script) == nil
        else { return false }
        let firstWord = script.split(whereSeparator: \.isWhitespace).first
            .map { $0.split(separator: "/").last.map(String.init) ?? String($0) } ?? ""
        return Self.serviceLauncherNames.contains(firstWord) || ignoredProcessNames.contains(firstWord)
            || script.localizedCaseInsensitiveContains("mcp")
    }

    func isBackgroundService(_ process: ProcessRecord) -> Bool {
        if ignoredProcessNames.contains(process.name) { return true }
        let words = [process.name] + process.arguments.prefix(2).map { $0.split(separator: "/").last.map(String.init) ?? $0 }
        if words.contains(where: Self.serviceLauncherNames.contains) { return true }
        return process.arguments.contains { $0.localizedCaseInsensitiveContains("mcp") }
    }

    public static func isShell(_ process: ProcessRecord) -> Bool {
        shellNames.contains(process.name)
    }

    public static func isCommandShell(_ process: ProcessRecord) -> Bool {
        isShell(process) && process.arguments.dropFirst().contains(where: isCommandFlag)
    }

    /// `-c`, `-lc`, `-ic`, `--command`, but not `--login` or `-l`.
    static func isCommandFlag(_ argument: String) -> Bool {
        if argument == "--command" { return true }
        guard argument.hasPrefix("-"), !argument.hasPrefix("--") else { return false }
        return argument.dropFirst().contains("c")
    }
}

/// Parent/child lookups over a process snapshot.
struct ProcessTree {
    private let byPid: [Int32: ProcessRecord]
    private let childrenByPid: [Int32: [ProcessRecord]]

    init(_ snapshot: [ProcessRecord]) {
        byPid = Dictionary(snapshot.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        childrenByPid = Dictionary(grouping: snapshot.filter { $0.pid != $0.ppid }, by: \.ppid)
    }

    func children(of pid: Int32) -> [ProcessRecord] {
        childrenByPid[pid] ?? []
    }

    /// Topmost process of each watched agent, so nested agent processes are walked once.
    func roots(for agents: Set<Agent>) -> [(ProcessRecord, Agent)] {
        byPid.values
            .compactMap { process -> (ProcessRecord, Agent)? in
                guard let agent = Agent.agent(for: process), agents.contains(agent) else { return nil }
                return hasAncestor(of: process, matching: agent) ? nil : (process, agent)
            }
            .sorted { $0.0.pid < $1.0.pid }
    }

    private func hasAncestor(of process: ProcessRecord, matching agent: Agent) -> Bool {
        var seen: Set<Int32> = [process.pid]
        var current = byPid[process.ppid]
        while let ancestor = current, seen.insert(ancestor.pid).inserted {
            if Agent.agent(for: ancestor) == agent { return true }
            current = byPid[ancestor.ppid]
        }
        return false
    }
}
