import Testing
@testable import ThumbsOutCore

@Suite("Screen lock delay")
struct ScreenLockDelayTests {
    /// sysadminctl logs through NSLog, so every line carries a timestamp and the process ID.
    func output(_ message: String) -> String {
        "2026-10-27 10:16:31.090 sysadminctl[66617:34506411] \(message)\n"
    }

    @Test("reads Immediately")
    func immediate() {
        #expect(ScreenLockDelay(sysadminctlOutput: output("screenLock delay is immediate")) == .immediate)
    }

    @Test("reads a delay in seconds")
    func seconds() {
        #expect(ScreenLockDelay(sysadminctlOutput: output("screenLock delay is 300 seconds")) == .seconds(300))
    }

    @Test("reads Never as off")
    func off() {
        #expect(ScreenLockDelay(sysadminctlOutput: output("screenLock is off")) == .off)
    }

    @Test("a zero-second delay is immediate")
    func zeroSeconds() {
        #expect(ScreenLockDelay(sysadminctlOutput: output("screenLock delay is 0 seconds")) == .immediate)
    }

    @Test("finds the answer among other lines")
    func otherLines() {
        let text = output("Some warning about the keychain") + output("screenLock delay is 5 seconds")
        #expect(ScreenLockDelay(sysadminctlOutput: text) == .seconds(5))
    }

    @Test(
        "anything else is unreadable",
        arguments: [
            "",
            "sysadminctl: command not found",
            "2026-10-27 10:16:31.090 sysadminctl[1:2] Unknown state for screenLock (42)",
            "2026-10-27 10:16:31.090 sysadminctl[1:2] screenLock delay is many seconds",
            "2026-10-27 10:16:31.090 sysadminctl[1:2] screenLock delay is -5 seconds",
            "2026-10-27 10:16:31.090 sysadminctl[1:2] screenLock delay is 99999999999999999999 seconds",
        ]
    )
    func unreadable(text: String) {
        #expect(ScreenLockDelay(sysadminctlOutput: text) == nil)
    }

    @Test("only Immediately counts as immediate")
    func isImmediate() {
        #expect(ScreenLockDelay.immediate.isImmediate)
        #expect(!ScreenLockDelay.seconds(5).isImmediate)
        #expect(!ScreenLockDelay.off.isImmediate)
    }

    @Test(
        "labels read like System Settings",
        arguments: [
            (ScreenLockDelay.immediate, "immediately"),
            (.seconds(1), "1 second"),
            (.seconds(5), "5 seconds"),
            (.seconds(90), "90 seconds"),
            (.seconds(60), "1 minute"),
            (.seconds(300), "5 minutes"),
            (.seconds(900), "15 minutes"),
            (.seconds(3600), "1 hour"),
            (.seconds(28_800), "8 hours"),
            (.off, "off"),
        ]
    )
    func label(delay: ScreenLockDelay, expected: String) {
        #expect(delay.label == expected)
    }
}
