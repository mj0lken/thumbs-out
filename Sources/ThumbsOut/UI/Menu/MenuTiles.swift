import SwiftUI
import ThumbsOutCore

/// Lid-closed mode: what closing the lid does now, and the switch to change it.
struct LidTile: View {
    let controller: AwakeController
    @AppStorage(SettingsKey.isLidClosedModeEnabled)
    private var isEnabled = AppSettings.defaults.isLidClosedModeEnabled

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isActive ? Theme.lid : .secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text("Stay awake with lid closed").font(.tileTitle)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Toggle("Stay awake with lid closed", isOn: binding)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .tint(Theme.lid)
                .disabled(controller.lid.isBusy)
        }
        .tile()
    }

    private var isActive: Bool { controller.lidDecision.disablesLidSleep }

    private var binding: Binding<Bool> {
        Binding(
            get: { controller.lid.isBusy || (isEnabled && controller.lid.isSetUp) },
            set: { newValue in Task { await controller.setLidClosedMode(newValue) } }
        )
    }

    private var detail: String {
        if controller.lid.isBusy { return "Waiting for your password…" }
        guard isEnabled, controller.lid.isSetUp else {
            return controller.lid.isSetUp || controller.lidBehavior != .sleeps
                ? StatusPresentation.lidLine(for: controller.lidBehavior)
                : "Needs your admin password once"
        }
        if isActive { return StatusPresentation.lidLine(for: controller.lidBehavior) }
        return StatusPresentation.lidModeNote(for: controller.lidDecision) ?? "Ready: kicks in while agents work"
    }
}

/// Other apps currently keeping the Mac awake, collapsed by default.
struct BlockersTile: View {
    let blockers: [SleepBlocker]
    var hasLid = true
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text(blockers.isEmpty ? "No other apps keeping it awake" : "Other apps keeping it awake")
                        .font(.tileTitle)
                    if !blockers.isEmpty {
                        Text("\(blockers.count)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .padding(.horizontal, 6)
                            .background(Color.primary.opacity(0.1), in: Capsule())
                    }
                    Spacer()
                    if !blockers.isEmpty {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(blockers.isEmpty)

            if isExpanded {
                ForEach(blockers) { blocker in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(blocker.processName).font(.system(size: 12, weight: .medium))
                        if let summary = blocker.summary {
                            Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if blocker.keepsDisplayOn {
                            Image(systemName: "display").font(.caption2).foregroundStyle(.secondary)
                                .help("Also keeps the display on")
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if hasLid {
                    Text("These don't keep the Mac awake once the lid is closed.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .tile()
    }
}

/// Manual sessions, settings and quit.
struct PanelFooter: View {
    let controller: AwakeController
    let openSettings: () -> Void

    private static let durations: [(title: String, seconds: TimeInterval?)] = [
        ("15 minutes", 15 * 60), ("1 hour", 3_600), ("2 hours", 7_200), ("5 hours", 18_000), ("Until I stop it", nil),
    ]

    var body: some View {
        HStack(spacing: 4) {
            Menu {
                Section("Keep awake for") {
                    ForEach(Self.durations, id: \.title) { option in
                        Button(option.title) { controller.startManualSession(duration: option.seconds) }
                    }
                }
                if controller.manualSession != nil {
                    Divider()
                    Button("End manual session") { controller.endManualSession() }
                }
            } label: {
                Label(manualTitle, systemImage: "timer")
                    .font(.system(size: 12, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.leading, 4)

            Spacer()

            Button(action: openSettings) { Image(systemName: "gearshape") }
                .buttonStyle(IconButtonStyle())
                .help("Settings")
                .accessibilityLabel("Settings")
            Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power") }
                .buttonStyle(IconButtonStyle())
                .help("Quit thumbs-out")
                .accessibilityLabel("Quit thumbs-out")
        }
    }

    private var manualTitle: String {
        switch controller.manualSession {
        case nil: "Keep awake manually…"
        case .indefinite: "Manual session on"
        case .until(let end): "Manual · \(AwakeStats.format(end.timeIntervalSinceNow)) left"
        }
    }
}
