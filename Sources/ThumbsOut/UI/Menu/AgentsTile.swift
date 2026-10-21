import SwiftUI
import ThumbsOutCore

/// The agents that are open right now. The row below opens the rest beside the menu, so the panel
/// keeps its height.
struct AgentsTile: View {
    let controller: AwakeController
    @State private var isShowingAll = false

    var body: some View {
        let groups = AgentGroups.group(watched: controller.watchedAgents) { controller.status(for: $0) }
        VStack(alignment: .leading, spacing: 8) {
            Text("Agents").font(.sectionLabel).foregroundStyle(.secondary)
            if groups.open.isEmpty {
                Text(groups.installed.isEmpty ? "No agents found yet. Install one and it shows up here." : "No agents open right now")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(groups.open) { agent in
                AgentMenuRow(agent: agent, controller: controller)
            }
            if !groups.installed.isEmpty || !groups.notInstalled.isEmpty {
                ShowAllButton(summary: Self.summary(for: groups), isShowingAll: $isShowingAll)
                    .sidePanel(isPresented: $isShowingAll) { AllAgentsList(controller: controller) }
            }
        }
        .tile()
    }

    private static func summary(for groups: AgentGroups) -> String {
        switch (groups.installed.count, groups.notInstalled.count) {
        case (0, let more): "Show \(more) more"
        case (let installed, 0): "Show \(installed) installed"
        case (let installed, let more): "Show \(installed) installed and \(more) more"
        }
    }
}

/// Everything that isn't open: the other installed agents, then the rest of the catalog.
struct AllAgentsList: View {
    let controller: AwakeController

    var body: some View {
        let groups = AgentGroups.group(watched: controller.watchedAgents) { controller.status(for: $0) }
        VStack(alignment: .leading, spacing: 8) {
            if !groups.installed.isEmpty {
                Text("Installed").font(.sectionLabel).foregroundStyle(.secondary)
                ForEach(groups.installed) { agent in
                    AgentMenuRow(agent: agent, controller: controller)
                }
            }
            if !groups.installed.isEmpty, !groups.notInstalled.isEmpty {
                Divider().padding(.vertical, 2)
            }
            if !groups.notInstalled.isEmpty {
                Text("Also works with").font(.sectionLabel).foregroundStyle(.secondary)
                NotInstalledGrid(agents: groups.notInstalled)
            }
        }
    }
}

/// The row under the open agents; it stays highlighted while the full list is showing.
private struct ShowAllButton: View {
    let summary: String
    @Binding var isShowingAll: Bool
    @State private var isHovering = false

    var body: some View {
        let isHighlighted = isHovering || isShowingAll
        Button {
            isShowingAll.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(summary)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .frame(width: 18) // Lines up with the status dots above.
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(isHighlighted ? .primary : .secondary)
            .padding(.horizontal, 6)
            .frame(height: 24)
            .background(Color.primary.opacity(isHighlighted ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -6) // The hover fill bleeds out; the text stays aligned with the rows.
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHighlighted)
        .accessibilityLabel("Show all agents")
        .accessibilityValue(summary)
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

/// Agents thumbs-out supports but didn't find: names only, two to a line, so the list stays short.
private struct NotInstalledGrid: View {
    let agents: [Agent]

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .leading), count: 2)

    var body: some View {
        LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 6) {
            ForEach(agents) { agent in
                HStack(spacing: 6) {
                    AgentIcon(installations: [], size: 14)
                    Text(agent.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue("Not found on this Mac")
            }
        }
    }
}
