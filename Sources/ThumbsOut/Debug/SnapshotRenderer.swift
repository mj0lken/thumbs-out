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
        controller.simulateDesktopMac()
        render(MenuPanel(controller: controller) {}.background(.regularMaterial), .light, directory, "menu-desktop")
        render(SettingsView(controller: controller) {}.frame(width: 520, height: 1500), .light, directory, "settings-desktop")
        finish(status: 0)
    }

    /// Clears the staged settings (`exit` skips `defer`), then exits.
    static func finish(status: Int32) -> Never {
        for key in [SettingsKey.isLidClosedModeEnabled, "lidSleepDisabledByThumbsOut"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        exit(status)
    }

    private static func render(_ view: some View, _ scheme: ColorScheme, _ directory: URL, _ name: String) {
        guard let bitmap = bitmap(of: view, scheme: scheme) else { return }
        try? bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("\(name).png"))
    }

    /// Lays a view out in an offscreen window and captures it at the display's backing scale.
    static func bitmap(of view: some View, scheme: ColorScheme = .light, settle: TimeInterval = 0.3) -> NSBitmapImageRep? {
        let hosting = NSHostingView(
            rootView: view.environment(\.colorScheme, scheme).environment(\.rendersStaticControls, true)
        )
        hosting.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let size = hosting.fittingSize
        let window = ActiveLookingWindow(
            contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.appearance = hosting.appearance
        window.backgroundColor = scheme == .dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.96, alpha: 1)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(settle))
        defer { window.orderOut(nil) }
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return bitmap
    }
}

/// Reports itself as key so controls render in their active, tinted state, without actually
/// taking focus from whatever the user is doing.
private final class ActiveLookingWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}
#endif
