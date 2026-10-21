import Foundation
import Testing
@testable import ThumbsOutCore

@Suite("Short command filter")
struct ShortCommandFilterTests {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let window: TimeInterval = 360
    let maxAge: TimeInterval = 15

    func spawned(_ summary: String, parent: Int32 = 10, pid: Int32 = 11, at seconds: TimeInterval) -> SpawnedCommand {
        SpawnedCommand(
            command: DetectedCommand(agent: .claudeCode, pid: pid, summary: summary),
            parentPID: parent, date: start.addingTimeInterval(seconds)
        )
    }

    /// Runs one tick per batch, each at the time of its last command, and returns what counted per tick.
    func ticks(_ batches: [[SpawnedCommand]]) -> [[String]] {
        var filter = ShortCommandFilter()
        return batches.map { batch in
            let now = batch.last?.date ?? start
            let result = filter.filtering(batch, now: now, repeatWindow: window, maxAge: maxAge)
            filter = result.filter
            return result.commands.map(\.summary)
        }
    }

    @Test("a short command counts")
    func counts() {
        #expect(ticks([[spawned("cat Package.swift", at: 0)]]) == [["cat Package.swift"]])
    }

    @Test("a command a process repeats on a timer counts once")
    func timerCountsOnce() {
        let batches = stride(from: 0.0, through: 3_600, by: 30).map { [spawned("git status --porcelain", at: $0)] }
        let counted = ticks(batches).filter { !$0.isEmpty }
        #expect(counted == [["git status --porcelain"]])
    }

    @Test("once a repeat stops for a whole window, it counts again")
    func countsAgainAfterWindow() {
        let counted = ticks([[spawned("make", at: 0)], [spawned("make", at: 100)], [spawned("make", at: 100 + window + 1)]])
        #expect(counted == [["make"], [], ["make"]])
    }

    @Test("the same command from another process, or another command, still counts")
    func distinctCommands() {
        let counted = ticks([
            [spawned("ls", at: 0)],
            [spawned("ls", parent: 20, at: 5), spawned("cat a.swift", at: 5)],
        ])
        #expect(counted == [["ls"], ["ls", "cat a.swift"]])
    }

    @Test("commands from before the Mac slept don't count after it wakes")
    func staleDropped() {
        let result = ShortCommandFilter().filtering(
            [spawned("ls", at: 0)], now: start.addingTimeInterval(3_600), repeatWindow: window, maxAge: maxAge
        )
        #expect(result.commands.isEmpty)
    }
}
