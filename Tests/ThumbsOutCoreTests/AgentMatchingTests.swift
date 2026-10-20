import Testing
@testable import ThumbsOutCore

@Suite("Agent matching")
struct AgentMatchingTests {
    @Test("recognises the native Claude Code CLI")
    func claudeNative() {
        let record = Fixtures.process(10, parent: 1, Fixtures.claudeCLIPath)
        #expect(Agent.agent(for: record) == .claudeCode)
    }

    @Test("recognises the CLI by argv[0] when the binary lives elsewhere")
    func claudeByArgvZero() {
        let record = ProcessRecord(pid: 10, ppid: 1, path: "/opt/tools/2.1.72", arguments: ["claude", "--resume"])
        #expect(Agent.agent(for: record) == .claudeCode)
    }

    @Test("recognises Claude Code bundled inside the Claude desktop app")
    func claudeBundled() {
        let record = Fixtures.process(10, parent: 1, Fixtures.claudeBundledPath, "--output-format", "stream-json")
        #expect(Agent.agent(for: record) == .claudeCode)
    }

    @Test("recognises Claude Code installed through npm")
    func claudeNpm() {
        let record = Fixtures.process(
            10, parent: 1, "/opt/homebrew/bin/node",
            "/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js"
        )
        #expect(Agent.agent(for: record) == .claudeCode)
    }

    @Test("does not treat the Claude desktop app itself as Claude Code")
    func claudeDesktopIsNotCode() {
        let record = Fixtures.process(10, parent: 1, "/Applications/Claude.app/Contents/MacOS/Claude")
        #expect(Agent.agent(for: record) == nil)
    }

    @Test("recognises ChatGPT and Codex", arguments: [
        "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT",
        "/Applications/Codex.app/Contents/MacOS/Codex",
        "/opt/homebrew/bin/codex",
    ])
    func chatGPT(path: String) {
        #expect(Agent.agent(for: Fixtures.process(10, parent: 1, path)) == .chatGPT)
    }

    @Test("recognises Codex CLI installed through npm")
    func codexNpm() {
        let record = Fixtures.process(
            10, parent: 1, "/opt/homebrew/bin/node", "/opt/homebrew/lib/node_modules/@openai/codex/bin/codex.js"
        )
        #expect(Agent.agent(for: record) == .chatGPT)
    }

    @Test("recognises Antigravity and its helpers", arguments: [
        Fixtures.antigravityPath,
        Fixtures.antigravityHelperPath,
        "/Applications/Antigravity IDE.app/Contents/MacOS/Electron",
        "/Applications/Antigravity.app/Contents/Resources/bin/language_server",
    ])
    func antigravity(path: String) {
        #expect(Agent.agent(for: Fixtures.process(10, parent: 1, path)) == .antigravity)
    }

    @Test("ignores unrelated processes", arguments: [
        "/bin/zsh", "/usr/bin/git", "/Applications/Safari.app/Contents/MacOS/Safari", "/usr/local/bin/claudette",
    ])
    func unrelated(path: String) {
        #expect(Agent.agent(for: Fixtures.process(10, parent: 1, path)) == nil)
    }
}
