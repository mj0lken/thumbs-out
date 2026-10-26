/// Whether a reading of the lid locks the screen, or why not.
public enum LidLockDecision: Sendable, Equatable {
    case lock
    case dontLock(Reason)

    public enum Reason: Sendable, Equatable {
        case lidOpen
        case turnedOff
        /// Locked earlier in this closure, or the lid was already closed when thumbs-out started.
        case alreadyHandled
        /// Closing the lid with another display connected means working on that screen.
        case externalDisplay
        /// thumbs-out isn't holding lid sleep off: usually the Mac sleeps, and its own lock-screen setting applies.
        case notKeptAwake

        var explanation: String {
            switch self {
            case .lidOpen: "the lid is open"
            case .turnedOff: "locking on lid close is turned off"
            case .alreadyHandled: "it was already closed when thumbs-out started"
            case .externalDisplay: "another display is connected"
            case .notKeptAwake: "thumbs-out isn't keeping the closed Mac awake"
            }
        }
    }
}

/// Locks the screen once per lid closure, as soon as thumbs-out is what keeps the closed Mac awake.
///
/// Not only at the instant the lid shuts: closing it on an external monitor and unplugging the monitor
/// later should still lock. And never when the Mac sleeps anyway or while another display is connected
/// (closing the lid there means working on that screen).
///
/// Every opening has to be fed in: one missed between two closures leaves the second one unlocked.
public enum LidLockState: Sendable, Equatable {
    /// Before the first reading.
    case unknown
    case open
    /// Closed and not locked yet.
    case closed
    /// Closed and locked, or already closed when thumbs-out started: nothing to do until it opens.
    case closedHandled

    /// The lid's position at the last reading; `nil` before the first.
    public var isLidClosed: Bool? {
        switch self {
        case .unknown: nil
        case .open: false
        case .closed, .closedHandled: true
        }
    }

    public func decide(
        isEnabled: Bool,
        isLidClosed: Bool,
        lidSleepDisabledByUs: Bool,
        hasExternalDisplay: Bool
    ) -> LidLockDecision {
        guard isLidClosed else { return .dontLock(.lidOpen) }
        guard isEnabled else { return .dontLock(.turnedOff) }
        guard self == .open || self == .closed else { return .dontLock(.alreadyHandled) }
        guard !hasExternalDisplay else { return .dontLock(.externalDisplay) }
        guard lidSleepDisabledByUs else { return .dontLock(.notKeptAwake) }
        return .lock
    }

    /// A log line for a reading that changes something: the lid moved, or the screen locks. `nil` for
    /// a reading like the last one, so a closed lid doesn't log every tick.
    public func logLine(isLidClosed: Bool, decision: LidLockDecision) -> String? {
        guard self.isLidClosed != isLidClosed || decision == .lock else { return nil }
        let lid = switch (self.isLidClosed, isLidClosed) {
        case (nil, false): "Lid open"
        case (_, false): "Lid opened"
        case (true?, true): "Lid still closed"
        case (_, true): "Lid closed"
        }
        return switch decision {
        case .lock: "\(lid): locking the screen"
        case .dontLock(.lidOpen): lid
        case .dontLock(let reason): "\(lid), not locking: \(reason.explanation)"
        }
    }

    /// The state after a reading. `locked` is whether the screen was locked successfully just now;
    /// after a failed attempt the closure stays unhandled, so the next reading tries again.
    public func next(isLidClosed: Bool, locked: Bool) -> LidLockState {
        guard isLidClosed else { return .open }
        return self == .unknown || self == .closedHandled || locked ? .closedHandled : .closed
    }
}
