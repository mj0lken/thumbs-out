import SwiftUI
import ThumbsOutCore

/// The panel shown when clicking the menu bar icon.
struct MenuPanel: View {
    let controller: AwakeController
    let openSettings: () -> Void

    @AppStorage(SettingsKey.isAutoEnabled) private var isAutoEnabled = AppSettings.defaults.isAutoEnabled
    @AppStorage(SettingsKey.gracePeriodMinutes) private var gracePeriodMinutes = AppSettings.defaults.gracePeriodMinutes

    /// Redraws countdowns and the "now" stretch while the panel is open, between detection ticks.
    private static let clockInterval: TimeInterval = 15

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.clockInterval)) { _ in
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            StatusHeader(controller: controller, isAutoEnabled: $isAutoEnabled)
            StatsStrip(stats: controller.stats, isAwake: controller.decision.keepsAwake)
            AgentsTile(controller: controller)
            graceTile
            if controller.power.hasLid {
                LidTile(controller: controller)
            }
            BlockersTile(blockers: controller.power.blockers, hasLid: controller.power.hasLid)
            PanelFooter(controller: controller, openSettings: openSettings)
        }
        .padding(Theme.panelPadding)
        .frame(width: Theme.panelWidth)
        .tint(Theme.working)
    }

    private var graceTile: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Stay awake after the last command").font(.tileTitle)
                Spacer()
                Text(GracePeriodScale.label(for: gracePeriodMinutes))
                    .font(.tileTitle.monospacedDigit())
                    .foregroundStyle(Theme.working)
                    .contentTransition(.numericText())
            }
            GraceMeter(minutes: $gracePeriodMinutes, remainingMinutes: remainingGraceMinutes)
        }
        .tile()
        .opacity(isAutoEnabled ? 1 : 0.5)
        .disabled(!isAutoEnabled)
    }

    private var remainingGraceMinutes: Double? {
        guard case .gracePeriod(let end) = controller.decision else { return nil }
        return max(0, end.timeIntervalSinceNow / 60)
    }
}

private struct StatusHeader: View {
    let controller: AwakeController
    @Binding var isAutoEnabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            ThumbBadge(color: Theme.color(for: controller.decision), isFilled: controller.decision.keepsAwake)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.panelTitle)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            AppSwitch(title: "Watch agents", isOn: $isAutoEnabled)
                .help("Keep the Mac awake while agents run commands")
        }
    }

    private var title: String {
        controller.decision.keepsAwake ? "Keeping your Mac awake" : "Sleep allowed"
    }

    private var subtitle: String {
        switch controller.decision {
        case .agentsActive(let agents):
            if agents.count == 1, controller.commands.count == 1, let command = controller.commands.first {
                return "\(command.agent.displayName): \(command.summary)"
            }
            return agents.count == 1 ? "\(agents[0].displayName) working" : "\(agents.count) agents working"
        case .gracePeriod(let end):
            return "Agents finished · \(AwakeStats.format(end.timeIntervalSinceNow)) left"
        case .manual(until: let end?):
            return "Manual session · \(AwakeStats.format(end.timeIntervalSinceNow)) left"
        case .manual(until: nil):
            return "Manual session · until you stop it"
        case .sleepAllowed:
            return isAutoEnabled ? "Agents are idle" : "Watching is off"
        }
    }
}

/// How long thumbs-out has kept the Mac awake.
private struct StatsStrip: View {
    let stats: AwakeStats
    let isAwake: Bool

    var body: some View {
        HStack(spacing: 0) {
            stat("Now", isAwake ? AwakeStats.format(stats.currentStretch(at: Date()) ?? 0) : "–")
            Divider().frame(height: 26)
            stat("Today", AwakeStats.format(stats.seconds(on: Date())))
            Divider().frame(height: 26)
            stat("7 days", AwakeStats.format(stats.seconds(inLast: 7, endingOn: Date())))
        }
        .padding(.vertical, 8)
        .tile()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Time kept awake")
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.statValue).contentTransition(.numericText())
            Text(label).font(.sectionLabel).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AgentsTile: View {
    let controller: AwakeController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agents").font(.sectionLabel).foregroundStyle(.secondary)
            if visibleAgents.isEmpty {
                Text("No agents found yet. Install one and it shows up here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(visibleAgents) { agent in
                AgentMenuRow(agent: agent, controller: controller)
            }
        }
        .tile()
    }

    /// Agents that are installed, plus editors and local models only once switched on.
    private var visibleAgents: [Agent] {
        Agent.allCases.filter { agent in
            controller.status(for: agent).isFound
                && (agent.category == .agent || controller.watchedAgents.contains(agent))
        }
    }
}

private struct AgentMenuRow: View {
    let agent: Agent
    let controller: AwakeController
    @AppStorage private var isWatched: Bool

    init(agent: Agent, controller: AwakeController) {
        self.agent = agent
        self.controller = controller
        _isWatched = AppStorage(wrappedValue: agent.isWatchedByDefault, SettingsKey.watch(agent))
    }

    var body: some View {
        let status = controller.status(for: agent)
        let installations = controller.installations(for: agent)
        HStack(spacing: 10) {
            AgentIcon(installations: installations, size: 22)
                .opacity(status.isFound ? 1 : 0.6)
            VStack(alignment: .leading, spacing: 1) {
                Text(agent.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(status.isFound ? .primary : .secondary)
                Text(AgentStatusText.detail(
                    status: status, isWatched: isWatched, installations: installations,
                    commands: controller.commands.filter { $0.agent == agent }
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            StatusDot(status: status, isWatched: isWatched)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(AgentStatusText.badge(for: status, agent: agent))
    }
}
