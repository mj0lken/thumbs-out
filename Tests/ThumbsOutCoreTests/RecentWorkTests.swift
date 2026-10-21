import Testing
@testable import ThumbsOutCore

@Suite("Recent work between snapshots")
struct RecentWorkTests {
    let running: [Agent: Int32] = [.claudeCode: 10, .chatGPT: 20]

    func merged(
        _ commands: [DetectedCommand] = [], short: [DetectedCommand] = [], writers: Set<Agent> = []
    ) -> [DetectedCommand] {
        ActivityDetector.addingRecentWork(to: commands, shortCommands: short, transcriptWriters: writers, agentPIDs: running)
    }

    @Test("an agent that wrote its transcript is working, credited to its process")
    func transcriptWrite() {
        #expect(merged(writers: [.claudeCode]) == [
            DetectedCommand(agent: .claudeCode, pid: 10, summary: ActivityDetector.workingSummary),
        ])
    }

    @Test("a transcript write doesn't count once the agent has quit")
    func transcriptWithoutProcess() {
        #expect(merged(writers: [.antigravity]).isEmpty)
    }

    @Test("an agent that ran short commands shows the latest one")
    func shortCommands() {
        let short = [
            DetectedCommand(agent: .claudeCode, pid: 11, summary: "ls"),
            DetectedCommand(agent: .claudeCode, pid: 12, summary: "cat Package.swift"),
        ]
        #expect(merged(short: short, writers: [.claudeCode]) == [short[1]])
    }

    @Test("a command running now wins over recent work")
    func runningWins() {
        let live = DetectedCommand(agent: .claudeCode, pid: 13, summary: "swift test")
        let short = [DetectedCommand(agent: .claudeCode, pid: 11, summary: "ls")]
        #expect(merged([live], short: short, writers: [.claudeCode]) == [live])
    }

    @Test("each agent's recent work is added alongside running commands")
    func severalAgents() {
        let live = DetectedCommand(agent: .claudeCode, pid: 13, summary: "swift test")
        #expect(merged([live], writers: [.claudeCode, .chatGPT]) == [
            live, DetectedCommand(agent: .chatGPT, pid: 20, summary: ActivityDetector.workingSummary),
        ])
    }

    @Test("nothing recent adds nothing")
    func nothing() {
        #expect(merged().isEmpty)
    }

    @Test("each running agent is credited to its outermost process")
    func agentPIDs() {
        let snapshot = [
            Fixtures.launchd,
            Fixtures.process(10, parent: 1, Fixtures.claudeCLIPath),
            Fixtures.process(12, parent: 1, Fixtures.claudeCLIPath),
            Fixtures.process(30, parent: 1, Fixtures.antigravityPath),
            Fixtures.process(31, parent: 30, Fixtures.antigravityHelperPath),
        ]
        #expect(ActivityDetector.agentPIDs(in: snapshot) == [.claudeCode: 10, .antigravity: 30])
    }
}
