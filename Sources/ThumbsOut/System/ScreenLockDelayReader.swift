import Foundation
import os
import ThumbsOutCore

/// Reads macOS's password delay. Read only: changing it needs the user's password, so thumbs-out
/// only points them at Lock Screen settings.
enum ScreenLockDelayReader {
    private static let log = Logger(subsystem: "com.mj0lken.thumbs-out", category: "lock")

    /// Nil when sysadminctl fails or prints something unrecognised.
    static func read() async -> ScreenLockDelay? {
        // Needs no admin rights; the answer goes to stderr.
        let result = await CommandRunner.run("/usr/sbin/sysadminctl", ["-screenLock", "status"])
        guard result.succeeded, let delay = ScreenLockDelay(sysadminctlOutput: result.errorOutput) else {
            log.error("Couldn't read the password delay (status \(result.status)): \(result.errorOutput, privacy: .public)")
            return nil
        }
        return delay
    }
}
