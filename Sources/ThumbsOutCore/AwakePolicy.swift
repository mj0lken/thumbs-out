import Foundation

/// A keep-awake session the user started by hand, like Amphetamine's "Start new session".
public enum ManualSession: Sendable, Equatable {
    case indefinite
    case until(Date)

    public func isExpired(at now: Date) -> Bool {
        switch self {
        case .indefinite: false
        case .until(let end): end <= now
        }
    }

    var end: Date? {
        switch self {
        case .indefinite: nil
        case .until(let end): end
        }
    }
}

/// Why the Mac is (or is not) being kept awake.
public enum AwakeDecision: Sendable, Equatable {
    case sleepAllowed
    case agentsActive([Agent])
    case manual(until: Date?)
    case gracePeriod(until: Date)

    public var keepsAwake: Bool { self != .sleepAllowed }
}

public enum AwakePolicy {
    /// - Parameters:
    ///   - activeAgents: agents working right now: running a command, or busy since the last tick.
    ///   - lastActivity: when an agent was last seen working.
    ///   - gracePeriod: how long to stay awake after that, so the agent can keep thinking.
    ///   - isAutoEnabled: whether agent detection is switched on at all.
    public static func decide(
        now: Date,
        activeAgents: [Agent],
        lastActivity: Date?,
        gracePeriod: TimeInterval,
        manual: ManualSession?,
        isAutoEnabled: Bool
    ) -> AwakeDecision {
        if isAutoEnabled, !activeAgents.isEmpty {
            return .agentsActive(activeAgents)
        }
        if let manual, !manual.isExpired(at: now) {
            return .manual(until: manual.end)
        }
        if isAutoEnabled, let lastActivity {
            let graceEnd = lastActivity.addingTimeInterval(gracePeriod)
            if graceEnd > now { return .gracePeriod(until: graceEnd) }
        }
        return .sleepAllowed
    }
}
