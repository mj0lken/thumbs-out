import AppKit
import ThumbsOutCore

/// Puts together a problem report from thumbs-out's own state on this Mac, and nothing else: no
/// process list, no command lines, nothing about other apps beyond the names the menu already shows.
@MainActor
enum DiagnosticsCollector {
    struct Result: Sendable {
        let report: IssueReport
        /// Newest first. Only their count and date go into the report.
        let crashReports: [CrashReport]
    }

    static let redactor = PrivacyRedactor(
        homeDirectory: NSHomeDirectory(), userName: NSUserName(), fullName: NSFullUserName(), hostName: MacFacts.hostName()
    )
    private nonisolated static let logLimit = 50

    static func collect(from controller: AwakeController) async -> Result {
        await controller.lid.refreshSetupStatus()
        let (log, crashes, mac) = await Task.detached(priority: .userInitiated) {
            (AppLog.recentLines(limit: logLimit), CrashReport.find(), MacFacts.read())
        }.value
        let settings = AppSettings.load()
        let report = IssueReport(
            sections: [
                appSection(crashes: crashes),
                macSection(mac, power: controller.power),
                setupSection(controller, settings: settings),
                nowSection(controller),
                settingsSection(settings),
                agentsSection(controller, watched: settings.watchedAgents),
            ],
            log: log
        )
        return Result(report: report, crashReports: crashes)
    }

    // MARK: Sections

    private static func appSection(crashes: [CrashReport]) -> IssueReport.Section {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = (info["CFBundleShortVersionString"] as? String).map { "\($0) (\(info["CFBundleVersion"] as? String ?? "?"))" }
        let launched = NSRunningApplication.current.launchDate
        return .init("thumbs-out", [
            .init("Version", version ?? "unknown (not a packaged app)"),
            .init("Build", isDebugBuild ? "debug" : "release"),
            .init("Location", location(of: Bundle.main.bundlePath)),
            .init("Running for", launched.map { AwakeStats.format(Date().timeIntervalSince($0)) } ?? "unknown"),
            .init("Crash reports", crashes.first.map {
                "\(crashes.count), latest \($0.date.formatted(date: .abbreviated, time: .omitted)) (not included)"
            } ?? "none"),
        ])
    }

    private static func macSection(_ mac: MacFacts, power: SystemPowerState) -> IssueReport.Section {
        .init("This Mac", [
            .init("macOS", ProcessInfo.processInfo.operatingSystemVersionString),
            .init("Model", mac.model ?? "unknown"),
            .init("Chip", mac.chip ?? "unknown"),
            .init("Lid", power.hasLid ? "yes" : "no (desktop Mac)"),
            .init("Power", describe(power.power)),
            .init("Administrator account", mac.isAdministrator.map(yesNo) ?? "unknown"),
        ])
    }

    private static func setupSection(_ controller: AwakeController, settings: AppSettings) -> IssueReport.Section {
        let lid = controller.lid
        var facts: [IssueReport.Fact] = [
            .init("Lid-closed setup (sudoers rule)", setupState(lid)),
            .init("Lid-closed mode", onOff(settings.isLidClosedModeEnabled)),
            .init("Sleep switch (pmset disablesleep)", sleepSwitch(controller)),
            .init("Closing the lid now", StatusPresentation.lidLine(for: controller.lidBehavior)),
            .init("Lid sleep decision", describe(controller.lidDecision)),
            .init("Launch at login", LaunchAtLogin.statusDescription),
        ]
        if let error = lid.lastError { facts.append(.init("Last lid error", error)) }
        return .init("Setup and permissions", facts)
    }

    private static func nowSection(_ controller: AwakeController) -> IssueReport.Section {
        let blockers = controller.power.blockers.map { $0.keepsDisplayOn ? "\($0.processName) (display too)" : $0.processName }
        return .init("Right now", [
            .init("Keeping the Mac awake", describe(controller.decision)),
            .init("Commands (program names only)", commandPrograms(controller.commands)),
            .init("Agents open", list(Agent.allCases.filter(controller.runningAgents.contains).map(\.displayName))),
            .init("Other apps keeping it awake", list(blockers)),
        ])
    }

    private static func settingsSection(_ settings: AppSettings) -> IssueReport.Section {
        let ignored = settings.ignoredProcessNames == ActivityDetector.defaultIgnoredProcessNames
            ? "default" : list(settings.ignoredProcessNames.sorted())
        return .init("Settings", [
            .init("Watch agents", onOff(settings.isAutoEnabled)),
            .init("Watched", watchedChanges(settings.watchedAgents)),
            .init("Grace period", GracePeriodScale.label(for: settings.gracePeriodMinutes)),
            .init("Keep the display on", onOff(settings.keepDisplayAwake)),
            .init("Check every", "\(settings.pollIntervalSeconds) s"),
            .init("Stop below battery", "\(settings.minimumBatteryPercent)%"),
            .init("Ignored processes", ignored),
        ])
    }

    /// Found agents only, with where they're installed (home folder redacted on the way out).
    private static func agentsSection(_ controller: AwakeController, watched: Set<Agent>) -> IssueReport.Section {
        let facts = Agent.allCases.compactMap { agent -> IssueReport.Fact? in
            let status = controller.status(for: agent)
            guard status.isFound else { return nil }
            let places = controller.installations(for: agent).map { "\($0.name) at \(redactor.installLocation($0.path))" }
            let parts = [describe(status), watched.contains(agent) ? nil : "not watched"].compactMap { $0 } + places
            return .init(agent.displayName, parts.joined(separator: " · "))
        }
        return .init("Agents found", facts.isEmpty ? [.init("Agents", "none found")] : facts)
    }

    // MARK: Wording

    private static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private static func location(of bundlePath: String) -> String {
        if bundlePath.contains("/AppTranslocation/") {
            return "translocated by Gatekeeper (opened from where it was downloaded, not from Applications)"
        }
        return redactor.installLocation(bundlePath)
    }

    /// Tells a missing rule from one sudo won't accept (edited, wrong owner, another user's).
    private static func setupState(_ lid: LidSleepController) -> String {
        if lid.isSetUp { return "installed" }
        guard FileManager.default.fileExists(atPath: LidSleepHelper.sudoersPath) else { return "not installed" }
        return "rule file present, but sudo doesn't accept it" + (lid.setupCheckError.map { " (\($0))" } ?? "")
    }

    private static func describe(_ power: PowerStatus) -> String {
        guard let percent = power.batteryPercent else { return "power adapter, no battery" }
        return power.isOnBattery ? "battery, \(percent)%" : "power adapter, battery at \(percent)%"
    }

    private static func sleepSwitch(_ controller: AwakeController) -> String {
        guard controller.power.sleepDisabled else { return "0 (normal)" }
        return controller.lid.isDisabledByUs ? "1, set by thumbs-out" : "1, set by something else"
    }

    private static func describe(_ decision: LidClosedDecision) -> String {
        switch decision {
        case .disableLidSleep: "turn lid sleep off"
        case .allowLidSleep(.turnedOff): "leave it on: lid-closed mode is off"
        case .allowLidSleep(.noLid): "leave it on: no lid"
        case .allowLidSleep(.setupRequired): "leave it on: setup needed"
        case .allowLidSleep(.notNeeded): "leave it on: not keeping the Mac awake"
        case .allowLidSleep(.lowBattery(let percent)): "leave it on: battery at \(percent)%"
        }
    }

    private static func describe(_ decision: AwakeDecision) -> String {
        switch decision {
        case .sleepAllowed: "no"
        case .agentsActive(let agents): "yes, \(list(agents.map(\.displayName))) running commands"
        case .gracePeriod(let end): "yes, grace period with \(AwakeStats.format(end.timeIntervalSinceNow)) left"
        case .manual(until: nil): "yes, manual session until stopped"
        case .manual(until: let end?): "yes, manual session with \(AwakeStats.format(end.timeIntervalSinceNow)) left"
        }
    }

    private static func describe(_ status: AgentStatus) -> String {
        switch status {
        case .working(let count): "working, \(count) \(count == 1 ? "command" : "commands")"
        case .running: "open, idle"
        case .installed: "installed"
        case .notFound: "not found"
        }
    }

    /// `Claude Code: swift, npm`. Programs only: arguments can hold paths, URLs and secrets.
    private static func commandPrograms(_ commands: [DetectedCommand]) -> String {
        let perAgent = Agent.allCases.compactMap { agent -> String? in
            let programs = commands.filter { $0.agent == agent }.compactMap { CommandSummary.program(of: $0.summary) }
            guard !programs.isEmpty else { return nil }
            let unique = programs.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            return "\(agent.displayName): \(unique.joined(separator: ", "))"
        }
        return perAgent.isEmpty ? "none" : perAgent.joined(separator: "; ")
    }

    private static func watchedChanges(_ watched: Set<Agent>) -> String {
        let defaults = AppSettings.defaults.watchedAgents
        guard watched != defaults else { return "default (every agent, no editors or local models)" }
        let added = Agent.allCases.filter { watched.contains($0) && !defaults.contains($0) }.map(\.displayName)
        let removed = Agent.allCases.filter { !watched.contains($0) && defaults.contains($0) }.map(\.displayName)
        return [added.isEmpty ? nil : "added \(list(added))", removed.isEmpty ? nil : "removed \(list(removed))"]
            .compactMap { $0 }
            .joined(separator: "; ")
    }

    private static func list(_ names: [String]) -> String {
        names.isEmpty ? "none" : names.joined(separator: ", ")
    }

    private static func onOff(_ value: Bool) -> String { value ? "on" : "off" }
    private static func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }
}
