import Foundation
import os

/// Locks the screen the way Control-Command-Q does. Apps and agents keep running behind the lock screen.
///
/// macOS has no public call for this. `SACLockScreenImmediate` in the private login framework is the
/// one lock-screen utilities use; it's looked up at run time, so if a future macOS drops it the setting
/// is simply unavailable instead of crashing the app.
enum ScreenLocker {
    private typealias LockFunction = @convention(c) () -> Int32

    private static let log = Logger(subsystem: "com.mj0lken.thumbs-out", category: "lock")
    private static let frameworkPath = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"

    private static let lockFunction: LockFunction? = {
        guard let handle = dlopen(frameworkPath, RTLD_LAZY),
              let symbol = dlsym(handle, "SACLockScreenImmediate")
        else { return nil }
        return unsafeBitCast(symbol, to: LockFunction.self)
    }()

    static var isAvailable: Bool { lockFunction != nil }

    /// Returns whether the screen locked.
    static func lock() -> Bool {
        guard let lockFunction else {
            log.error("Can't lock the screen: SACLockScreenImmediate isn't available on this macOS")
            return false
        }
        let status = lockFunction()
        guard status == 0 else {
            log.error("Locking the screen failed with status \(status)")
            return false
        }
        log.notice("Locked the screen: the lid is closed while thumbs-out keeps the Mac awake")
        return true
    }
}
