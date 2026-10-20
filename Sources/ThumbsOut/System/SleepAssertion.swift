import Foundation
import IOKit.pwr_mgt
import os

/// Holds at most one IOKit power assertion, the same mechanism Amphetamine and `caffeinate` use.
/// Shows up in `pmset -g assertions` under the given reason.
@MainActor
final class SleepAssertion {
    private enum Kind: String {
        case system = "PreventUserIdleSystemSleep"
        case display = "PreventUserIdleDisplaySleep"
    }

    private static let log = Logger(subsystem: "com.mj0lken.thumbs-out", category: "power")

    private var assertionID: IOPMAssertionID = IOPMAssertionID(0)
    private var current: (kind: Kind, reason: String)?

    /// Takes (or swaps to) an assertion. Display assertions also keep the system awake.
    func hold(keepDisplayAwake: Bool, reason: String) {
        let kind: Kind = keepDisplayAwake ? .display : .system
        if let current, current.kind == kind, current.reason == reason { return }

        release()
        var newID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kind.rawValue as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &newID
        )
        guard result == kIOReturnSuccess else {
            Self.log.error("IOPMAssertionCreateWithName failed: \(result, privacy: .public)")
            return
        }
        assertionID = newID
        current = (kind, reason)
    }

    func release() {
        guard current != nil else { return }
        let result = IOPMAssertionRelease(assertionID)
        if result != kIOReturnSuccess {
            Self.log.error("IOPMAssertionRelease failed: \(result, privacy: .public)")
        }
        current = nil
    }
}
