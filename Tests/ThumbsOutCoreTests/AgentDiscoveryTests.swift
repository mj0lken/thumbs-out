import Testing
@testable import ThumbsOutCore

@Suite("Agent discovery")
struct AgentDiscoveryTests {
    let home = "/Users/me"

    func discover(_ existing: Set<String>, nodeVersions: [String] = []) -> [AgentInstallation] {
        AgentDiscovery.installations(home: home, nodeVersions: nodeVersions, fileExists: existing.contains)
    }

    @Test("finds nothing on a clean Mac")
    func clean() {
        #expect(discover([]).isEmpty)
    }

    @Test("finds desktop apps in /Applications and ~/Applications")
    func apps() {
        let found = discover(["/Applications/Claude.app", "/Users/me/Applications/Antigravity IDE.app"])
        #expect(found == [
            AgentInstallation(agent: .claudeCode, kind: .app, name: "Claude app", path: "/Applications/Claude.app"),
            AgentInstallation(agent: .antigravity, kind: .app, name: "Antigravity IDE",
                              path: "/Users/me/Applications/Antigravity IDE.app"),
        ])
    }

    @Test("finds command-line tools in common install locations")
    func clis() {
        let found = discover(["/Users/me/.local/bin/claude", "/opt/homebrew/bin/codex", "/Users/me/.local/bin/agy"])
        #expect(found.map(\.name) == ["claude CLI", "codex CLI", "agy CLI"])
        #expect(found.map(\.agent) == [.claudeCode, .chatGPT, .antigravity])
        #expect(found.allSatisfy { $0.kind == .commandLine })
    }

    @Test("finds npm installs under nvm")
    func nvm() {
        let found = discover(["/Users/me/.nvm/versions/node/v22.1.0/bin/codex"], nodeVersions: ["v22.1.0"])
        #expect(found.map(\.path) == ["/Users/me/.nvm/versions/node/v22.1.0/bin/codex"])
    }

    @Test("lists a tool once even when installed in several places")
    func deduplicates() {
        let found = discover(["/Users/me/.local/bin/claude", "/opt/homebrew/bin/claude"])
        #expect(found.count == 1)
        #expect(found.first?.path == "/Users/me/.local/bin/claude")
    }

    @Test("ignores updater staging copies, the Trash and translocated apps", arguments: [
        ("/Applications/Warp.app", true),
        ("/Users/me/Downloads/Cursor.app", true),
        ("/Users/me/Library/Application Support/dev.warp.Warp-Stable/autoupdate/x/Warp(v1).app", false),
        ("/Library/Caches/com.example/Claude.app", false),
        ("/Users/me/.Trash/ChatGPT.app", false),
        ("/private/var/folders/ab/T/AppTranslocation/123/d/Cursor.app", false),
    ])
    func userFacingApps(path: String, expected: Bool) {
        #expect(AgentDiscovery.isUserFacingApp(path: path) == expected)
    }

    @Test("every agent has bundle identifiers to look up apps installed elsewhere")
    func bundleIdentifiers() {
        #expect(Agent.claudeCode.bundleIdentifiers.contains("com.anthropic.claudefordesktop"))
        #expect(Agent.chatGPT.bundleIdentifiers.contains("com.openai.codex"))
        #expect(Agent.antigravity.bundleIdentifiers.contains("com.google.antigravity"))
    }
}

@Suite("Agent status")
struct AgentStatusTests {
    let app = AgentInstallation(agent: .claudeCode, kind: .app, name: "Claude app", path: "/Applications/Claude.app")

    func status(installed: Bool = false, running: Bool = false, commands: Int = 0) -> AgentStatus {
        let detected = (0..<commands).map { DetectedCommand(agent: .claudeCode, pid: Int32($0), summary: "ls") }
        return AgentStatus.resolve(
            .claudeCode,
            installations: installed ? [app] : [],
            runningAgents: running ? [.claudeCode] : [],
            commands: detected
        )
    }

    @Test("working beats running beats installed beats not found")
    func precedence() {
        #expect(status() == .notFound)
        #expect(status(installed: true) == .installed)
        #expect(status(installed: true, running: true) == .running)
        #expect(status(installed: true, running: true, commands: 2) == .working(2))
    }

    @Test("a running agent counts as found even if we could not locate its install")
    func runningWithoutInstall() {
        #expect(status(running: true) == .running)
    }

    @Test("other agents' commands are ignored")
    func otherAgents() {
        let status = AgentStatus.resolve(
            .antigravity, installations: [], runningAgents: [],
            commands: [DetectedCommand(agent: .claudeCode, pid: 1, summary: "ls")]
        )
        #expect(status == .notFound)
    }
}
