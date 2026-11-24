import AppKit
import SwiftUI
import ThumbsOutCore

/// Settings › Updates: periodic checks, what was last found, and one-click in-app updates.
struct UpdatesSection: View {
    var isLidSetupBusy = false
    /// Absent in snapshots that don't show updates.
    @Environment(UpdateChecker.self) private var updates: UpdateChecker?
    @AppStorage(SettingsKey.checksForUpdates) private var checksAutomatically = true
    @State private var didCopyHomebrew = false

    var body: some View {
        if let updates {
            Section {
                FormSwitch(title: "Check for updates automatically", isOn: $checksAutomatically)
                LabeledContent("Version", value: updates.currentVersion?.description ?? "development build")
                HStack(spacing: 8) {
                    status(of: updates)
                    Spacer()
                    if updates.installer.isBusy {
                        ProgressView().controlSize(.small)
                    } else if let release = updates.availableUpdate {
                        if updates.canSelfUpdate {
                            Button("Update") { Task { await updates.installAvailableUpdate() } }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.workingInk)
                                .disabled(isLidSetupBusy || updates.status == .checking)
                        } else if updates.isHomebrewInstall {
                            Button(didCopyHomebrew ? "Copied" : "Copy Command") { copyHomebrewCommand() }
                            Button("Notes") { NSWorkspace.shared.open(release.pageURL) }
                        } else {
                            Button("Download…") { NSWorkspace.shared.open(release.pageURL) }
                        }
                    }
                    Button("Check Now") { Task { await updates.checkNow() } }
                        .disabled(updates.status == .checking || updates.installer.isBusy || updates.currentVersion == nil)
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("thumbs-out checks GitHub every 30 minutes and on wake. Nothing is downloaded or installed until you click Update. Homebrew users can update in-app or with \(UpdateChecker.homebrewCommand).")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func copyHomebrewCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(UpdateChecker.homebrewCommand, forType: .string)
        didCopyHomebrew = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopyHomebrew = false
        }
    }

    @ViewBuilder
    private func status(of updates: UpdateChecker) -> some View {
        switch updates.installer.phase {
        case .downloading(let fraction):
            Text(fraction.map { "Downloading… \(Int(($0 * 100).rounded()))%" } ?? "Downloading…")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        case .verifying:
            Text("Checking the download…").foregroundStyle(.secondary)
        case .restarting:
            Text("Restarting…").foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).foregroundStyle(.red)
        case .idle:
            switch (updates.status, updates.availableUpdate) {
            case (.checking, _):
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Checking…").foregroundStyle(.secondary)
                }
            case (.failed(let message), _):
                Text("Couldn't check: \(message)").foregroundStyle(.red)
            case (_, .some(let release)):
                Text("thumbs-out \(release.version.description) is available").foregroundStyle(Theme.workingInk)
            case (.upToDate, nil):
                Text("Up to date").foregroundStyle(.secondary)
            case (.idle, nil):
                Text(updates.lastCheck.map { "Last checked \($0.formatted(.relative(presentation: .named)))" } ?? "Not checked yet")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
