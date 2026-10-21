/// Locks the screen once per lid closure, as soon as thumbs-out is what keeps the closed Mac awake.
///
/// Not only at the instant the lid shuts: closing it on an external monitor and unplugging the monitor
/// later should still lock. And never when the Mac sleeps anyway (macOS asks for the password on
/// wake) or while another display is connected (closing the lid there means working on that screen).
public enum LidLockState: Sendable, Equatable {
    /// Before the first reading.
    case unknown
    case open
    /// Closed and not locked yet.
    case closed
    /// Closed and locked, or already closed when thumbs-out started: nothing to do until it opens.
    case closedHandled

    public func shouldLock(
        isEnabled: Bool,
        isLidClosed: Bool,
        lidSleepDisabledByUs: Bool,
        hasExternalDisplay: Bool
    ) -> Bool {
        guard isLidClosed, self == .open || self == .closed else { return false }
        return isEnabled && lidSleepDisabledByUs && !hasExternalDisplay
    }

    /// The state after a reading. `locked` is whether the screen was locked successfully just now;
    /// after a failed attempt the closure stays unhandled, so the next reading tries again.
    public func next(isLidClosed: Bool, locked: Bool) -> LidLockState {
        guard isLidClosed else { return .open }
        return self == .unknown || self == .closedHandled || locked ? .closedHandled : .closed
    }
}
