import AppKit
import SwiftUI
import ThumbsOutCore

/// Tops the panel while a newer release is out. Homebrew installs get the upgrade command to copy;
/// others get the release page, with the notes and the download.
struct UpdateBanner: View {
    let release: LatestRelease
    let isHomebrewInstall: Bool
    @State private var didCopy = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Theme.working)
            VStack(alignment: .leading, spacing: 2) {
                Text("Version \(release.version.description) is available").font(.tileTitle)
                Text(isHomebrewInstall ? UpdateChecker.homebrewCommand : "See what's new and download it")
                    .font(isHomebrewInstall ? .caption.monospaced() : .caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 4)
            if isHomebrewInstall {
                Button(didCopy ? "Copied" : "Copy") { copyCommand() }
                    .help("Copy the Homebrew upgrade command")
            }
            Button(isHomebrewInstall ? "Notes" : "Download") {
                NSWorkspace.shared.open(release.pageURL)
            }
            .help("Open the release page on GitHub")
        }
        .controlSize(.small)
        .tile()
    }

    private func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(UpdateChecker.homebrewCommand, forType: .string)
        didCopy = true
    }
}
