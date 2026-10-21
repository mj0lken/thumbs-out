import Foundation
import Testing
@testable import ThumbsOutCore

/// Folder listings built from file paths relative to the home folder, like a tiny file system.
struct FakeHome {
    static let path = "/Users/me"

    var files: [String: Date]
    var folderDates: [String: Date] = [:]

    func list(_ path: String) -> [FileEntry] {
        let prefix = path + "/"
        var entries: [String: FileEntry] = [:]
        for (file, modified) in files {
            let absolute = "\(Self.path)/\(file)"
            guard absolute.hasPrefix(prefix) else { continue }
            let parts = absolute.dropFirst(prefix.count).split(separator: "/", maxSplits: 1)
            let name = String(parts[0])
            if parts.count == 1 {
                entries[name] = FileEntry(name: name, isDirectory: false, modified: modified)
            } else if entries[name] == nil {
                let folderDate = folderDates[String(absolute.prefix(prefix.count + name.count))] ?? .distantPast
                entries[name] = FileEntry(name: name, isDirectory: true, modified: folderDate)
            }
        }
        return entries.values.sorted { $0.name < $1.name }
    }
}

@Suite("Transcript patterns")
struct TranscriptPatternTests {
    @Test("`*` matches within one path component", arguments: [
        ("*.jsonl", "abc.jsonl", true), ("*.jsonl", "abc.json", false), ("*.jsonl", "agent-a.meta.json", false),
        ("rollout-*.jsonl", "rollout-2026-10-21.jsonl", true), ("rollout-*.jsonl", "x-rollout-1.jsonl", false),
        ("session-*.json", "session-2026-02-21T11-01-c386ad79.json", true), ("subagents", "subagents", true),
        ("subagents", "subagent", false), ("*", "-Users-me-Projects-app", true), ("a*a", "a", false),
    ])
    func globs(glob: String, name: String, expected: Bool) {
        #expect(TranscriptPattern.matches(name, glob: glob) == expected)
    }

    @Test("splits into folder components and a file pattern")
    func components() {
        let pattern: TranscriptPattern = ".codex/sessions/*/*/*/rollout-*.jsonl"
        #expect(pattern.folders == [".codex", "sessions", "*", "*", "*"])
        #expect(pattern.file == "rollout-*.jsonl")
    }
}

@Suite("Transcript activity")
struct TranscriptScannerTests {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let claudeProject = ".claude/projects/-Users-me-Projects-app"

    func scan(
        _ scanner: TranscriptScanner, _ home: FakeHome, at now: Date, watching agents: Set<Agent> = [.claudeCode]
    ) -> (scanner: TranscriptScanner, writers: Set<Agent>, listed: [String]) {
        var listed: [String] = []
        let result = scanner.scanning(agents, home: FakeHome.path, now: now) { path in
            listed.append(path)
            return home.list(path)
        }
        return (result.scanner, result.writers, listed)
    }

    @Test("a transcript written since the last look means the agent is working")
    func newWrite() {
        var home = FakeHome(files: ["\(claudeProject)/s1.jsonl": start.addingTimeInterval(-600)])
        let first = scan(TranscriptScanner(), home, at: start)
        #expect(first.writers.isEmpty)

        home.files["\(claudeProject)/s1.jsonl"] = start.addingTimeInterval(3)
        #expect(scan(first.scanner, home, at: start.addingTimeInterval(5)).writers == [.claudeCode])
    }

    @Test("an unchanged transcript doesn't count twice")
    func unchanged() {
        let home = FakeHome(files: ["\(claudeProject)/s1.jsonl": start.addingTimeInterval(-2)])
        let first = scan(TranscriptScanner(), home, at: start)
        #expect(first.writers == [.claudeCode]) // On launch, writes from the last minute count.
        #expect(scan(first.scanner, home, at: start.addingTimeInterval(5)).writers.isEmpty)
    }

    @Test("between full scans only folders with recent transcripts are listed")
    func listsOnlyHotFolders() {
        let home = FakeHome(files: [
            "\(claudeProject)/s1.jsonl": start.addingTimeInterval(-600),
            ".claude/projects/-Users-me-old/s2.jsonl": start.addingTimeInterval(-86_400 * 3),
        ])
        let first = scan(TranscriptScanner(), home, at: start)
        let second = scan(first.scanner, home, at: start.addingTimeInterval(5))
        #expect(second.listed == ["\(FakeHome.path)/\(claudeProject)"])
    }

    @Test("a session resumed after a long pause is noticed at the next full scan")
    func resumedSession() {
        let old = ".claude/projects/-Users-me-old/s2.jsonl"
        var home = FakeHome(files: [old: start.addingTimeInterval(-86_400 * 3)])
        let first = scan(TranscriptScanner(), home, at: start)

        home.files[old] = start.addingTimeInterval(4)
        let hot = scan(first.scanner, home, at: start.addingTimeInterval(5))
        #expect(hot.writers.isEmpty)
        let full = scan(hot.scanner, home, at: start.addingTimeInterval(TranscriptScanner.fullScanInterval + 1))
        #expect(full.writers == [.claudeCode])
        #expect(scan(full.scanner, home, at: start.addingTimeInterval(TranscriptScanner.fullScanInterval + 6))
            .listed == ["\(FakeHome.path)/.claude/projects/-Users-me-old"])
    }

    @Test("a folder stops being listed every tick an hour after its last write")
    func coolsDown() {
        let home = FakeHome(files: ["\(claudeProject)/s1.jsonl": start])
        let later = start.addingTimeInterval(TranscriptScanner.hotWindow + 1)
        let full = scan(scan(TranscriptScanner(), home, at: start).scanner, home, at: later)
        #expect(scan(full.scanner, home, at: later.addingTimeInterval(5)).listed.isEmpty)
    }

    @Test("a transcript dated in the future doesn't keep counting, and doesn't hide real writes")
    func futureDated() {
        var home = FakeHome(files: [
            "\(claudeProject)/s0.jsonl": start.addingTimeInterval(-600),
            "\(claudeProject)/s1.jsonl": start.addingTimeInterval(86_400),
        ])
        let first = scan(TranscriptScanner(), home, at: start)
        #expect(first.writers.isEmpty)
        let second = scan(first.scanner, home, at: start.addingTimeInterval(5))
        #expect(second.writers.isEmpty)

        home.files["\(claudeProject)/s2.jsonl"] = start.addingTimeInterval(8)
        #expect(scan(second.scanner, home, at: start.addingTimeInterval(10)).writers == [.claudeCode])
    }

    @Test("a write made while the folder was being listed counts once")
    func writeDuringListing() {
        let home = FakeHome(files: ["\(claudeProject)/s1.jsonl": start.addingTimeInterval(0.5)])
        let first = scan(TranscriptScanner(), home, at: start)
        #expect(first.writers == [.claudeCode])
        #expect(scan(first.scanner, home, at: start.addingTimeInterval(5)).writers.isEmpty)
    }

    @Test("writes from just before the Mac slept don't count when it wakes")
    func staleAfterSleep() {
        var home = FakeHome(files: ["\(claudeProject)/s1.jsonl": start.addingTimeInterval(-60)])
        let first = scan(TranscriptScanner(), home, at: start)
        home.files["\(claudeProject)/s1.jsonl"] = start.addingTimeInterval(2)
        #expect(scan(first.scanner, home, at: start.addingTimeInterval(1_800)).writers.isEmpty)
    }

    @Test("each agent's transcripts are found where it writes them", arguments: [
        (".claude/projects/-Users-me-Projects-app/0b1c.jsonl", Agent.claudeCode),
        (".claude/projects/-Users-me-Projects-app/0b1c/subagents/agent-a72e.jsonl", Agent.claudeCode),
        (".codex/sessions/2026/10/21/rollout-2026-10-21T07-48-01-01a0d7e3.jsonl", Agent.chatGPT),
        (".gemini/tmp/backend/chats/session-2026-02-21T17-13-15d25bf7.json", Agent.antigravity),
    ])
    func catalogLocations(file: String, agent: Agent) {
        let home = FakeHome(files: [file: start.addingTimeInterval(-1)])
        #expect(scan(TranscriptScanner(), home, at: start, watching: Set(Agent.allCases)).writers == [agent])
    }

    @Test("other files next to transcripts don't count", arguments: [
        ".claude/projects/-Users-me-Projects-app/memory/MEMORY.md",
        ".claude/projects/-Users-me-Projects-app/0b1c/tool-results/b4h7.txt",
        ".claude/projects/-Users-me-Projects-app/0b1c/subagents/agent-a72e.meta.json",
        ".claude/projects/-Users-me-Projects-app/0b1c/custom-title.json",
        ".codex/session_index.jsonl",
        ".gemini/tmp/backend/logs.json",
    ])
    func otherFiles(file: String) {
        let home = FakeHome(files: [file: start.addingTimeInterval(-1)])
        #expect(scan(TranscriptScanner(), home, at: start, watching: Set(Agent.allCases)).writers.isEmpty)
    }

    @Test("agents that aren't watched aren't looked for")
    func unwatched() {
        let home = FakeHome(files: ["\(claudeProject)/s1.jsonl": start.addingTimeInterval(-1)])
        let result = scan(TranscriptScanner(), home, at: start, watching: [.chatGPT])
        #expect(result.writers.isEmpty)
        #expect(!result.listed.contains { $0.contains("/.claude/") })
    }

    @Test("agents without known transcripts list nothing")
    func noTranscripts() {
        let home = FakeHome(files: ["\(claudeProject)/s1.jsonl": start.addingTimeInterval(-1)])
        #expect(scan(TranscriptScanner(), home, at: start, watching: [.cursor, .aider]).listed.isEmpty)
    }
}
