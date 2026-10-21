/// Work an agent did between two snapshots: commands that started and finished in between, and
/// writes to its session transcripts. Folding it in keeps the agent "working" (and the grace period
/// fresh) while it reads, edits and thinks, which runs no process a snapshot could catch.
extension ActivityDetector {
    /// Shown for an agent that's working without a command we could see.
    public static let workingSummary = "Working"

    /// `commands`, plus a line for each other agent that worked since the last tick: the latest
    /// short command it ran, or `workingSummary` if it wrote a transcript while its process runs.
    public static func addingRecentWork(
        to commands: [DetectedCommand],
        shortCommands: [DetectedCommand],
        transcriptWriters: Set<Agent>,
        agentPIDs: [Agent: Int32]
    ) -> [DetectedCommand] {
        let busy = Set(commands.map(\.agent))
        let latestShort = Dictionary(shortCommands.map { ($0.agent, $0) }, uniquingKeysWith: { _, latest in latest })
        let recent = Agent.allCases.filter { !busy.contains($0) }.compactMap { agent -> DetectedCommand? in
            if let command = latestShort[agent] { return command }
            guard transcriptWriters.contains(agent), let pid = agentPIDs[agent] else { return nil }
            return DetectedCommand(agent: agent, pid: pid, summary: workingSummary)
        }
        return commands + recent
    }
}
