import Testing
@testable import ThumbsOutCore

@Suite("Lid lock")
struct LidLockStateTests {
    func decide(
        _ state: LidLockState, closed: Bool = true, enabled: Bool = true,
        disabledByUs: Bool = true, externalDisplay: Bool = false
    ) -> LidLockDecision {
        state.decide(
            isEnabled: enabled, isLidClosed: closed,
            lidSleepDisabledByUs: disabledByUs, hasExternalDisplay: externalDisplay
        )
    }

    @Test("locks when the lid closes while thumbs-out keeps the Mac awake")
    func locksOnClose() {
        #expect(decide(.open) == .lock)
    }

    @Test("does nothing when the setting is off")
    func settingOff() {
        #expect(decide(.open, enabled: false) == .dontLock(.turnedOff))
    }

    @Test("not while the lid is open")
    func lidOpen() {
        #expect(decide(.open, closed: false) == .dontLock(.lidOpen))
        #expect(decide(.closedHandled, closed: false) == .dontLock(.lidOpen))
    }

    @Test("not when thumbs-out isn't keeping the closed Mac awake: it sleeps, and its own lock-screen setting applies")
    func notKeptAwake() {
        #expect(decide(.open, disabledByUs: false) == .dontLock(.notKeptAwake))
    }

    @Test("not with an external display: closing the lid there means working on the big screen")
    func externalDisplay() {
        #expect(decide(.open, externalDisplay: true) == .dontLock(.externalDisplay))
    }

    @Test("the external display is the reason given when docked in clamshell mode with thumbs-out idle")
    func externalDisplayComesBeforeNotKeptAwake() {
        #expect(decide(.open, disabledByUs: false, externalDisplay: true) == .dontLock(.externalDisplay))
    }

    @Test("the setting being off is the reason given, even for a closure already handled")
    func settingOffComesFirst() {
        #expect(decide(.closedHandled, enabled: false) == .dontLock(.turnedOff))
    }

    @Test("locks later in the same closure once the conditions hold, e.g. the monitor is unplugged")
    func locksWhenConditionsLaterHold() {
        let afterClosingOnMonitor = LidLockState.open.next(isLidClosed: true, locked: false)
        #expect(afterClosingOnMonitor == .closed)
        #expect(decide(afterClosingOnMonitor) == .lock)
    }

    @Test("locks once per closure")
    func oncePerClosure() {
        let afterLocking = LidLockState.open.next(isLidClosed: true, locked: true)
        #expect(afterLocking == .closedHandled)
        #expect(decide(afterLocking) == .dontLock(.alreadyHandled))
    }

    @Test("retries on the next check when locking failed")
    func retriesAfterFailure() {
        let afterFailure = LidLockState.open.next(isLidClosed: true, locked: false)
        #expect(decide(afterFailure) == .lock)
    }

    @Test("opening the lid starts over, so the next closure locks again")
    func openingResets() {
        let reopened = LidLockState.closedHandled.next(isLidClosed: false, locked: false)
        #expect(reopened == .open)
        #expect(decide(reopened) == .lock)
    }

    @Test("every closure locks when each opening in between is seen, however quick")
    func everyClosureLocks() {
        var state = LidLockState.open
        var locks = 0
        for closed in [true, false, true, false, true] {
            let locked = decide(state, closed: closed) == .lock
            if locked { locks += 1 }
            state = state.next(isLidClosed: closed, locked: locked)
        }
        #expect(locks == 3)
    }

    @Test("a lid already closed when thumbs-out starts is left alone until it opens")
    func alreadyClosedAtLaunch() {
        #expect(decide(.unknown) == .dontLock(.alreadyHandled))
        #expect(LidLockState.unknown.next(isLidClosed: true, locked: false) == .closedHandled)
        #expect(LidLockState.unknown.next(isLidClosed: false, locked: false) == .open)
    }

    @Test("knows the lid's position at the last reading, so only changes need logging")
    func lidPosition() {
        #expect(LidLockState.unknown.isLidClosed == nil)
        #expect(LidLockState.open.isLidClosed == false)
        #expect(LidLockState.closed.isLidClosed == true)
        #expect(LidLockState.closedHandled.isLidClosed == true)
    }

    func logLine(_ state: LidLockState, closed: Bool = true, disabledByUs: Bool = true, externalDisplay: Bool = false) -> String? {
        state.logLine(
            isLidClosed: closed,
            decision: decide(state, closed: closed, disabledByUs: disabledByUs, externalDisplay: externalDisplay)
        )
    }

    @Test("logs each lid change with what it decided")
    func logsChanges() {
        #expect(logLine(.unknown, closed: false) == "Lid open")
        #expect(logLine(.open) == "Lid closed: locking the screen")
        #expect(logLine(.closedHandled, closed: false) == "Lid opened")
        #expect(logLine(.open, disabledByUs: false) == "Lid closed, not locking: thumbs-out isn't keeping the closed Mac awake")
        #expect(logLine(.open, externalDisplay: true) == "Lid closed, not locking: another display is connected")
        #expect(logLine(.unknown) == "Lid closed, not locking: it was already closed when thumbs-out started")
    }

    @Test("logs a lock later in the same closure")
    func logsLaterLock() {
        #expect(logLine(.closed) == "Lid still closed: locking the screen")
    }

    @Test("logs nothing for a reading like the last one, so a closed lid doesn't log every tick")
    func quietWhenUnchanged() {
        #expect(logLine(.closedHandled) == nil)
        #expect(logLine(.closed, externalDisplay: true) == nil)
        #expect(logLine(.open, closed: false) == nil)
    }
}

@Suite("Lid lock log cycle")
struct LidLockCycleTests {
    /// Runs lid and screen changes through the cycle and returns the ones it would log.
    func logged(_ events: [Event]) -> [Event] {
        var cycle = LidLockCycle.idle
        var logged: [Event] = []
        for event in events {
            switch event {
            case .lid(let isClosed):
                cycle = cycle.lidMoved(isClosed: isClosed)
            case .screen(let isLocked):
                let change = cycle.screenChanged(isLocked: isLocked)
                cycle = change.next
                if change.logs { logged.append(event) }
            }
        }
        return logged
    }

    enum Event: Equatable {
        case lid(isClosed: Bool)
        case screen(isLocked: Bool)
    }

    @Test("logs the lock while the lid is closed and the unlock that ends it")
    func lidClosure() {
        let events: [Event] = [.lid(isClosed: true), .screen(isLocked: true), .lid(isClosed: false), .screen(isLocked: false)]
        #expect(logged(events) == [.screen(isLocked: true), .screen(isLocked: false)])
    }

    @Test("leaves out locking by hand or the screen saver with the lid open: a public report shouldn't show the user's day")
    func otherLocks() {
        #expect(logged([.screen(isLocked: true), .screen(isLocked: false)]).isEmpty)
    }

    @Test("leaves out a lock after a closure that didn't lock, like one on an external display")
    func closureWithoutLock() {
        let events: [Event] = [.lid(isClosed: true), .lid(isClosed: false), .screen(isLocked: true), .screen(isLocked: false)]
        #expect(logged(events).isEmpty)
    }

    @Test("closing again before unlocking still logs the one unlock")
    func closingAgainWhileLocked() {
        let events: [Event] = [
            .lid(isClosed: true), .screen(isLocked: true), .lid(isClosed: false),
            .lid(isClosed: true), .lid(isClosed: false), .screen(isLocked: false),
        ]
        #expect(logged(events) == [.screen(isLocked: true), .screen(isLocked: false)])
    }

    @Test("leaves out an unlock of a screen locked before the lid closed")
    func lockedBeforeClosing() {
        let events: [Event] = [.screen(isLocked: true), .lid(isClosed: true), .lid(isClosed: false), .screen(isLocked: false)]
        #expect(logged(events).isEmpty)
    }
}
