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
            AppSwitch(title: "Stay awake with lid closed", isOn: controller.lidModeSwitch(isEnabled: isEnabled), tint: Theme.lid, isSmall: true)
                .disabled(controller.lid.isBusy)
        }
        .tile()
    }

    private var isActive: Bool { controller.lidDecision.disablesLidSleep }

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

extension AwakeController {
    /// The lid-closed mode switch: on while setup runs, then on when the mode is enabled and set up.
    func lidModeSwitch(isEnabled: Bool) -> Binding<Bool> {
        Binding(
            get: { self.lid.isBusy || (isEnabled && self.lid.isSetUp) },
            set: { newValue in Task { await self.setLidClosedMode(newValue) } }
        )
    }
}

/// How many other apps are keeping the Mac awake; clicking lists them beside the menu.
struct BlockersTile: View {
    let blockers: [SleepBlocker]
    var hasLid = true
    @State private var isShowingList = false

    var body: some View {
        Button {
            isShowingList.toggle()
        } label: {
            HStack {
                Text(blockers.isEmpty ? "No other apps keeping it awake" : "Other apps keeping it awake")
                    .font(.tileTitle)
                if !blockers.isEmpty {
                    Text("\(blockers.count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 6)
                        .background(Color.primary.opacity(0.1), in: Capsule())
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isShowingList ? .primary : .secondary)
                }
            }
            .tile()
            .contentShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(blockers.isEmpty)
        .sidePanel(isPresented: $isShowingList) { BlockersList(blockers: blockers, hasLid: hasLid) }
    }
}

/// The other apps keeping the Mac awake, with what each one says it's doing.
struct BlockersList: View {
    let blockers: [SleepBlocker]
    let hasLid: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Other apps keeping it awake").font(.sectionLabel).foregroundStyle(.secondary)
            if blockers.isEmpty {
                Text("None right now").font(.caption).foregroundStyle(.secondary)
            }
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
            }
            if hasLid {
                Text("These don't keep the Mac awake once the lid is closed.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The one way into a problem report from the menu; the details come in their own window.
struct ReportBugRow: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "ladybug")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 18)
                Text("Report a Bug…").font(.system(size: 12, weight: .medium))
                Spacer()
            }
            .foregroundStyle(isHovering ? .primary : .secondary)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(Color.primary.opacity(isHovering ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
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
            .tint(Theme.workingInk)
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
