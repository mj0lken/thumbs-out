/// A process to watch for new children, because an agent's commands start under it.
public struct SpawnWatchTarget: Sendable, Equatable {
    public enum Role: Sendable, Equatable {
        /// The agent, or a process it runs through: a command shell it starts is a command.
        case process
        /// An interactive shell (a terminal tab): any program it starts is a command.
        case terminal
    }

    public let process: ProcessRecord
    public let agent: Agent
    public let role: Role

    public init(process: ProcessRecord, agent: Agent, role: Role) {
        self.process = process
        self.agent = agent
        self.role = role
    }
}

/// What a process that just started under a watched one turned out to be.
public enum SpawnedProcess: Sendable, Equatable {
    /// A command, which may finish long before the next snapshot.
    case command(DetectedCommand)
    /// Not a command, but commands may start under it, so it's watched too.
    case watch(SpawnWatchTarget)
    /// Forked but not yet running a program of its own: look again once it execs.
    case awaitingExec
    /// A helper (an MCP server, `gitstatusd`, a background shell) or an agent that covers itself.
    case ignored
}

/// Catches commands too short for a snapshot: the app watches the processes an agent's commands
/// start under and asks what each new child is. The rules are the snapshot walk's, so a short
/// command counts exactly when it would have counted had a snapshot caught it running.
extension ActivityDetector {
    public func spawnWatchTargets(in snapshot: [ProcessRecord], watching agents: Set<Agent>) -> [SpawnWatchTarget] {
        walks(in: snapshot, watching: agents).flatMap(\.spawners)
    }

    public func classify(
        _ child: ProcessRecord, startedBy parent: SpawnWatchTarget, watching agents: Set<Agent>
    ) -> SpawnedProcess {
        // Right after `fork` and before `exec`, a child is a copy of its parent.
        if child.path == parent.process.path, child.arguments == parent.process.arguments { return .awaitingExec }
        let watched = Self.commandAgents(agents)
        let agent = parent.agent
        let command = SpawnedProcess.command(DetectedCommand(agent: agent, pid: child.pid, summary: summary(of: child)))

        switch parent.role {
        case .terminal:
            switch terminalChild(child, agent: agent, watched: watched) {
            case .command: return command
            case .skip: return .ignored
            case .nested: return .watch(SpawnWatchTarget(process: child, agent: agent, role: .process))
            }
        case .process:
            switch step(for: child, agent: agent, watched: watched) {
            case .command: return command
            case .skip: return .ignored
            case .terminal: return .watch(SpawnWatchTarget(process: child, agent: agent, role: .terminal))
            case .descend: return .watch(SpawnWatchTarget(process: child, agent: agent, role: .process))
            }
        }
    }
}
