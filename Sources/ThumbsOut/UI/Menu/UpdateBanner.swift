import AppKit
import SwiftUI
import ThumbsOutCore

/// Tops the panel while a newer release is out. Any writable app bundle gets an in-app Update
/// button (including Homebrew installs paired with `auto_updates true`); read-only Homebrew copies
/// show the upgrade command to copy, and other read-only/translocated copies link to the release page.
struct UpdateBanner: View {
    let release: LatestRelease
    let updates: UpdateChecker
    var isLidSetupBusy = false
    @State private var didCopy = false

    private var installer: UpdateInstaller { updates.installer }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Theme.working)
            VStack(alignment: .leading, spacing: 2) {
                Text("Version \(release.version.description) is available").font(.tileTitle)
                subtitle
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                controls
            }
        }
        .controlSize(.small)
        .tile()
    }

    @ViewBuilder
    private var subtitle: some View {
        if updates.canSelfUpdate {
            switch installer.phase {
            case .idle:
                Text(isLidSetupBusy ? "Finish lid-closed setup to update" : "Installs and restarts thumbs-out")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .downloading(let fraction):
                Text(fraction.map { "Downloading… \(Int(($0 * 100).rounded()))%" } ?? "Downloading…")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            case .verifying:
                Text("Checking the download…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .restarting:
                Text("Restarting…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } else if updates.isHomebrewInstall {
            Text(UpdateChecker.homebrewCommand)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        } else {
            Text("See what's new and download it")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var controls: some View {
        if updates.canSelfUpdate {
            if installer.isBusy {
                ProgressView().controlSize(.small)
            } else {
                Button("Notes") { NSWorkspace.shared.open(release.pageURL) }
                    .help("Open the release page on GitHub")
                Button("Update") { Task { await updates.installAvailableUpdate() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.workingInk)
                    .disabled(isLidSetupBusy || updates.status == .checking)
                    .help("Download, verify and install version \(release.version.description)")
            }
        } else if updates.isHomebrewInstall {
            Button(didCopy ? "Copied" : "Copy") { copyCommand() }
                .help("Copy the Homebrew upgrade command")
            Button("Notes") { NSWorkspace.shared.open(release.pageURL) }
                .help("Open the release page on GitHub")
        } else {
            Button("Download") { NSWorkspace.shared.open(release.pageURL) }
                .help("Open the release page on GitHub")
        }
    }

    private func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(UpdateChecker.homebrewCommand, forType: .string)
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
        }
    }
}
