import SwiftUI
import ThumbsOutCore

/// All settings on one scrolling page, grouped into sections.
struct SettingsView: View {
    let controller: AwakeController
    let showWelcome: () -> Void
    let reportProblem: () -> Void

    @AppStorage(SettingsKey.isAutoEnabled) private var isAutoEnabled = AppSettings.defaults.isAutoEnabled
    @AppStorage(SettingsKey.gracePeriodMinutes) private var gracePeriodMinutes = AppSettings.defaults.gracePeriodMinutes
    @AppStorage(SettingsKey.keepDisplayAwake) private var keepDisplayAwake = AppSettings.defaults.keepDisplayAwake
    @AppStorage(SettingsKey.pollIntervalSeconds)
    private var pollIntervalSeconds = AppSettings.defaults.pollIntervalSeconds
    @AppStorage(SettingsKey.ignoredProcessNames)
    private var ignoredProcessNames = AppSettings.defaultIgnoredProcessNamesText

    var body: some View {
        Form {
            agentSections
            keepAwakeSection
            // Also shown without a lid if setup exists, so it can always be removed.
            if controller.power.hasLid || controller.lid.isSetUp {
                LidClosedSection(controller: controller)
            }
            StatsSection(controller: controller)
            detectionSection
            GeneralSection(showWelcome: showWelcome, reportProblem: reportProblem)
            UpdatesSection()
        }
        .formStyle(.grouped)
        .tint(Theme.working)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 520, idealHeight: 720)
    }

    /// One section per category with what was found, then everything not installed, collapsed.
    @ViewBuilder
    private var agentSections: some View {
        ForEach(Agent.Category.allCases, id: \.self) { category in
            let found = AgentCatalog.found(in: category, controller: controller)
            if category == .agent || !found.isEmpty {
                Section {
                    if found.isEmpty {
                        Text("No agents found yet.").foregroundStyle(.secondary)
                    }
                    ForEach(found) { agent in
                        AgentCoverageRow(
                            agent: agent,
                            status: controller.status(for: agent),
                            installations: controller.installations(for: agent)
                        )
                    }
                } header: {
                    categoryHeader(category)
                } footer: {
                    Text(AgentCatalog.footer(for: category)).foregroundStyle(.secondary)
                }
            }
        }
        let missing = AgentCatalog.notFound(controller: controller)
        if !missing.isEmpty {
            Section {
                DisclosureGroup("Not installed (\(missing.count))") {
                    Text(missing.map(\.displayName).joined(separator: ", "))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Agents are covered automatically once installed. Editors and local models can be switched on when they show up above.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private func categoryHeader(_ category: Agent.Category) -> some View {
        if category == .agent {
            HStack {
                Text(category.title)
                Spacer()
                ScanAgainButton(controller: controller)
                    .controlSize(.small)
            }
        } else {
            Text(category.title)
        }
    }

    private var keepAwakeSection: some View {
        Section("Keeping Awake") {
            FormSwitch(title: "Keep the Mac awake while agents run commands", isOn: $isAutoEnabled)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Stay awake after the last command")
                    Spacer()
                    Text(GracePeriodScale.label(for: gracePeriodMinutes))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                GraceMeter(minutes: $gracePeriodMinutes)
                Text("Covers the time an agent spends thinking between commands.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .disabled(!isAutoEnabled)
            FormSwitch(
                title: "Keep the display on too",
                subtitle: "The screen won't lock on its own while thumbs-out keeps the display on.",
                isOn: $keepDisplayAwake
            )
        }
    }

    private var detectionSection: some View {
        Section {
            Stepper(value: $pollIntervalSeconds, in: AppSettings.pollIntervalRange) {
                Text("Check every \(pollIntervalSeconds) seconds")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Ignored background processes")
                TextField("Ignored background processes", text: $ignoredProcessNames, axis: .vertical)
                    .labelsHidden()
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
            }
            Button("Restore Default Ignored Processes") {
                ignoredProcessNames = AppSettings.defaultIgnoredProcessNamesText
            }
        } header: {
            Text("Detection")
        } footer: {
            Text("Comma-separated names of processes that shouldn't count as a running command, like prompt helpers your shell keeps alive.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct LidClosedSection: View {
    let controller: AwakeController
    @AppStorage(SettingsKey.isLidClosedModeEnabled)
    private var isEnabled = AppSettings.defaults.isLidClosedModeEnabled
    @AppStorage(SettingsKey.minimumBatteryPercent)
    private var minimumBatteryPercent = AppSettings.defaults.minimumBatteryPercent
    @AppStorage(SettingsKey.locksScreenOnLidClose)
    private var locksScreen = AppSettings.defaults.locksScreenOnLidClose
    @State private var lockDelay: ScreenLockDelay?

    private var lid: LidSleepController { controller.lid }

    var body: some View {
        Section {
            FormSwitch(
                title: "Stay awake with the lid closed", isOn: controller.lidModeSwitch(isEnabled: isEnabled), tint: Theme.lid
            )
            .disabled(lid.isBusy)
            if ScreenLocker.isAvailable {
                FormSwitch(title: "Lock the screen when the lid closes", isOn: $locksScreen, tint: Theme.lid)
                    .disabled(!isEnabled || !lid.isSetUp)
                if locksScreen, isEnabled, lid.isSetUp {
                    LockDelayHint(delay: lockDelay)
                }
            }
            Picker("Stop below battery level", selection: $minimumBatteryPercent) {
                ForEach(AppSettings.minimumBatteryChoices, id: \.self) { Text("\($0)%").tag($0) }
            }
            .disabled(!isEnabled || !lid.isSetUp)
            LabeledContent("Right now", value: StatusPresentation.lidLine(for: controller.lidBehavior))
            if lid.isSetUp {
                Button("Remove Lid-Closed Setup…", role: .destructive) {
                    Task { await controller.removeLidClosedSetup() }
                }
                .disabled(lid.isBusy)
            }
            if let error = lid.lastError {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        } header: {
            Text("Lid Closed")
        } footer: {
            Text("Turns lid sleep off only while thumbs-out keeps your Mac awake. The first time, it asks for your admin password to allow just the pmset disablesleep command. With the screen locked, agents keep running; open the lid and log in as usual. It doesn't lock while another display is connected. A closed MacBook running agents gets warm, so keep it out of tight bags.")
                .foregroundStyle(.secondary)
        }
        .task { await lid.refreshSetupStatus() }
        .readsScreenLockDelay(into: $lockDelay)
    }
}

private struct StatsSection: View {
    let controller: AwakeController
    @State private var isConfirmingReset = false

    var body: some View {
        let stats = controller.stats
        let now = Date()
        Section("Time Kept Awake") {
            LabeledContent("Today", value: AwakeStats.format(stats.seconds(on: now)))
            LabeledContent("Last 7 days", value: AwakeStats.format(stats.seconds(inLast: 7, endingOn: now)))
            LabeledContent("Last 30 days", value: AwakeStats.format(stats.seconds(inLast: 30, endingOn: now)))
            LabeledContent("All time", value: AwakeStats.format(stats.totalSeconds))
            LabeledContent("Longest stretch", value: AwakeStats.format(stats.longestStretch(at: now)))
            Button("Reset Statistics…") { isConfirmingReset = true }
                .confirmationDialog("Reset all statistics?", isPresented: $isConfirmingReset) {
                    Button("Reset", role: .destructive) { controller.resetStats() }
                }
        }
        .monospacedDigit()
    }
}

private struct GeneralSection: View {
    let showWelcome: () -> Void
    let reportProblem: () -> Void
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?

    var body: some View {
        Section("General") {
            FormSwitch(title: "Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    // Reverting after a failure fires this again; keep the error visible.
                    guard enabled != LaunchAtLogin.isEnabled else { return }
                    launchAtLoginError = LaunchAtLogin.setEnabled(enabled)
                    if launchAtLoginError != nil { launchAtLogin = LaunchAtLogin.isEnabled }
                }
            if let launchAtLoginError {
                Text(launchAtLoginError).foregroundStyle(.red).font(.callout)
            } else if LaunchAtLogin.needsApproval {
                Text("Approve thumbs-out in System Settings › General › Login Items.")
                    .foregroundStyle(.secondary).font(.callout)
            }
            Button("Show Welcome Again…", action: showWelcome)
            Button("Report a Bug…", action: reportProblem)
        }
    }
}
