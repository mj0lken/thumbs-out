import Foundation
import Observation
import os
import ThumbsOutCore

/// Owns the system-wide `SleepDisabled` switch while lid-closed mode needs it.
///
/// Safety nets, because the switch outlives the app:
/// - the ownership flag is written and a watchdog started *before* the switch is flipped, so a
///   crash at any point leaves something that turns lid sleep back on,
/// - only a switch this app turned on is ever turned off (remembered across launches),
/// - the watchdog turns it off within seconds once this app process is gone,
/// - on launch, a switch left on by a previous run is turned off,
/// - on quit, it is turned off synchronously.
@MainActor
@Observable
final class LidSleepController {
    private(set) var isSetUp = false
    private(set) var isBusy = false
    private(set) var lastError: String?

    @ObservationIgnored private var watchdog: Process?
    @ObservationIgnored private var wantsSleepDisabled = false
    @ObservationIgnored private var systemSleepDisabled = false
    @ObservationIgnored private var isReconciling = false

    private static let log = Logger(subsystem: "com.mj0lken.thumbs-out", category: "lid")
    private static let ownershipKey = "lidSleepDisabledByThumbsOut"
    private static let adminPrompt =
        "thumbs-out wants to set up lid-closed mode, so it can keep your Mac awake with the lid closed while AI agents work."
    private static let removePrompt = "thumbs-out wants to remove lid-closed mode."

    /// Whether `SleepDisabled` is (or is about to be) on because of us.
    var isDisabledByUs: Bool {
        get { UserDefaults.standard.bool(forKey: Self.ownershipKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.ownershipKey) }
    }

    // MARK: Setup

    /// Checks the sudoers rule and undoes anything a crashed previous run left behind.
    func prepare() async {
        await refreshSetupStatus()
        if isDisabledByUs {
            Self.log.notice("Re-enabling lid sleep left disabled by a previous run")
            _ = await turnLidSleepBackOn()
        }
    }

    func refreshSetupStatus() async {
        // `sudo -n -l <command>` succeeds only if the command is allowed without a password.
        let check = await CommandRunner.run(
            LidSleepHelper.sudoPath,
            ["-n", "-l", LidSleepHelper.pmsetPath] + LidSleepHelper.pmsetArguments(disableSleep: true)
        )
        isSetUp = check.succeeded
    }

    /// Asks for an admin password once and installs the narrowly scoped sudoers rule.
    func install() async {
        guard !isBusy else { return } // Never show two admin prompts.
        isBusy = true
        defer { isBusy = false }
        do {
            let script = try LidSleepHelper.installScript(user: NSUserName())
            _ = await runPrivileged("set up lid-closed mode", script: script, prompt: Self.adminPrompt)
        } catch {
            lastError = "Couldn't set up lid-closed mode: \(error.localizedDescription)"
        }
    }

    /// Turns lid sleep back on and removes the sudoers rule. The caller switches lid-closed mode
    /// off first; while this runs, `reconcile` is paused so nothing turns lid sleep off again.
    func uninstall() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        // Let a switch that's already in flight land, so ownership below is accurate.
        while isReconciling {
            try? await Task.sleep(for: .milliseconds(100))
        }
        // Without a password first, so cancelling the admin prompt can't strand the switch.
        if isDisabledByUs, !(await turnLidSleepBackOn()) { return }
        _ = await runPrivileged("remove lid-closed mode", script: LidSleepHelper.uninstallScript(), prompt: Self.removePrompt)
    }

    /// Callers set `isBusy` around this.
    private func runPrivileged(_ action: String, script: String, prompt: String) async -> Bool {
        let result = await CommandRunner.run(
            "/usr/bin/osascript", ["-e", LidSleepHelper.administratorAppleScript(shell: script, prompt: prompt)]
        )
        if result.succeeded {
            lastError = nil
        } else if !result.errorOutput.contains("-128") { // -128: the user pressed Cancel.
            lastError = "Couldn't \(action): \(result.errorOutput)"
        }
        await refreshSetupStatus()
        return result.succeeded
    }

    // MARK: Switching

    /// Moves the switch toward the wanted state. Never turns off a switch someone else turned on.
    func reconcile(wantSleepDisabled: Bool, systemSleepDisabled: Bool) {
        wantsSleepDisabled = wantSleepDisabled
        self.systemSleepDisabled = systemSleepDisabled
        guard !isReconciling, !isBusy else { return }
        // Turning on: only when it's actually off (it may be on already, ours or someone else's).
        // Turning off: only when we're the ones who turned it on.
        let needsChange = wantSleepDisabled ? !systemSleepDisabled : isDisabledByUs
        guard needsChange else { return }

        isReconciling = true
        Task {
            if wantSleepDisabled {
                _ = await turnLidSleepOff()
            } else {
                _ = await turnLidSleepBackOn()
            }
            isReconciling = false
            if wantsSleepDisabled != wantSleepDisabled {
                reconcile(wantSleepDisabled: wantsSleepDisabled, systemSleepDisabled: wantSleepDisabled)
            }
        }
    }

    private func turnLidSleepOff() async -> Bool {
        // Claim ownership and arm the watchdog first: if we die mid-command, both still clean up.
        isDisabledByUs = true
        startWatchdog()
        guard await runPmset(disableSleep: true) else {
            isDisabledByUs = false
            stopWatchdog()
            return false
        }
        return true
    }

    private func turnLidSleepBackOn() async -> Bool {
        guard await runPmset(disableSleep: false) else { return false }
        isDisabledByUs = false
        stopWatchdog()
        return true
    }

    private func runPmset(disableSleep: Bool) async -> Bool {
        let result = await CommandRunner.run(
            LidSleepHelper.sudoPath,
            ["-n", LidSleepHelper.pmsetPath] + LidSleepHelper.pmsetArguments(disableSleep: disableSleep)
        )
        guard result.succeeded else {
            Self.log.error("pmset disablesleep failed: \(result.errorOutput, privacy: .public)")
            lastError = "Couldn't change lid sleep: \(result.errorOutput)"
            await refreshSetupStatus()
            return false
        }
        lastError = nil
        return true
    }

    /// Called from `applicationWillTerminate`; must finish before the process exits.
    func restoreForTermination() {
        guard isDisabledByUs || isReconciling else { return }
        let status = CommandRunner.runAndWait(
            LidSleepHelper.sudoPath,
            ["-n", LidSleepHelper.pmsetPath] + LidSleepHelper.pmsetArguments(disableSleep: false)
        )
        if status == 0 { isDisabledByUs = false }
        // The watchdog is left running on purpose: if a `pmset … 1` was still in flight, it lands
        // after this, and the watchdog turns lid sleep back on once this process has exited.
    }

    // MARK: Watchdog

    private func startWatchdog() {
        guard watchdog?.isRunning != true else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", LidSleepHelper.watchdogScript(
            appPID: ProcessInfo.processInfo.processIdentifier,
            executablePath: Bundle.main.executablePath ?? CommandLine.arguments[0]
        )]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            watchdog = process
        } catch {
            Self.log.error("Couldn't start the lid-sleep watchdog: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func stopWatchdog() {
        if watchdog?.isRunning == true { watchdog?.terminate() }
        watchdog = nil
    }
}
