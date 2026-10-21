import Foundation

/// A command seen starting between two snapshots.
public struct SpawnedCommand: Sendable, Equatable {
    public let command: DetectedCommand
    /// The process that started it.
    public let parentPID: Int32
    public let date: Date

    public init(command: DetectedCommand, parentPID: Int32, date: Date) {
        self.command = command
        self.parentPID = parentPID
        self.date = date
    }
}

/// Decides which short commands count. Watching every new process catches each run of a command
/// that something repeats on a timer (an editor extension polling, a status line refreshing), which a
/// snapshot would only catch now and then. So a command its process ran less than `repeatWindow`
/// before doesn't count again: with the window longer than the grace period, a timer can't keep an
/// idle agent awake. Immutable: `filtering` returns an updated copy.
public struct ShortCommandFilter: Sendable, Equatable {
    private struct Key: Hashable, Sendable {
        let parentPID: Int32
        let agent: Agent
        let summary: String
    }

    /// When each command last ran, counted or not.
    private var lastRun: [Key: Date] = [:]

    public init() {}

    /// - Parameter maxAge: older commands are dropped, like those seen just before the Mac slept.
    public func filtering(
        _ spawned: [SpawnedCommand], now: Date, repeatWindow: TimeInterval, maxAge: TimeInterval
    ) -> (filter: ShortCommandFilter, commands: [DetectedCommand]) {
        var next = self
        var counted: [DetectedCommand] = []
        for item in spawned.sorted(by: { $0.date < $1.date }) {
            let key = Key(parentPID: item.parentPID, agent: item.command.agent, summary: item.command.summary)
            let isRepeat = next.lastRun[key].map { item.date.timeIntervalSince($0) < repeatWindow } ?? false
            if !isRepeat, now.timeIntervalSince(item.date) <= maxAge { counted.append(item.command) }
            next.lastRun[key] = item.date
        }
        next.lastRun = next.lastRun.filter { now.timeIntervalSince($0.value) < repeatWindow }
        return (next, counted)
    }
}
