import Testing
@testable import ThumbsOutCore

@Suite("Short commands between snapshots")
struct SpawnActivityTests {
    let detector = ActivityDetector(ignoredProcessNames: ActivityDetector.defaultIgnoredProcessNames)
    let everyAgent = Set(Agent.allCases)

    let claude = Fixtures.process(10, parent: 1, Fixtures.claudeCLIPath)
    let shell = Fixtures.process(32, parent: 31, "/bin/zsh", "-l")

    var claudeTarget: SpawnWatchTarget { SpawnWatchTarget(process: claude, agent: .claudeCode, role: .process) }
    var terminalTarget: SpawnWatchTarget { SpawnWatchTarget(process: shell, agent: .antigravity, role: .terminal) }

    func spawned(_ child: ProcessRecord, by parent: SpawnWatchTarget, watching: Set<Agent>? = nil) -> SpawnedProcess {
        detector.classify(child, startedBy: parent, watching: watching ?? everyAgent)
    }

    // MARK: What to watch

    @Test("watches the agent and the processes its commands start under, not the commands or helpers")
    func watchTargets() {
        let snapshot = [
            Fixtures.launchd,
            claude,
            Fixtures.process(11, parent: 10, "/bin/zsh", "-c", "source s.sh && eval 'npm test' < /dev/null"),
            Fixtures.process(12, parent: 10, "/opt/homebrew/bin/node", "/tmp/github-mcp-server/index.js"),
            Fixtures.process(30, parent: 1, Fixtures.antigravityPath),
            Fixtures.process(31, parent: 30, Fixtures.antigravityHelperPath, "--type=utility"),
            shell,
            Fixtures.process(20, parent: 1, "/opt/homebrew/bin/codex"),
            Fixtures.process(21, parent: 20, "/usr/bin/sandbox-exec", "-p", "(policy)", "bash", "-lc", "cargo build"),
        ]
        let targets = detector.spawnWatchTargets(in: snapshot, watching: everyAgent)
        #expect(targets.map(\.process.pid).sorted() == [10, 20, 21, 30, 31, 32])
        #expect(targets.first { $0.process.pid == 32 }?.role == .terminal)
        #expect(targets.first { $0.process.pid == 21 }?.agent == .chatGPT)
    }

    @Test("unwatched agents and local model runtimes aren't watched")
    func unwatchedTargets() {
        let snapshot = [
            Fixtures.launchd,
            claude,
            Fixtures.process(50, parent: 1, "/Applications/Ollama.app/Contents/Resources/ollama", "serve"),
        ]
        #expect(detector.spawnWatchTargets(in: snapshot, watching: [.chatGPT, .ollama]).isEmpty)
    }

    // MARK: What a new child is

    @Test("a command shell the agent starts is a command, however short")
    func commandShell() {
        let child = Fixtures.process(11, parent: 10, "/bin/zsh", "-c", "source s.sh && eval 'cat Package.swift' < /dev/null")
        #expect(spawned(child, by: claudeTarget) == .command(DetectedCommand(agent: .claudeCode, pid: 11, summary: "cat Package.swift")))
    }

    @Test("MCP servers and package-runner helpers are ignored", arguments: [
        ["/opt/homebrew/bin/node", "/opt/homebrew/bin/npx", "-y", "some-server"],
        ["/opt/homebrew/bin/node", "/tmp/github-mcp-server/index.js"],
        ["/bin/sh", "-c", "uvx some-server"],
        ["/bin/sh", "-c", "node /opt/github-mcp/server.js"],
    ])
    func helpersIgnored(arguments: [String]) {
        let child = ProcessRecord(pid: 11, ppid: 10, path: arguments[0], arguments: arguments)
        #expect(spawned(child, by: claudeTarget) == .ignored)
    }

    @Test("a program the agent runs directly is watched, since a command shell may start under it")
    func intermediateWatched() {
        let codex = Fixtures.process(20, parent: 1, "/opt/homebrew/bin/codex")
        let sandbox = Fixtures.process(21, parent: 20, "/usr/bin/sandbox-exec", "-p", "(policy)", "bash", "-lc", "cargo build")
        let codexTarget = SpawnWatchTarget(process: codex, agent: .chatGPT, role: .process)
        #expect(spawned(sandbox, by: codexTarget) == .watch(SpawnWatchTarget(process: sandbox, agent: .chatGPT, role: .process)))

        let sandboxTarget = SpawnWatchTarget(process: sandbox, agent: .chatGPT, role: .process)
        let bash = Fixtures.process(22, parent: 21, "/bin/bash", "-lc", "cargo build")
        #expect(spawned(bash, by: sandboxTarget) == .command(DetectedCommand(agent: .chatGPT, pid: 22, summary: "cargo build")))
    }

    @Test("a new terminal tab is watched as a terminal")
    func newTerminal() {
        let helper = SpawnWatchTarget(
            process: Fixtures.process(31, parent: 30, Fixtures.antigravityHelperPath), agent: .antigravity, role: .process
        )
        let tab = Fixtures.process(33, parent: 31, "/bin/zsh", "-l")
        #expect(spawned(tab, by: helper) == .watch(SpawnWatchTarget(process: tab, agent: .antigravity, role: .terminal)))
    }

    @Test("a child that hasn't exec'd yet is looked at again once it does")
    func forkedCopy() {
        let copy = ProcessRecord(pid: 33, ppid: 32, path: shell.path, arguments: shell.arguments)
        #expect(spawned(copy, by: terminalTarget) == .awaitingExec)
        let claudeCopy = ProcessRecord(pid: 11, ppid: 10, path: claude.path, arguments: claude.arguments)
        #expect(spawned(claudeCopy, by: claudeTarget) == .awaitingExec)
    }

    @Test("any program started in a watched terminal is a command")
    func terminalCommand() {
        let child = Fixtures.process(33, parent: 32, "/usr/local/bin/pytest", "-q")
        #expect(spawned(child, by: terminalTarget) == .command(DetectedCommand(agent: .antigravity, pid: 33, summary: "pytest -q")))
    }

    @Test("prompt helpers in a terminal are ignored")
    func terminalHelpers() {
        let child = Fixtures.process(33, parent: 32, "/Users/me/.cache/gitstatus/gitstatusd-darwin-arm64", "-s", "-1")
        #expect(spawned(child, by: terminalTarget) == .ignored)
    }

    @Test("another watched agent started in a terminal covers itself")
    func otherAgentInTerminal() {
        let child = Fixtures.process(33, parent: 32, "/Users/me/.local/bin/claude")
        #expect(spawned(child, by: terminalTarget) == .ignored)
        #expect(spawned(child, by: terminalTarget, watching: [.antigravity])
            == .command(DetectedCommand(agent: .antigravity, pid: 33, summary: "claude")))
    }

    @Test("the agent's own CLI in its terminal is watched like the agent")
    func ownCLIInTerminal() {
        let cursorShell = Fixtures.process(61, parent: 60, "/bin/zsh", "-i")
        let target = SpawnWatchTarget(process: cursorShell, agent: .cursor, role: .terminal)
        let agentCLI = Fixtures.process(62, parent: 61, "/Users/me/.local/bin/cursor-agent")
        #expect(spawned(agentCLI, by: target) == .watch(SpawnWatchTarget(process: agentCLI, agent: .cursor, role: .process)))
    }

    @Test("a watched agent started by another is left to its own watch")
    func nestedAgent() {
        let vscode = SpawnWatchTarget(
            process: Fixtures.process(40, parent: 1, "/Applications/Visual Studio Code.app/Contents/MacOS/Electron"),
            agent: .vscode, role: .process
        )
        let inner = Fixtures.process(41, parent: 40, "/Users/me/.vscode/extensions/anthropic.claude-code/resources/claude")
        #expect(spawned(inner, by: vscode, watching: [.vscode, .claudeCode]) == .ignored)
        #expect(spawned(inner, by: vscode, watching: [.vscode]) == .watch(SpawnWatchTarget(process: inner, agent: .vscode, role: .process)))
    }
}
