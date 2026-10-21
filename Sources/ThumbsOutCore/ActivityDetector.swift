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
        "gitstatusd", "gitstatusd-darwin-arm64", "starship", "direnv", "zsh-autosuggest",
    ]

    public let ignoredProcessNames: Set<String>

    public init(ignoredProcessNames: Set<String> = defaultIgnoredProcessNames) {
        self.ignoredProcessNames = ignoredProcessNames
    }

    public func activeCommands(in snapshot: [ProcessRecord], watching agents: Set<Agent>) -> [DetectedCommand] {
        walks(in: snapshot, watching: agents).flatMap(\.commands)
    }

    /// Agents with any process running, whether or not they're busy.
    public static func runningAgents(in snapshot: [ProcessRecord]) -> Set<Agent> {
        Set(agentPIDs(in: snapshot).keys)
    }

    /// Each running agent's outermost process.
    public static func agentPIDs(in snapshot: [ProcessRecord]) -> [Agent: Int32] {
        ProcessTree(snapshot).roots(for: Set(Agent.allCases)).reduce(into: [:]) { pids, root in
            if pids[root.1] == nil { pids[root.1] = root.0.pid }
        }
    }

    /// One walk per watched agent's root process, skipping local model runtimes.
    func walks(in snapshot: [ProcessRecord], watching agents: Set<Agent>) -> [Walk] {
        let tree = ProcessTree(snapshot)
        let commandAgents = Self.commandAgents(agents)
        return tree.roots(for: commandAgents).map { root, agent in
            walk(from: root, agent: agent, tree: tree, watched: commandAgents)
        }
    }

    static func commandAgents(_ agents: Set<Agent>) -> Set<Agent> {
        agents.filter { $0.category != .modelRuntime }
    }

    /// What one agent's tree holds: the commands running in it, and the processes they start under.
    struct Walk {
        var commands: [DetectedCommand] = []
        var spawners: [SpawnWatchTarget] = []
    }

    /// How the walk treats a process below an agent.
    enum Step {
        case command
        case skip
        case terminal
        case descend
    }

    func step(for process: ProcessRecord, agent: Agent, watched: Set<Agent>) -> Step {
        if Self.isCommandShell(process) { return isBackgroundCommandShell(process) ? .skip : .command }
        if Self.isShell(process) { return .terminal }
        let owner = Agent.agent(for: process)
        if let owner, owner != agent, watched.contains(owner) { return .skip }
        if owner != agent, isBackgroundService(process) { return .skip }
        return .descend
    }

    /// Walks one agent's tree. A watched agent nested inside it (Claude Code inside VS Code) is
    /// walked from its own root instead, so each command is credited to the innermost agent.
    private func walk(from root: ProcessRecord, agent: Agent, tree: ProcessTree, watched: Set<Agent>) -> Walk {
        var result = Walk(spawners: [SpawnWatchTarget(process: root, agent: agent, role: .process)])
        var visited: Set<Int32> = [root.pid]
        var stack = tree.children(of: root.pid)

        while let process = stack.popLast() {
            guard visited.insert(process.pid).inserted else { continue }
            switch step(for: process, agent: agent, watched: watched) {
            case .command:
                // A command shell's subtree belongs to the command it runs.
                result.commands.append(DetectedCommand(agent: agent, pid: process.pid, summary: summary(of: process)))
            case .skip:
                continue
            case .terminal:
                result.spawners.append(SpawnWatchTarget(process: process, agent: agent, role: .terminal))
                let (command, nested) = terminalActivity(in: process, agent: agent, tree: tree, watched: watched)
                if let command { result.commands.append(command) }
                stack.append(contentsOf: nested)
            case .descend:
                result.spawners.append(SpawnWatchTarget(process: process, agent: agent, role: .process))
                stack.append(contentsOf: tree.children(of: process.pid))
            }
        }
        result.commands.sort { $0.pid < $1.pid }
        return result
    }

    /// How a child of an interactive shell (a terminal tab) counts. Children that belong to this
    /// same agent (its own CLI in its own IDE's terminal) are walked further; an idle session of
    /// another watched agent isn't a command, since that agent covers itself.
    enum TerminalChild {
        case command
        case skip
        case nested
    }

    func terminalChild(_ child: ProcessRecord, agent: Agent, watched: Set<Agent>) -> TerminalChild {
        if ignoredProcessNames.contains(child.name) { return .skip }
        switch Agent.agent(for: child) {
        case agent: return .nested
        case let owner? where watched.contains(owner): return .skip
        default: return .command
        }
    }

    /// An interactive shell runs a command when it has a child process.
    private func terminalActivity(
        in shell: ProcessRecord, agent: Agent, tree: ProcessTree, watched: Set<Agent>
    ) -> (command: DetectedCommand?, nested: [ProcessRecord]) {
        var nested: [ProcessRecord] = []
        var commands: [ProcessRecord] = []
        for child in tree.children(of: shell.pid) {
            switch terminalChild(child, agent: agent, watched: watched) {
            case .nested: nested.append(child)
            case .skip: continue
            case .command: commands.append(child)
            }
        }
        let command = commands.min { $0.pid < $1.pid }.map {
            DetectedCommand(agent: agent, pid: $0.pid, summary: summary(of: $0))
        }
        return (command, nested)
    }

    /// Processes we may not inspect (e.g. `sudo` children) have no arguments.
    func summary(of process: ProcessRecord) -> String {
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

    /// A process and all its descendants.
    func subtree(of root: ProcessRecord) -> [ProcessRecord] {
        var result: [ProcessRecord] = []
        var visited: Set<Int32> = []
        var stack = [root]
        while let process = stack.popLast() {
            guard visited.insert(process.pid).inserted else { continue }
            result.append(process)
            stack.append(contentsOf: children(of: process.pid))
        }
        return result
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
