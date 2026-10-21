import AppKit
import SwiftUI
import ThumbsOutCore

/// Settings › Updates: the daily check, what it last found, and a button to check now.
struct UpdatesSection: View {
    /// Absent in snapshots that don't show updates.
    @Environment(UpdateChecker.self) private var updates: UpdateChecker?
    @AppStorage(SettingsKey.checksForUpdates) private var checksAutomatically = true

    var body: some View {
        if let updates {
            Section {
                FormSwitch(title: "Check for updates automatically", isOn: $checksAutomatically)
                LabeledContent("Version", value: updates.currentVersion?.description ?? "development build")
                HStack(spacing: 8) {
                    status(of: updates)
                    Spacer()
                    if let release = updates.availableUpdate {
                        Button("Download…") { NSWorkspace.shared.open(release.pageURL) }
                    }
                    Button("Check Now") { Task { await updates.checkNow() } }
                        .disabled(updates.state == .checking || updates.currentVersion == nil)
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("Once a day, thumbs-out asks GitHub for the latest release. Nothing is downloaded or installed without you. Installed with Homebrew? Update with \(UpdateChecker.homebrewCommand).")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func status(of updates: UpdateChecker) -> some View {
        switch updates.state {
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking…").foregroundStyle(.secondary)
            }
        case .available(let release):
            Text("thumbs-out \(release.version.description) is available").foregroundStyle(Theme.workingInk)
        case .failed(let message):
            Text("Couldn't check: \(message)").foregroundStyle(.red)
        case .upToDate:
            Text("Up to date").foregroundStyle(.secondary)
        case .idle:
            Text(updates.lastCheck.map { "Last checked \($0.formatted(.relative(presentation: .named)))" } ?? "Not checked yet")
                .foregroundStyle(.secondary)
        }
    }
}
