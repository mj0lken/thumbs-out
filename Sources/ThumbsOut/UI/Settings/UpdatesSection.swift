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
                        .disabled(updates.status == .checking || updates.currentVersion == nil)
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
