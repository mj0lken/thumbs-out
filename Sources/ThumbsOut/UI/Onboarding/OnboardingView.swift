import SwiftUI
import ThumbsOutCore

/// First-launch walkthrough: agents found, grace period, lid-closed mode, launch at login.
struct OnboardingView: View {
    let controller: AwakeController
    let finish: () -> Void

    enum Step: Int, CaseIterable {
        case welcome, agents, awake, lid, done
    }

    @State private var step: Step
    @State private var isMovingForward = true
    @State private var launchAtLogin: Bool
    @State private var launchAtLoginError: String?

    /// - Parameter suggestLaunchAtLogin: preselect launch at login (first run); otherwise reflect
    ///   the current setting, so reopening the welcome flow never silently turns it back on.
    init(
        controller: AwakeController,
        initialStep: Step = .welcome,
        suggestLaunchAtLogin: Bool = true,
        finish: @escaping () -> Void
    ) {
        self.controller = controller
        self.finish = finish
        _step = State(initialValue: initialStep)
        _launchAtLogin = State(initialValue: suggestLaunchAtLogin || LaunchAtLogin.isEnabled)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                stepContent
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .offset(x: isMovingForward ? 40 : -40).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 44)
            .padding(.top, 48)
            .padding(.bottom, 24)

            Divider()
            bottomBar
        }
        .frame(width: 600, height: 580)
        .background(.background)
        .tint(Theme.working)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome: WelcomeStep()
        case .agents: AgentsStep(controller: controller)
        case .awake: AwakeStep()
        case .lid: LidStep(controller: controller)
        case .done: DoneStep(launchAtLogin: $launchAtLogin, error: launchAtLoginError)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { item in
                    Capsule()
                        .fill(item == step ? Theme.working : Color.primary.opacity(0.15))
                        .frame(width: item == step ? 18 : 6, height: 6)
                }
            }
            .animation(.snappy, value: step)
            .accessibilityElement()
            .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")

            Spacer()

            if step != .welcome {
                Button("Back") { move(by: -1) }
                    .keyboardShortcut(.cancelAction)
            }
            Button(primaryTitle) {
                if step == .done { complete() } else { move(by: 1) }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(Theme.workingInk)
        }
        .controlSize(.large)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: "Get Started"
        case .done: "Start Using thumbs-out"
        default: "Continue"
        }
    }

    private func move(by offset: Int) {
        guard var next = Step(rawValue: step.rawValue + offset) else { return }
        // Desktop Macs have no lid: skip that step.
        if next == .lid, !controller.power.hasLid, let skipped = Step(rawValue: next.rawValue + offset) {
            next = skipped
        }
        isMovingForward = offset > 0
        withAnimation(.snappy(duration: 0.28)) { step = next }
    }

    private func complete() {
        if launchAtLogin != LaunchAtLogin.isEnabled {
            do {
                try LaunchAtLogin.setEnabled(launchAtLogin)
            } catch {
                launchAtLoginError = "Couldn't change the login item: \(error.localizedDescription)"
                return
            }
        }
        finish()
    }
}

/// Title block shared by every step.
private struct StepHeader: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(tint)
            Text(title).font(.system(size: 26, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 22)
    }
}

private struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ThumbBadge(color: Theme.working, size: 84)
                .padding(.bottom, 26)
            Text("Thumbs out.").font(.heroTitle)
            Text("Your agents keep working. Your Mac stays awake. No more walking around holding the lid open.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .padding(.bottom, 30)

            VStack(alignment: .leading, spacing: 16) {
                feature("terminal", Theme.working, "Notices when Claude Code, ChatGPT/Codex or Antigravity run commands")
                feature("laptopcomputer", Theme.lid, "Can keep the Mac awake with the lid closed, too")
                feature("chart.bar.fill", Theme.grace, "Shows how long it has kept your Mac awake")
            }
        }
    }

    private func feature(_ symbol: String, _ tint: Color, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(text).font(.body)
        }
    }
}

private struct AgentsStep: View {
    let controller: AwakeController
    @State private var isScanning = false

    var body: some View {
        let foundAgents = AgentCatalog.found(in: .agent, controller: controller)
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(
                symbol: "magnifyingglass", tint: Theme.running,
                title: foundAgents.isEmpty ? "No agents found yet" : "Found \(foundAgents.count) agents on this Mac",
                subtitle: "thumbs-out watches the ones that are switched on, and picks up agents you install later."
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Agent.Category.allCases, id: \.self) { category in
                        let found = AgentCatalog.found(in: category, controller: controller)
                        if !found.isEmpty {
                            categoryGroup(category, agents: found)
                        }
                    }
                }
            }
            .scrollIndicators(.automatic)
            Button(isScanning ? "Scanning…" : "Scan Again") {
                Task {
                    isScanning = true
                    await controller.rescanAgents()
                    isScanning = false
                }
            }
            .disabled(isScanning)
            .padding(.top, 12)
        }
        .task { await controller.rescanAgents() }
    }

    private func categoryGroup(_ category: Agent.Category, agents: [Agent]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(category.title).font(.sectionLabel).foregroundStyle(.secondary)
            VStack(spacing: 12) {
                ForEach(agents) { agent in
                    AgentCoverageRow(
                        agent: agent,
                        status: controller.status(for: agent),
                        installations: controller.installations(for: agent)
                    )
                    if agent != agents.last { Divider() }
                }
            }
            .tile()
            if category != .agent {
                Text(AgentCatalog.footer(for: category)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct AwakeStep: View {
    @AppStorage(SettingsKey.gracePeriodMinutes) private var gracePeriodMinutes = AppSettings.defaults.gracePeriodMinutes
    @AppStorage(SettingsKey.keepDisplayAwake) private var keepDisplayAwake = AppSettings.defaults.keepDisplayAwake

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(
                symbol: "hourglass", tint: Theme.grace,
                title: "Give agents time to think",
                subtitle: "Agents pause between commands while they think. thumbs-out stays awake for a grace period after the last one."
            )
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Stay awake after the last command").font(.tileTitle)
                    Spacer()
                    Text(GracePeriodScale.label(for: gracePeriodMinutes))
                        .font(.statValue)
                        .foregroundStyle(Theme.workingInk)
                        .contentTransition(.numericText())
                }
                GraceMeter(minutes: $gracePeriodMinutes)
            }
            .tile()
            SwitchRow(
                title: "Keep the display on too",
                subtitle: "Off lets the screen turn off while the Mac keeps working.",
                isOn: $keepDisplayAwake
            )
            .tile()
            .padding(.top, 10)
        }
    }
}

private struct LidStep: View {
    let controller: AwakeController
    @AppStorage(SettingsKey.isLidClosedModeEnabled)
    private var isEnabled = AppSettings.defaults.isLidClosedModeEnabled
    @AppStorage(SettingsKey.minimumBatteryPercent)
    private var minimumBatteryPercent = AppSettings.defaults.minimumBatteryPercent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(
                symbol: "laptopcomputer", tint: Theme.lid,
                title: "Close the lid, keep working",
                subtitle: "Normally a MacBook sleeps the moment you close it. thumbs-out can keep it awake while agents work, and lets it sleep again when they're done."
            )
            VStack(alignment: .leading, spacing: 12) {
                SwitchRow(
                    title: "Stay awake with the lid closed",
                    subtitle: controller.lid.isBusy ? "Waiting for your password…" : "Asks for your admin password once.",
                    isOn: Binding(
                        get: { controller.lid.isBusy || (isEnabled && controller.lid.isSetUp) },
                        set: { newValue in Task { await controller.setLidClosedMode(newValue) } }
                    ),
                    tint: Theme.lid
                )
                .disabled(controller.lid.isBusy)

                if isEnabled, controller.lid.isSetUp {
                    Divider()
                    Picker("Stop below battery level", selection: $minimumBatteryPercent) {
                        ForEach(AppSettings.minimumBatteryChoices, id: \.self) { Text("\($0)%").tag($0) }
                    }
                }
                if let error = controller.lid.lastError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
            }
            .tile()

            Label(
                "A closed MacBook running agents gets warm. Keep it out of tight bags.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .symbolRenderingMode(.multicolor)
            .padding(.top, 14)
        }
    }
}

private struct DoneStep: View {
    @Binding var launchAtLogin: Bool
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(
                symbol: "checkmark.circle.fill", tint: Theme.working,
                title: "You're all set",
                subtitle: "thumbs-out lives in your menu bar. Click the thumb to see what it's doing and how long it's kept your Mac awake."
            )
            SwitchRow(
                title: "Launch at login",
                subtitle: "Start thumbs-out automatically, so it's always watching.",
                isOn: $launchAtLogin
            )
            .tile()
            if let error {
                Text(error).font(.callout).foregroundStyle(.red).padding(.top, 8)
            }
            Text("You can change all of this later in Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 14)
        }
    }
}
