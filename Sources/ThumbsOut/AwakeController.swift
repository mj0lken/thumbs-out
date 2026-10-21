import ThumbsOutCore
import Foundation
import Observation
import os

/// Polls the process table, decides whether to keep the Mac awake and holds the power assertion.
@MainActor
@Observable
final class AwakeController {
    private(set) var decision: AwakeDecision = .sleepAllowed
    private(set) var commands: [DetectedCommand] = []
    private(set) var manualSession: ManualSession?
    private(set) var power = SystemPowerState()
    private(set) var lidDecision: LidClosedDecision = .allowLidSleep(.turnedOff)
    private(set) var installations: [AgentInstallation] = []
    private(set) var runningAgents: Set<Agent> = []
    private(set) var watchedAgents: Set<Agent> = []
    private(set) var stats = StatsStore.load()

    let lid = LidSleepController()

    @ObservationIgnored private let assertion = SleepAssertion()
    @ObservationIgnored private let spawnWatcher = SpawnWatcher()
    @ObservationIgnored private var transcriptScanner = TranscriptScanner()
    @ObservationIgnored private var lastActivity: Date?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var settingsObserver: NSObjectProtocol?
    @ObservationIgnored private var lastSettings = AppSettings.defaults
    @ObservationIgnored private var pendingSettingsRefresh: Task<Void, Never>?
    /// Bumped on every refresh so a slow, older scan can't overwrite a newer result.
    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var lastScan: Date?
    @ObservationIgnored private var lastStatsSave: Date?
    @ObservationIgnored private var lastCPUSample: CPUSample?

    private static let log = Logger(subsystem: "com.mj0lken.thumbs-out", category: "detection")
    private static let settingsDebounce: Duration = .milliseconds(400)
    /// Installed apps rarely change; rescanning once a minute is plenty.
    private static let rescanInterval: TimeInterval = 60
    /// Stats change every tick; writing them to disk once a minute (and on quit) is enough.
    private static let statsSaveInterval: TimeInterval = 60

    init() {
        AppSettings.registerDefaults()
        watchedAgents = AppSettings.load().watchedAgents
    }

    func start() {
        guard loop == nil else { return }
        isRunning = true
        Task { await lid.prepare() }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsDidChange() }
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: .seconds(self.lastSettings.pollIntervalSeconds))
            }
        }
    }

    func stop() {
        isRunning = false
        loop?.cancel()
        loop = nil
        pendingSettingsRefresh?.cancel()
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        settingsObserver = nil
        assertion.release()
        lid.restoreForTermination()
        StatsStore.save(stats)
    }

    /// What closing the lid would do right now.
    var lidBehavior: LidClosedBehavior {
        LidClosedBehavior.evaluate(
            clamshellCausesSleep: power.clamshellCausesSleep,
            sleepDisabled: power.sleepDisabled,
            disabledByUs: lid.isDisabledByUs
        )
    }

    func status(for agent: Agent) -> AgentStatus {
        AgentStatus.resolve(agent, installations: installations, runningAgents: runningAgents, commands: commands)
    }

    func installations(for agent: Agent) -> [AgentInstallation] {
        installations.filter { $0.agent == agent }
    }

    func rescanAgents() async {
        let files = await Task.detached(priority: .utility) { AgentScanner.scanFiles() }.value
        installations = files + AgentScanner.appsFromLaunchServices(excluding: Set(files.map(\.path)))
        lastScan = Date()
    }

    /// Turns lid-closed mode on or off, running the one-time admin setup first if needed.
    @discardableResult
    func setLidClosedMode(_ enabled: Bool) async -> Bool {
        guard !lid.isBusy else { return false } // A setup or removal is already in progress.
        if enabled, !lid.isSetUp {
            await lid.install()
            guard lid.isSetUp else { return false }
        }
        UserDefaults.standard.set(enabled, forKey: SettingsKey.isLidClosedModeEnabled)
        apply(settings: AppSettings.load(), now: Date())
        return true
    }

    /// Switches lid-closed mode off first, so nothing turns lid sleep off again while the rule is removed.
    func removeLidClosedSetup() async {
        UserDefaults.standard.set(false, forKey: SettingsKey.isLidClosedModeEnabled)
        await lid.uninstall()
    }

    func resetStats() {
        stats = AwakeStats()
        StatsStore.save(stats)
    }

    // MARK: Manual sessions

    /// Starts a manual session; `nil` duration means "until I turn it off".
    func startManualSession(duration: TimeInterval?) {
        manualSession = duration.map { .until(Date().addingTimeInterval($0)) } ?? .indefinite
        applyAndRecord()
    }

    func endManualSession() {
        manualSession = nil
        applyAndRecord()
    }

    /// Records a tick right away, so time before and after the switch is credited correctly.
    private func applyAndRecord() {
        let now = Date()
        apply(settings: lastSettings, now: now)
        recordStats(at: now, pollInterval: lastSettings.pollIntervalSeconds)
    }

    // MARK: Detection

    private func settingsDidChange() {
        let settings = AppSettings.load()
        guard settings != lastSettings else { return }
        // Debounced: text fields write to defaults on every keystroke.
        pendingSettingsRefresh?.cancel()
        pendingSettingsRefresh = Task { [weak self] in
            try? await Task.sleep(for: Self.settingsDebounce)
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    private func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let settings = AppSettings.load()
        lastSettings = settings
        watchedAgents = settings.watchedAgents

        let shouldDetect = settings.isAutoEnabled && !settings.watchedAgents.isEmpty
        let detector = ActivityDetector(ignoredProcessNames: settings.ignoredProcessNames)
        let agents = settings.watchedAgents
        if lastScan.map({ Date().timeIntervalSince($0) > Self.rescanInterval }) ?? true {
            await rescanAgents()
        }
        let previousSample = lastCPUSample
        let transcriptScanner = transcriptScanner
        let spawnWatcher = spawnWatcher
        let scan = await Task.detached(priority: .utility) {
            let snapshot = ProcessLister.snapshot()
            let uptime = ProcessInfo.processInfo.systemUptime
            spawnWatcher.update(
                targets: shouldDetect ? detector.spawnWatchTargets(in: snapshot, watching: agents) : [],
                detector: detector, watching: agents
            )
            let transcripts = shouldDetect
                ? transcriptScanner.scanning(agents, home: TranscriptFolders.home, now: Date(), list: TranscriptFolders.list)
                : (scanner: transcriptScanner, writers: [])
            return Scan(
                commands: shouldDetect
                    ? detector.activeCommands(in: snapshot, watching: agents)
                        + RuntimeActivityDetector().busyRuntimes(
                            in: snapshot, uptime: uptime, previous: previousSample, watching: agents
                        )
                    : [],
                agentPIDs: ActivityDetector.agentPIDs(in: snapshot),
                transcriptScanner: transcripts.scanner,
                transcriptWriters: transcripts.writers,
                power: SystemPowerReader.read(),
                cpuSample: RuntimeActivityDetector.sample(snapshot, uptime: uptime)
            )
        }.value
        guard isRunning, generation == refreshGeneration else { return }
        lastCPUSample = scan.cpuSample
        self.transcriptScanner = scan.transcriptScanner
        if !scan.transcriptWriters.isEmpty {
            let writers = scan.transcriptWriters.map(\.id).sorted().joined(separator: ", ")
            Self.log.debug("Transcript writes by \(writers, privacy: .public)")
        }
        // Taken only once the scan is current, so a superseded one can't drop them.
        let shortCommands = spawnWatcher.takeCommands().filter { agents.contains($0.agent) }
        commands = shouldDetect
            ? ActivityDetector.addingRecentWork(
                to: scan.commands, shortCommands: shortCommands,
                transcriptWriters: scan.transcriptWriters, agentPIDs: scan.agentPIDs
            )
            : []
        runningAgents = Set(scan.agentPIDs.keys)
        power = scan.power

        let now = Date()
        if !commands.isEmpty { lastActivity = now }
        apply(settings: settings, now: now)
        recordStats(at: now, pollInterval: settings.pollIntervalSeconds)
    }

    /// What one detection tick found off the main actor.
    private struct Scan: Sendable {
        let commands: [DetectedCommand]
        let agentPIDs: [Agent: Int32]
        let transcriptScanner: TranscriptScanner
        let transcriptWriters: Set<Agent>
        let power: SystemPowerState
        let cpuSample: CPUSample
    }

    private func recordStats(at now: Date, pollInterval: Int) {
        // Allow some slack over the poll interval; anything longer means the Mac was asleep or suspended.
        let maxGap = TimeInterval(pollInterval * 2 + 5)
        stats = stats.recording(
            keepsAwake: decision.keepsAwake, at: now, uptime: ProcessInfo.processInfo.systemUptime, maxCountedGap: maxGap
        )
        if lastStatsSave.map({ now.timeIntervalSince($0) >= Self.statsSaveInterval }) ?? true {
            StatsStore.save(stats)
            lastStatsSave = now
        }
    }

    private func apply(settings: AppSettings, now: Date) {
        if let manualSession, manualSession.isExpired(at: now) {
            self.manualSession = nil
        }
        let activeAgents = Agent.allCases.filter { agent in commands.contains { $0.agent == agent } }
        decision = AwakePolicy.decide(
            now: now,
            activeAgents: activeAgents,
            lastActivity: lastActivity,
            gracePeriod: TimeInterval(settings.gracePeriodMinutes * 60),
            manual: manualSession,
            isAutoEnabled: settings.isAutoEnabled
        )

        if decision.keepsAwake {
            assertion.hold(keepDisplayAwake: settings.keepDisplayAwake, reason: assertionReason)
        } else {
            assertion.release()
        }

        lidDecision = LidClosedPolicy.decide(
            keepsAwake: decision.keepsAwake,
            isEnabled: settings.isLidClosedModeEnabled,
            isSetUp: lid.isSetUp,
            hasLid: power.hasLid,
            power: power.power,
            minimumBatteryPercent: settings.minimumBatteryPercent
        )
        lid.reconcile(wantSleepDisabled: lidDecision.disablesLidSleep, systemSleepDisabled: power.sleepDisabled)
    }

    private var assertionReason: String {
        switch decision {
        case .agentsActive(let agents):
            "thumbs-out: \(agents.map(\.displayName).joined(separator: ", ")) working"
        case .manual: "thumbs-out: manual session"
        case .gracePeriod: "thumbs-out: waiting for agents to finish"
        case .sleepAllowed: "thumbs-out"
        }
    }

    #if DEBUG
    /// Fills in representative state for offscreen snapshots, without starting detection.
    func loadSnapshotState() async {
        await rescanAgents()
        commands = [
            DetectedCommand(agent: .claudeCode, pid: 1, summary: "swift test --parallel"),
            DetectedCommand(agent: .antigravity, pid: 2, summary: "npm run dev"),
        ]
        runningAgents = [.claudeCode, .antigravity, .cursor] // Cursor open but idle: the blue dot
        power = SystemPowerReader.read()
        stats = DemoRenderer.stats(todayMinutes: 134, weekMinutes: 580, currentMinutes: 47, now: Date())
        lid.simulateLidMode(active: false)
        UserDefaults.standard.set(true, forKey: SettingsKey.isLidClosedModeEnabled)
        power.sleepDisabled = false
        decision = .agentsActive([.claudeCode, .antigravity])
    }

    /// One staged moment of the demo animation.
    struct DemoState {
        var decision: AwakeDecision
        var commands: [DetectedCommand]
        var running: Set<Agent>
        var lidActive: Bool
        var stats: AwakeStats
        var blockers: [SleepBlocker] = []
    }

    func applyDemo(_ state: DemoState) {
        decision = state.decision
        commands = state.commands
        runningAgents = state.running
        stats = state.stats
        lid.simulateLidMode(active: state.lidActive)
        UserDefaults.standard.set(true, forKey: SettingsKey.isLidClosedModeEnabled)
        lidDecision = state.lidActive ? .disableLidSleep : .allowLidSleep(.notNeeded)
        power.sleepDisabled = state.lidActive
        power.hasLid = true
        power.blockers = state.blockers
    }

    /// Snapshot variant: a desktop Mac (mini, Studio, iMac) with no lid and no battery.
    func simulateDesktopMac() {
        power.hasLid = false
        power.power = PowerStatus(isOnBattery: false, batteryPercent: nil)
    }
    #endif
}
