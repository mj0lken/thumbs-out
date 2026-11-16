import Foundation
import IOKit
import os

/// Reports the lid opening or closing the moment it happens, from the power manager's clamshell message.
///
/// The detection loop only looks every few seconds. On its own it misses a lid that opens and closes
/// again in between, and the second closure goes unlocked.
@MainActor
final class LidWatcher {
    /// `kIOPMMessageClamshellStateChange`, `iokit_family_msg(sub_iokit_powermanagement, 0x100)`:
    /// the macro isn't imported into Swift.
    private nonisolated static let clamshellStateChange: natural_t = 0xE003_4100
    /// `kClamshellStateBit` in the message argument: set while the lid is closed.
    private nonisolated static let closedBit: UInt = 1 << 0

    private static let log = Logger(subsystem: "com.mj0lken.thumbs-out", category: "lock")

    /// Runs on the main queue, which the notification port delivers to.
    private nonisolated static let callback: IOServiceInterestCallback = { refcon, _, messageType, argument in
        guard messageType == clamshellStateChange, let refcon else { return }
        let isClosed = UInt(bitPattern: argument) & closedBit != 0
        let watcherAddress = UInt(bitPattern: refcon)
        MainActor.assumeIsolated {
            guard let pointer = UnsafeRawPointer(bitPattern: watcherAddress) else { return }
            Unmanaged<LidWatcher>.fromOpaque(pointer).takeUnretainedValue().onChange?(isClosed)
        }
    }

    private var port: IONotificationPortRef?
    private var notification: io_object_t = 0
    private var onChange: (@MainActor (Bool) -> Void)?
    /// The reference the notification holds, so a message can never reach a released watcher.
    private var retainedByNotification: Unmanaged<LidWatcher>?

    /// Calls `onChange` with whether the message says the lid is now closed, until `stop()`.
    func start(onChange: @escaping @MainActor (Bool) -> Void) {
        guard port == nil else { return }
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        defer { if rootDomain != 0 { IOObjectRelease(rootDomain) } }
        guard rootDomain != 0, let port = IONotificationPortCreate(kIOMainPortDefault) else {
            Self.log.error("Can't watch the lid: the power manager isn't available")
            return
        }
        IONotificationPortSetDispatchQueue(port, .main)
        let retained = Unmanaged.passRetained(self)
        let result = IOServiceAddInterestNotification(
            port, rootDomain, kIOGeneralInterest, Self.callback, retained.toOpaque(), &notification
        )
        guard result == KERN_SUCCESS else {
            retained.release()
            IONotificationPortDestroy(port)
            Self.log.error("Can't watch the lid: IOServiceAddInterestNotification failed with \(result)")
            return
        }
        self.port = port
        self.onChange = onChange
        retainedByNotification = retained
    }

    func stop() {
        if notification != 0 { IOObjectRelease(notification) }
        notification = 0
        if let port { IONotificationPortDestroy(port) }
        port = nil
        onChange = nil
        retainedByNotification?.release()
        retainedByNotification = nil
    }
}
