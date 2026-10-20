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
        "/Applications/Antigravity.app/Contents/Resources/bin/language_server",
    ])
    func antigravity(path: String) {
        #expect(Agent.agent(for: Fixtures.process(10, parent: 1, path)) == .antigravity)
    }

    @Test("Antigravity IDE is its own entry, watched by default", arguments: [
        "/Applications/Antigravity IDE.app/Contents/MacOS/Electron",
        "/Applications/Antigravity IDE.app/Contents/Frameworks/Antigravity IDE Helper.app/Contents/MacOS/Antigravity IDE Helper",
    ])
    func antigravityIDE(path: String) {
        #expect(Agent.agent(for: Fixtures.process(10, parent: 1, path)) == .antigravityIDE)
        #expect(Agent.antigravityIDE.isWatchedByDefault)
    }

    @Test("ignores unrelated processes", arguments: [
        "/bin/zsh", "/usr/bin/git", "/Applications/Safari.app/Contents/MacOS/Safari", "/usr/local/bin/claudette",
    ])
    func unrelated(path: String) {
        #expect(Agent.agent(for: Fixtures.process(10, parent: 1, path)) == nil)
    }

    @Test("recognises the newer agents by app, CLI or script", arguments: [
        ("/Applications/Cursor.app/Contents/MacOS/Cursor", [], "cursor"),
        ("/Users/me/.local/share/cursor-agent/versions/2025.09.18/node", ["--use-system-ca", "/Users/me/.local/share/cursor-agent/versions/2025.09.18/index.js"], "cursor"),
        ("/opt/homebrew/Cellar/node/24.1.0/bin/node", ["/opt/homebrew/bin/gemini"], "antigravity"),
        ("/Applications/Windsurf.app/Contents/MacOS/Electron", [], "windsurf"),
        ("/Applications/Kiro.app/Contents/MacOS/Electron", [], "kiro"),
        ("/opt/homebrew/bin/node", ["/opt/homebrew/lib/node_modules/@github/copilot/index.js"], "copilot"),
        ("/Users/me/.opencode/bin/opencode", [], "opencode"),
        ("/Users/me/.local/share/uv/tools/aider-chat/bin/python3", ["/Users/me/.local/bin/aider"], "aider"),
        ("/Applications/Goose.app/Contents/MacOS/goosed", [], "goose"),
        ("/Applications/Visual Studio Code.app/Contents/MacOS/Electron", [], "vscode"),
        ("/Applications/Zed.app/Contents/MacOS/zed", [], "zed"),
        ("/Applications/Warp.app/Contents/MacOS/stable", [], "warp"),
        ("/Applications/Ollama.app/Contents/Resources/ollama", ["serve"], "ollama"),
        ("/Applications/LM Studio.app/Contents/MacOS/LM Studio", [], "lmStudio"),
    ])
    func newerAgents(path: String, args: [String], expected: String) {
        let record = ProcessRecord(pid: 10, ppid: 1, path: path, arguments: [path] + args)
        #expect(Agent.agent(for: record)?.id == expected)
    }

    @Test("does not mistake macOS's own CursorUIViewService for Cursor")
    func cursorUIViewService() {
        let path = "/System/Library/PrivateFrameworks/TextInputUIMacHelper.framework/Versions/A/XPCServices/"
            + "CursorUIViewService.xpc/Contents/MacOS/CursorUIViewService"
        #expect(Agent.agent(for: Fixtures.process(10, parent: 1, path)) == nil)
    }

    @Test("plain node or python processes are not agents")
    func plainInterpreters() {
        #expect(Agent.agent(for: Fixtures.process(10, parent: 1, "/opt/homebrew/bin/node", "server.js")) == nil)
        #expect(Agent.agent(for: Fixtures.process(11, parent: 1, "/usr/bin/python3", "-m", "http.server")) == nil)
    }

    @Test("agents are on by default; editors and local models are opt-in")
    func defaults() {
        #expect(Agent.claudeCode.isWatchedByDefault)
        #expect(Agent.cursor.isWatchedByDefault)
        #expect(!Agent.vscode.isWatchedByDefault)
        #expect(!Agent.ollama.isWatchedByDefault)
        #expect(Set(Agent.allCases.map(\.id)).count == Agent.allCases.count)
    }

    @Test("existing settings keys keep their ids")
    func stableIDs() {
        #expect([Agent.claudeCode, .chatGPT, .antigravity].map(\.id) == ["claudeCode", "chatGPT", "antigravity"])
    }

    @Test("tools that share a name with an agent are not mistaken for it", arguments: [
        "/Users/me/go/bin/goose",                       // pressly/goose database migrations
        "/opt/homebrew/bin/copilot",                    // AWS Copilot CLI
        "/opt/homebrew/bin/amp",                        // the amp text editor
    ])
    func ambiguousNames(path: String) {
        #expect(Agent.agent(for: Fixtures.process(10, parent: 1, path, "up")) == nil)
    }

    @Test("ambiguous agents are still recognised by their package or install path", arguments: [
        ("/opt/homebrew/bin/node", ["/opt/homebrew/lib/node_modules/@github/copilot/index.js"], "copilot"),
        ("/opt/homebrew/bin/node", ["/opt/homebrew/lib/node_modules/@sourcegraph/amp/dist/main.js"], "amp"),
        ("/opt/homebrew/Cellar/block-goose-cli/1.9.0/bin/goose", [], "goose"),
    ])
    func ambiguousByPackage(path: String, args: [String], expected: String) {
        let record = ProcessRecord(pid: 10, ppid: 1, path: path, arguments: [path] + args)
        #expect(Agent.agent(for: record)?.id == expected)
    }

    @Test("shells are never agents, whatever their command mentions")
    func shellsAreNotAgents() {
        let record = Fixtures.process(10, parent: 1, "/bin/zsh", "-c", "npm i -g @anthropic-ai/claude-code")
        #expect(Agent.agent(for: record) == nil)
    }
}
