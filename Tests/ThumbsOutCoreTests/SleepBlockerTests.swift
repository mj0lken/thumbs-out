import Testing
@testable import ThumbsOutCore

@Suite("Sleep blockers")
struct SleepBlockerTests {
    private func raw(
        _ pid: Int32, _ process: String?, _ type: String, _ name: String = "reason", onBehalfOf: Int32? = nil
    ) -> RawAssertion {
        RawAssertion(pid: pid, processName: process, type: type, name: name, onBehalfOfPID: onBehalfOf)
    }

    @Test("keeps only assertions that stop the Mac from sleeping")
    func filtersTypes() {
        let blockers = SleepBlockers.from([
            raw(1, "Claude", "NoIdleSleepAssertion", "Electron"),
            raw(2, "WindowServer", "UserIsActive"),
            raw(3, "Backup", "BackgroundTask"),
            raw(4, "caffeinate", "PreventUserIdleSystemSleep"),
        ], nameForPID: { _ in nil })
        #expect(blockers.map(\.processName) == ["caffeinate", "Claude"])
    }

    @Test("hides powerd's own bookkeeping assertions")
    func hidesPowerd() {
        let blockers = SleepBlockers.from(
            [raw(345, "powerd", "PreventUserIdleSystemSleep", "Powerd - Prevent sleep while display is on")],
            nameForPID: { _ in nil }
        )
        #expect(blockers.isEmpty)
    }

    @Test("credits the app an assertion was taken on behalf of")
    func onBehalfOf() {
        let blockers = SleepBlockers.from(
            [raw(427, "coreaudiod", "PreventUserIdleSystemSleep", "audio", onBehalfOf: 900)],
            nameForPID: { $0 == 900 ? "Music" : nil }
        )
        #expect(blockers.map(\.processName) == ["Music"])
    }

    @Test("groups several assertions from one app into one row")
    func groupsByApp() {
        let blockers = SleepBlockers.from([
            raw(70, "Amphetamine", "PreventUserIdleSystemSleep", "Amphetamine (System)"),
            raw(70, "Amphetamine", "PreventUserIdleDisplaySleep", "Amphetamine (Display)"),
        ], nameForPID: { _ in nil })
        #expect(blockers == [
            SleepBlocker(processName: "Amphetamine", reasons: ["Amphetamine (System)", "Amphetamine (Display)"],
                         keepsDisplayOn: true),
        ])
    }

    @Test("prefers the resolved app name and falls back to the pid")
    func naming() {
        let blockers = SleepBlockers.from([
            raw(10, "Claude Helper", "PreventUserIdleSystemSleep"),
            raw(11, nil, "PreventUserIdleSystemSleep"),
        ], nameForPID: { $0 == 10 ? "Claude" : nil })
        #expect(blockers.map(\.processName) == ["Claude", "pid 11"])
    }

    @Test("leaves out the given processes, e.g. thumbs-out itself")
    func excludesPIDs() {
        let blockers = SleepBlockers.from(
            [raw(1, "ThumbsOut", "PreventUserIdleSystemSleep"), raw(2, "caffeinate", "PreventUserIdleSystemSleep")],
            excludingPIDs: [1], nameForPID: { _ in nil }
        )
        #expect(blockers.map(\.processName) == ["caffeinate"])
    }

    @Test("turns raw assertion names into readable reasons", arguments: [
        ("com.apple.audio.BuiltInSpeakerDevice.context.preventuseridlesleep", "Godot", "Playing audio"),
        ("Electron", "Claude", "Keeping the app active"),
        ("Godot: exporting", "Godot", "exporting"),
        ("Godot", "Godot", nil),
        ("", "Godot", nil),
        ("Amphetamine (Single-Use - System)", "Amphetamine", "Amphetamine (Single-Use - System)"),
    ])
    func friendlyReasons(reason: String, process: String, expected: String?) {
        let blocker = SleepBlocker(processName: process, reasons: [reason], keepsDisplayOn: false)
        #expect(blocker.summary == expected)
    }

    @Test("derives an app's name from any executable inside its bundle", arguments: [
        ("/Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper", "Claude"),
        ("/Applications/Amphetamine.app/Contents/MacOS/Amphetamine", "Amphetamine"),
        ("/usr/bin/caffeinate", "caffeinate"),
        ("", ""),
    ])
    func appNames(path: String, expected: String) {
        #expect(ProcessDisplayName.from(path: path) == expected)
    }
}

@Suite("Lid-closed behaviour")
struct LidClosedBehaviorTests {
    @Test("sleep disabled system-wide wins")
    func sleepDisabled() {
        let behavior = LidClosedBehavior.evaluate(clamshellCausesSleep: true, sleepDisabled: true, disabledByUs: true)
        #expect(behavior == .staysAwakeSleepDisabled(byThumbsOut: true))
    }

    @Test("external display on power keeps the Mac awake")
    func externalDisplay() {
        let behavior = LidClosedBehavior.evaluate(clamshellCausesSleep: false, sleepDisabled: false, disabledByUs: false)
        #expect(behavior == .staysAwakeExternalDisplay)
    }

    @Test("otherwise closing the lid sleeps the Mac")
    func sleeps() {
        let behavior = LidClosedBehavior.evaluate(clamshellCausesSleep: true, sleepDisabled: false, disabledByUs: false)
        #expect(behavior == .sleeps)
    }
}
