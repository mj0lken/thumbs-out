import Testing
@testable import ThumbsOutCore

@Suite("Activity detection")
struct ActivityDetectorTests {
    let detector = ActivityDetector(ignoredProcessNames: ActivityDetector.defaultIgnoredProcessNames)
    let everyAgent = Set(Agent.allCases)

    @Test("idle Claude Code session is not active")
    func idleClaude() {
        let snapshot = [Fixtures.launchd, Fixtures.process(10, parent: 1, Fixtures.claudeCLIPath)]
        #expect(detector.activeCommands(in: snapshot, watching: everyAgent).isEmpty)
    }

    @Test("Claude Code running a command through `zsh -c` is active")
    func claudeRunningCommand() {
        let snapshot = [
            Fixtures.launchd,
            Fixtures.process(10, parent: 1, Fixtures.claudeCLIPath),
            Fixtures.process(11, parent: 10, "/bin/zsh", "-c", "source snap.sh && eval 'npm test' < /dev/null"),
        ]
        let commands = detector.activeCommands(in: snapshot, watching: everyAgent)
        #expect(commands == [DetectedCommand(agent: .claudeCode, pid: 11, summary: "npm test")])
    }

    @Test("Codex running a sandboxed `bash -lc` command is active")
    func codexSandboxed() {
        let snapshot = [
            Fixtures.launchd,
            Fixtures.process(20, parent: 1, "/opt/homebrew/bin/codex"),
            Fixtures.process(21, parent: 20, "/usr/bin/sandbox-exec", "-p", "(policy)", "bash", "-lc", "cargo build"),
            Fixtures.process(22, parent: 21, "/bin/bash", "-lc", "cargo build"),
        ]
        let commands = detector.activeCommands(in: snapshot, watching: everyAgent)
        #expect(commands.map(\.agent) == [.chatGPT])
        #expect(commands.first?.summary == "cargo build")
    }

    @Test("Antigravity terminal with an idle interactive shell is not active")
    func antigravityIdleTerminal() {
        let snapshot = [
            Fixtures.launchd,
            Fixtures.process(30, parent: 1, Fixtures.antigravityPath),
            Fixtures.process(31, parent: 30, Fixtures.antigravityHelperPath, "--type=utility"),
            Fixtures.process(32, parent: 31, "/bin/zsh", "-l"),
        ]
        #expect(detector.activeCommands(in: snapshot, watching: everyAgent).isEmpty)
    }

    @Test("Antigravity terminal whose shell has a running child is active")
    func antigravityBusyTerminal() {
        let snapshot = [
            Fixtures.launchd,
            Fixtures.process(30, parent: 1, Fixtures.antigravityPath),
            Fixtures.process(31, parent: 30, Fixtures.antigravityHelperPath, "--type=utility"),
            Fixtures.process(32, parent: 31, "/bin/zsh", "-l"),
            Fixtures.process(33, parent: 32, "/usr/local/bin/pytest", "-q"),
        ]
        let commands = detector.activeCommands(in: snapshot, watching: everyAgent)
        #expect(commands == [DetectedCommand(agent: .antigravity, pid: 33, summary: "pytest -q")])
    }

    @Test("background helpers like gitstatusd under a shell do not count")
    func ignoredShellHelpers() {
        let snapshot = [
            Fixtures.launchd,
            Fixtures.process(30, parent: 1, Fixtures.antigravityPath),
            Fixtures.process(32, parent: 30, "/bin/zsh", "-l"),
            Fixtures.process(33, parent: 32, "/Users/me/.cache/gitstatus/gitstatusd-darwin-arm64", "-s", "-1"),
        ]
        let custom = ActivityDetector(ignoredProcessNames: ["gitstatusd-darwin-arm64"])
        #expect(custom.activeCommands(in: snapshot, watching: everyAgent).isEmpty)
    }

    @Test("MCP servers launched through npx do not count as commands")
    func mcpServersIgnored() {
        let snapshot = [
            Fixtures.launchd,
            Fixtures.process(10, parent: 1, Fixtures.claudeCLIPath),
            Fixtures.process(11, parent: 10, "/opt/homebrew/bin/node", "/opt/homebrew/bin/npx", "-y", "some-server"),
            Fixtures.process(12, parent: 11, "/bin/sh", "-c", "some-server"),
            Fixtures.process(13, parent: 10, "/opt/homebrew/bin/node", "/tmp/github-mcp-server/index.js"),
            Fixtures.process(14, parent: 13, "/bin/sh", "-c", "helper"),
        ]
        #expect(detector.activeCommands(in: snapshot, watching: everyAgent).isEmpty)
    }

    @Test("MCP servers launched through a command shell do not count", arguments: [
        ["-c", "node /opt/github-mcp/server.js"],
        ["-lc", "npx -y @modelcontextprotocol/server-filesystem ~"],
        ["-c", "uvx some-server"],
    ])
    func mcpCommandShellsIgnored(shellArgs: [String]) {
        let snapshot = [
            Fixtures.launchd,
            Fixtures.process(20, parent: 1, "/opt/homebrew/bin/codex"),
            ProcessRecord(pid: 21, ppid: 20, path: "/bin/sh", arguments: ["/bin/sh"] + shellArgs),
        ]
        #expect(detector.activeCommands(in: snapshot, watching: everyAgent).isEmpty)
    }

    @Test("Claude Code commands that mention MCP still count")
    func claudeMcpCommandCounts() {
        let snapshot = [
            Fixtures.launchd,
            Fixtures.process(10, parent: 1, Fixtures.claudeCLIPath),
            Fixtures.process(11, parent: 10, "/bin/zsh", "-c", "source s.sh && eval 'claude mcp list' < /dev/null"),
        ]
        #expect(detector.activeCommands(in: snapshot, watching: everyAgent).map(\.summary) == ["claude mcp list"])
    }

    @Test("a privileged child we cannot inspect still counts, with a fallback label")
    func uninspectableChild() {
        let snapshot = [
            Fixtures.launchd,
            Fixtures.process(30, parent: 1, Fixtures.antigravityPath),
            Fixtures.process(32, parent: 30, "/bin/zsh", "-l"),
            ProcessRecord(pid: 33, ppid: 32, path: "", arguments: []),
        ]
        let commands = detector.activeCommands(in: snapshot, watching: everyAgent)
        #expect(commands == [DetectedCommand(agent: .antigravity, pid: 33, summary: "process 33")])
    }

    @Test("agents that are not watched are skipped")
    func unwatchedAgent() {
        let snapshot = [
            Fixtures.launchd,
            Fixtures.process(10, parent: 1, Fixtures.claudeCLIPath),
            Fixtures.process(11, parent: 10, "/bin/zsh", "-c", "ls"),
        ]
        #expect(detector.activeCommands(in: snapshot, watching: [.antigravity, .chatGPT]).isEmpty)
    }

    @Test("a shell that merely launched an agent is not attributed as that agent's command")
    func shellAboveAgentIgnored() {
        let snapshot = [
            Fixtures.launchd,
            Fixtures.process(5, parent: 1, "/bin/zsh", "-c", "claude"),
            Fixtures.process(10, parent: 5, Fixtures.claudeCLIPath),
        ]
        #expect(detector.activeCommands(in: snapshot, watching: everyAgent).isEmpty)
    }

    @Test("each command is reported once even with nested agent processes")
    func nestedAgentsReportedOnce() {
        let snapshot = [
            Fixtures.launchd,
            Fixtures.process(10, parent: 1, "/opt/homebrew/bin/node", "/x/@anthropic-ai/claude-code/cli.js"),
            Fixtures.process(11, parent: 10, Fixtures.claudeCLIPath),
            Fixtures.process(12, parent: 11, "/bin/zsh", "-c", "make"),
        ]
        let commands = detector.activeCommands(in: snapshot, watching: everyAgent)
        #expect(commands.count == 1)
    }

    @Test("a cyclic parent chain does not hang")
    func cyclicParents() {
        let snapshot = [
            Fixtures.process(10, parent: 11, Fixtures.claudeCLIPath),
            Fixtures.process(11, parent: 10, "/bin/zsh", "-c", "ls"),
        ]
        _ = detector.activeCommands(in: snapshot, watching: everyAgent)
    }

    @Test("command-shell flags are recognised", arguments: [
        (["-c", "ls"], true), (["-lc", "ls"], true), (["-ic", "ls"], true), (["--command", "ls"], true),
        (["-l"], false), (["-i"], false), (["--login"], false), ([], false),
    ])
    func commandShellFlags(args: [String], expected: Bool) {
        let record = ProcessRecord(pid: 1, ppid: 0, path: "/bin/zsh", arguments: ["/bin/zsh"] + args)
        #expect(ActivityDetector.isCommandShell(record) == expected)
    }

    @Test("login shells reported as -zsh are still shells")
    func loginShellName() {
        let record = ProcessRecord(pid: 1, ppid: 0, path: "", arguments: ["-zsh"])
        #expect(ActivityDetector.isShell(record))
    }

    @Test("reports which agents are running at all, busy or not")
    func runningAgents() {
        let snapshot = [
            Fixtures.launchd,
            Fixtures.process(10, parent: 1, Fixtures.claudeCLIPath),
            Fixtures.process(30, parent: 1, Fixtures.antigravityPath),
            Fixtures.process(31, parent: 30, Fixtures.antigravityHelperPath),
        ]
        #expect(ActivityDetector.runningAgents(in: snapshot) == [.claudeCode, .antigravity])
    }
}
