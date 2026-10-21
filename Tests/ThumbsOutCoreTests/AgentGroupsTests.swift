import Testing
@testable import ThumbsOutCore

@Suite("Agent groups")
struct AgentGroupsTests {
    let catalog: [Agent] = [.claudeCode, .chatGPT, .cursor, .vscode, .ollama]

    func group(_ statuses: [Agent: AgentStatus], watched: Set<Agent> = [.claudeCode, .chatGPT, .cursor]) -> AgentGroups {
        AgentGroups.group(catalog, watched: watched) { statuses[$0] ?? .notFound }
    }

    @Test("splits the catalog into open, installed and not installed")
    func splits() {
        let groups = group([.claudeCode: .working(1), .chatGPT: .installed, .cursor: .running])
        #expect(groups.open == [.claudeCode, .cursor])
        #expect(groups.installed == [.chatGPT])
        #expect(groups.notInstalled == [.vscode, .ollama])
    }

    @Test("an editor left open only counts as open while watched")
    func unwatchedEditor() {
        let statuses: [Agent: AgentStatus] = [.vscode: .running]
        #expect(group(statuses).open.isEmpty)
        #expect(group(statuses).installed == [.vscode])
        #expect(group(statuses, watched: [.vscode]).open == [.vscode])
    }

    @Test("an agent switched off still shows as open while it runs")
    func unwatchedAgent() {
        #expect(group([.cursor: .running], watched: []).open == [.cursor])
    }

    @Test("a clean Mac has nothing open or installed")
    func clean() {
        let groups = group([:])
        #expect(groups.open.isEmpty)
        #expect(groups.installed.isEmpty)
        #expect(groups.notInstalled == catalog)
    }

    @Test("keeps catalog order within a group")
    func catalogOrder() {
        let groups = group([.ollama: .installed, .claudeCode: .installed, .cursor: .installed])
        #expect(groups.installed == [.claudeCode, .cursor, .ollama])
    }

    @Test("only running and working agents are open", arguments: [
        (AgentStatus.notFound, false), (.installed, false), (.running, true), (.working(2), true),
    ])
    func isOpen(status: AgentStatus, expected: Bool) {
        #expect(status.isOpen == expected)
    }
}
