import Foundation

/// How long thumbs-out has kept the Mac awake. Immutable: `recording` returns an updated copy.
public struct AwakeStats: Codable, Sendable, Equatable {
    /// Seconds kept awake per day, keyed `yyyy-MM-dd` in the user's calendar.
    public private(set) var dailySeconds: [String: TimeInterval] = [:]
    public private(set) var totalSeconds: TimeInterval = 0
    public private(set) var longestStretch: TimeInterval = 0
    private var stretchStart: Date?
    private var lastTick: Date?
    private var lastUptime: TimeInterval?
    private var wasAwake = false

    public static let retentionDays = 30

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case dailySeconds, totalSeconds, longestStretch, stretchStart, lastTick, lastUptime, wasAwake
    }

    /// Lenient, so stats saved by an older version (with fewer fields) aren't thrown away.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dailySeconds = try container.decodeIfPresent([String: TimeInterval].self, forKey: .dailySeconds) ?? [:]
        totalSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .totalSeconds) ?? 0
        longestStretch = try container.decodeIfPresent(TimeInterval.self, forKey: .longestStretch) ?? 0
        stretchStart = try container.decodeIfPresent(Date.self, forKey: .stretchStart)
        lastTick = try container.decodeIfPresent(Date.self, forKey: .lastTick)
        lastUptime = try container.decodeIfPresent(TimeInterval.self, forKey: .lastUptime)
        wasAwake = try container.decodeIfPresent(Bool.self, forKey: .wasAwake) ?? false
    }

    /// Records one detection tick. Time between ticks counts only if the Mac was being kept awake
    /// and the gap is short enough that it didn't get suspended in between.
    ///
    /// - Parameter uptime: a clock that pauses while the Mac sleeps (`ProcessInfo.systemUptime`),
    ///   so a short sleep inside an otherwise continuous gap isn't counted as awake time.
    public func recording(
        keepsAwake: Bool,
        at now: Date,
        uptime: TimeInterval,
        maxCountedGap: TimeInterval,
        calendar: Calendar = .current
    ) -> AwakeStats {
        var next = self
        let gap = lastTick.map { now.timeIntervalSince($0) } ?? .infinity
        let isContinuous = gap >= 0 && gap <= maxCountedGap

        if wasAwake, isContinuous, lastTick != nil {
            let awakeDuring = lastUptime.map { min(gap, max(0, uptime - $0)) } ?? gap
            next.add(from: now.addingTimeInterval(-awakeDuring), to: now, calendar: calendar)
        }
        if let stretchStart, let lastTick, !(keepsAwake && isContinuous) {
            let end = wasAwake && isContinuous ? now : lastTick
            next.longestStretch = max(longestStretch, end.timeIntervalSince(stretchStart))
            next.stretchStart = nil
        }
        if keepsAwake, next.stretchStart == nil {
            next.stretchStart = now
        }
        next.lastTick = now
        next.lastUptime = uptime
        next.wasAwake = keepsAwake
        next.prune(before: now, calendar: calendar)
        return next
    }

    /// Length of the stretch in progress, or nil when the Mac isn't being kept awake.
    public func currentStretch(at now: Date) -> TimeInterval? {
        stretchStart.map { max(0, now.timeIntervalSince($0)) }
    }

    /// Longest stretch so far, counting the one in progress.
    public func longestStretch(at now: Date) -> TimeInterval {
        max(longestStretch, currentStretch(at: now) ?? 0)
    }

    public func seconds(on day: Date, calendar: Calendar = .current) -> TimeInterval {
        dailySeconds[Self.key(for: day, calendar: calendar)] ?? 0
    }

    public func seconds(inLast days: Int, endingOn day: Date, calendar: Calendar = .current) -> TimeInterval {
        (0..<days).reduce(0) { sum, offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: day) else { return sum }
            return sum + seconds(on: date, calendar: calendar)
        }
    }

    /// "<1m", "42m", "1h 31m", "25h".
    public static func format(_ seconds: TimeInterval) -> String {
        if seconds <= 0 { return "0m" }
        if seconds < 60 { return "<1m" }
        let minutes = Int(seconds / 60)
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(minutes)m" }
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    // MARK: Private

    private mutating func add(from start: Date, to end: Date, calendar: Calendar) {
        var cursor = start
        while cursor < end {
            // Calendar arithmetic, not +86 400 s, so days with a DST change split correctly.
            let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cursor)) ?? end
            let sliceEnd = min(end, nextDay)
            let slice = sliceEnd.timeIntervalSince(cursor)
            dailySeconds[Self.key(for: cursor, calendar: calendar), default: 0] += slice
            totalSeconds += slice
            cursor = sliceEnd
        }
    }

    private mutating func prune(before now: Date, calendar: Calendar) {
        guard let cutoff = calendar.date(byAdding: .day, value: -(Self.retentionDays - 1), to: now) else { return }
        let oldestKept = Self.key(for: cutoff, calendar: calendar)
        dailySeconds = dailySeconds.filter { $0.key >= oldestKept }
    }

    private static func key(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
