import Testing
@testable import ThumbsOutCore

@Suite("Lid lock")
struct LidLockStateTests {
    func shouldLock(
        _ state: LidLockState, closed: Bool = true, enabled: Bool = true,
        disabledByUs: Bool = true, externalDisplay: Bool = false
    ) -> Bool {
        state.shouldLock(
            isEnabled: enabled, isLidClosed: closed,
            lidSleepDisabledByUs: disabledByUs, hasExternalDisplay: externalDisplay
        )
    }

    @Test("locks when the lid closes while thumbs-out keeps the Mac awake")
    func locksOnClose() {
        #expect(shouldLock(.open))
    }

    @Test("does nothing when the setting is off")
    func settingOff() {
        #expect(!shouldLock(.open, enabled: false))
    }

    @Test("not while the lid is open")
    func lidOpen() {
        #expect(!shouldLock(.open, closed: false))
        #expect(!shouldLock(.closedHandled, closed: false))
    }

    @Test("not when the Mac sleeps on lid close anyway: macOS asks for the password on wake")
    func macSleepsAnyway() {
        #expect(!shouldLock(.open, disabledByUs: false))
    }

    @Test("not with an external display: closing the lid there means working on the big screen")
    func externalDisplay() {
        #expect(!shouldLock(.open, externalDisplay: true))
    }

    @Test("locks later in the same closure once the conditions hold, e.g. the monitor is unplugged")
    func locksWhenConditionsLaterHold() {
        let afterClosingOnMonitor = LidLockState.open.next(isLidClosed: true, locked: false)
        #expect(afterClosingOnMonitor == .closed)
        #expect(shouldLock(afterClosingOnMonitor))
    }

    @Test("locks once per closure")
    func oncePerClosure() {
        let afterLocking = LidLockState.open.next(isLidClosed: true, locked: true)
        #expect(afterLocking == .closedHandled)
        #expect(!shouldLock(afterLocking))
    }

    @Test("retries on the next check when locking failed")
    func retriesAfterFailure() {
        let afterFailure = LidLockState.open.next(isLidClosed: true, locked: false)
        #expect(shouldLock(afterFailure))
    }

    @Test("opening the lid starts over, so the next closure locks again")
    func openingResets() {
        let reopened = LidLockState.closedHandled.next(isLidClosed: false, locked: false)
        #expect(reopened == .open)
        #expect(shouldLock(reopened))
    }

    @Test("a lid already closed when thumbs-out starts is left alone until it opens")
    func alreadyClosedAtLaunch() {
        #expect(!shouldLock(.unknown))
        #expect(LidLockState.unknown.next(isLidClosed: true, locked: false) == .closedHandled)
        #expect(LidLockState.unknown.next(isLidClosed: false, locked: false) == .open)
    }
}
