import Testing
@testable import ThumbsOutCore

@Suite("Command summaries")
struct CommandSummaryTests {
    @Test("unwraps Claude Code's eval wrapper")
    func claudeWrapper() {
        let script = "source /Users/me/.claude/shell-snapshots/snap.sh 2>/dev/null || true && "
            + "eval 'git status' < /dev/null && pwd -P >| /tmp/claude-1-cwd"
        #expect(CommandSummary.summarize(["/bin/zsh", "-c", "-l", script]) == "git status")
    }

    @Test("restores single quotes escaped inside the eval wrapper")
    func escapedQuotes() {
        let script = #"eval 'echo '"'"'hi'"'"'' < /dev/null && pwd -P >| /tmp/x"#
        #expect(CommandSummary.summarize(["/bin/zsh", "-c", script]) == "echo 'hi'")
    }

    @Test("uses the script after -c for plain command shells")
    func plainShell() {
        #expect(CommandSummary.summarize(["/bin/bash", "-lc", "cargo build --release"]) == "cargo build --release")
    }

    @Test("falls back to the executable name and arguments")
    func plainProcess() {
        #expect(CommandSummary.summarize(["/usr/local/bin/pytest", "-q", "tests"]) == "pytest -q tests")
    }

    @Test("collapses whitespace and truncates long commands")
    func truncates() {
        let long = String(repeating: "a", count: 200)
        let summary = CommandSummary.summarize(["/bin/sh", "-c", "echo   \n" + long], maxLength: 20)
        #expect(summary.count == 20)
        #expect(summary.hasPrefix("echo a"))
        #expect(summary.hasSuffix("…"))
    }

    @Test("handles an empty argument list")
    func empty() {
        #expect(CommandSummary.summarize([]) == "")
    }
}
