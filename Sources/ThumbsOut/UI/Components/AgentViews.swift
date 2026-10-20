import AppKit
import SwiftUI
import ThumbsOutCore

/// The agent's real app icon when an app is installed, else a terminal or a dashed placeholder.
struct AgentIcon: View {
    let installations: [AgentInstallation]
    var size: CGFloat = 24

    @MainActor private static var cache: [String: NSImage] = [:]

    var body: some View {
        if let app = installations.first(where: { $0.kind == .app }) {
            Image(nsImage: Self.icon(for: app.path))
                .resizable()
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(installations.isEmpty ? Color.clear : Color.primary.opacity(0.75))
                .overlay {
                    if installations.isEmpty {
                        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    } else {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: size * 0.45))
                            .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                    }
                }
                .frame(width: size * 0.86, height: size * 0.86)
                .frame(width: size, height: size)
        }
    }

    @MainActor private static func icon(for path: String) -> NSImage {
        if let cached = cache[path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache[path] = image
        return image
    }
}

/// A status dot; it pulses gently while the agent is running a command.
struct StatusDot: View {
    let status: AgentStatus
    let isWatched: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            if case .working = status, isWatched, !reduceMotion {
                Circle()
                    .fill(Theme.working.opacity(0.35))
                    .frame(width: 8, height: 8)
                    .scaleEffect(isPulsing ? 2.2 : 1)
                    .opacity(isPulsing ? 0 : 1)
                    .onAppear {
                        withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { isPulsing = true }
                    }
            }
            if status.isFound, isWatched {
                Circle().fill(Theme.color(for: status)).frame(width: 8, height: 8)
            } else {
                Circle().strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1).frame(width: 8, height: 8)
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

enum AgentStatusText {
    static func detail(
        status: AgentStatus, isWatched: Bool, installations: [AgentInstallation], commands: [DetectedCommand]
    ) -> String {
        guard status.isFound else { return "Not found on this Mac" }
        guard isWatched else { return "Found, but not watched" }
        switch status {
        case .working(let count):
            let first = commands.first?.summary ?? "a command"
            return count > 1 ? "\(first) + \(count - 1) more" : first
        case .running:
            return "Open, idle"
        case .installed, .notFound:
            return installations.map(\.name).joined(separator: " · ")
        }
    }

    static func badge(for status: AgentStatus, agent: Agent) -> String {
        switch status {
        case .working: agent.category == .modelRuntime ? "Generating" : "Working"
        case .running: "Running"
        case .installed: "Installed"
        case .notFound: "Not found"
        }
    }
}

/// An agent row for onboarding and settings: what was found, and whether it's covered.
struct AgentCoverageRow: View {
    let agent: Agent
    let status: AgentStatus
    let installations: [AgentInstallation]
    @AppStorage private var isWatched: Bool

    init(agent: Agent, status: AgentStatus, installations: [AgentInstallation]) {
        self.agent = agent
        self.status = status
        self.installations = installations
        _isWatched = AppStorage(wrappedValue: agent.isWatchedByDefault, SettingsKey.watch(agent))
    }

    var body: some View {
        HStack(spacing: 12) {
            AgentIcon(installations: installations, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(agent.displayName).font(.tileTitle)
                    Text(AgentStatusText.badge(for: status, agent: agent))
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.color(for: status).opacity(status.isFound ? 0.16 : 0.08), in: Capsule())
                        .foregroundStyle(status.isFound ? Theme.color(for: status) : .secondary)
                }
                Text(coverageText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(installations.map(\.path).joined(separator: "\n"))
            }
            Spacer(minLength: 8)
            AppSwitch(title: "Watch \(agent.displayName)", isOn: $isWatched, isSmall: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var coverageText: String {
        if installations.isEmpty {
            return status.isFound ? "Running now" : "Not found on this Mac"
        }
        return installations.map(\.name).joined(separator: " · ")
    }
}

/// Catalog groupings shared by Settings and onboarding.
@MainActor
enum AgentCatalog {
    static func found(in category: Agent.Category, controller: AwakeController) -> [Agent] {
        Agent.allCases.filter { $0.category == category && controller.status(for: $0).isFound }
    }

    static func notFound(controller: AwakeController) -> [Agent] {
        Agent.allCases.filter { !controller.status(for: $0).isFound }
    }

    static func footer(for category: Agent.Category) -> String {
        switch category {
        case .agent:
            "Watched by default. Switch one off to stop it from keeping your Mac awake. In agent IDEs like Cursor and Antigravity, commands you type in their terminal count too."
        case .editor:
            "Off by default: every command in these counts, including the ones you type yourself."
        case .modelRuntime:
            "Off by default. Local models don't run commands, so these count as busy while generating (using CPU)."
        }
    }
}

/// Rescans for installed agents, showing progress while it runs.
struct ScanAgainButton: View {
    let controller: AwakeController
    @State private var isScanning = false

    var body: some View {
        Button(isScanning ? "Scanning…" : "Scan Again") {
            Task {
                isScanning = true
                await controller.rescanAgents()
                isScanning = false
            }
        }
        .disabled(isScanning)
    }
}
