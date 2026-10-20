import Foundation
import Testing
@testable import ThumbsOutCore

@Suite("Awake stats")
struct AwakeStatsTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return calendar
    }()

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute, second: second))!
    }

    /// By default the uptime clock runs with the wall clock (the Mac never slept).
    func record(_ stats: AwakeStats, _ awake: Bool, _ at: Date, uptime: TimeInterval? = nil) -> AwakeStats {
        stats.recording(
            keepsAwake: awake, at: at, uptime: uptime ?? at.timeIntervalSince1970,
            maxCountedGap: 90, calendar: calendar
        )
    }

    @Test("counts time between ticks while keeping the Mac awake")
    func countsAwakeTime() {
        var stats = AwakeStats()
        stats = record(stats, true, date(20, 10, 0, 0))
        stats = record(stats, true, date(20, 10, 0, 5))
        stats = record(stats, true, date(20, 10, 0, 10))
        stats = record(stats, false, date(20, 10, 0, 15))
        stats = record(stats, false, date(20, 10, 0, 20))
        #expect(stats.totalSeconds == 15)
        #expect(stats.seconds(on: date(20, 12), calendar: calendar) == 15)
    }

    @Test("does not count gaps longer than the cap, e.g. while the Mac slept anyway")
    func capsGaps() {
        var stats = record(AwakeStats(), true, date(20, 10))
        stats = record(stats, true, date(20, 11))
        #expect(stats.totalSeconds == 0)
    }

    @Test("does not count time the Mac spent asleep, even within the gap cap")
    func excludesSleepByUptime() {
        var stats = record(AwakeStats(), true, date(20, 10, 0, 0), uptime: 1_000)
        // 60 s passed on the wall clock, but the uptime clock (paused during sleep) moved only 5 s.
        stats = record(stats, true, date(20, 10, 1, 0), uptime: 1_005)
        #expect(stats.totalSeconds == 5)
    }

    @Test("decodes stats saved by an older version with missing fields")
    func decodesOlderFormat() throws {
        let stats = try JSONDecoder().decode(AwakeStats.self, from: Data(#"{"totalSeconds": 120}"#.utf8))
        #expect(stats.totalSeconds == 120)
        #expect(stats.dailySeconds.isEmpty)
        #expect(stats.longestStretch == 0)
    }

    @Test("splits a stretch across midnight into both days")
    func splitsAcrossMidnight() {
        var stats = record(AwakeStats(), true, date(20, 23, 59, 30))
        stats = record(stats, true, date(21, 0, 0, 30))
        #expect(stats.seconds(on: date(20, 12), calendar: calendar) == 30)
        #expect(stats.seconds(on: date(21, 12), calendar: calendar) == 30)
        #expect(stats.totalSeconds == 60)
    }

    @Test("tracks the current and longest awake stretch")
    func sessions() {
        var stats = record(AwakeStats(), true, date(20, 10, 0, 0))
        stats = record(stats, true, date(20, 10, 1, 0))
        #expect(stats.currentStretch(at: date(20, 10, 1, 30)) == 90)
        stats = record(stats, false, date(20, 10, 1, 10))
        #expect(stats.currentStretch(at: date(20, 10, 2)) == nil)
        #expect(stats.longestStretch == 70)
    }

    @Test("the longest stretch includes the one still in progress")
    func longestIncludesCurrent() {
        var stats = record(AwakeStats(), true, date(20, 10, 0, 0))
        stats = record(stats, true, date(20, 10, 1, 0))
        #expect(stats.longestStretch(at: date(20, 10, 1, 30)) == 90)
    }

    @Test("sums the last seven days, including today")
    func lastWeek() {
        var stats = AwakeStats()
        for day in [12, 14, 20] {
            stats = record(stats, true, date(day, 9, 0, 0))
            stats = record(stats, true, date(day, 9, 1, 0))
            stats = record(stats, false, date(day, 9, 1, 1))
        }
        #expect(stats.seconds(inLast: 7, endingOn: date(20, 12), calendar: calendar) == 122)
    }

    @Test("forgets days older than the retention window")
    func prunes() {
        var stats = record(AwakeStats(), true, date(1, 9, 0, 0))
        stats = record(stats, true, date(1, 9, 1, 0))
        stats = record(stats, false, date(1, 9, 1, 1))
        stats = record(stats, false, date(31, 9))
        #expect(stats.dailySeconds.count == 0)
        #expect(stats.totalSeconds == 61)
    }

    @Test("survives a JSON round trip")
    func codable() throws {
        let stats = record(record(AwakeStats(), true, date(20, 10)), true, date(20, 10, 0, 30))
        let decoded = try JSONDecoder().decode(AwakeStats.self, from: JSONEncoder().encode(stats))
        #expect(decoded == stats)
    }

    @Test("formats durations for the menu", arguments: [
        (0.0, "0m"), (59.0, "<1m"), (60.0, "1m"), (3_540.0, "59m"), (3_600.0, "1h"), (5_460.0, "1h 31m"),
        (90_000.0, "25h"),
    ])
    func formatting(seconds: TimeInterval, expected: String) {
        #expect(AwakeStats.format(seconds) == expected)
    }
}
