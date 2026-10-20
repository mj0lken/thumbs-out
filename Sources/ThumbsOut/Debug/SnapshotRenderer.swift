#if DEBUG
import AppKit
import SwiftUI

/// `ThumbsOut --render-snapshots <dir>` writes PNGs of every screen, in light and dark, then exits.
/// Debug builds only; used to review the UI without driving the real menu bar.
@MainActor
enum SnapshotRenderer {
    static func runIfRequested(controller: AwakeController) async {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--render-snapshots"), flag + 1 < arguments.count else { return }
        let directory = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        await controller.loadSnapshotState()

        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .light ? "light" : "dark"
            render(MenuPanel(controller: controller) {}.background(.regularMaterial), scheme, directory, "menu-\(suffix)")
            render(SettingsView(controller: controller) {}.frame(width: 520, height: 1500), scheme, directory, "settings-\(suffix)")
            for step in OnboardingView.Step.allCases {
                render(OnboardingView(controller: controller, initialStep: step) {}, scheme, directory, "onboarding-\(step.rawValue)-\(suffix)")
            }
        }
        exit(0)
    }

    private static func render(_ view: some View, _ scheme: ColorScheme, _ directory: URL, _ name: String) {
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, scheme))
        hosting.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let size = hosting.fittingSize
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.appearance = hosting.appearance
        window.backgroundColor = scheme == .dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.96, alpha: 1)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("\(name).png"))
        window.orderOut(nil)
    }
}
#endif
