import AppKit
import SwiftUI

@main
struct ThumbsOutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuPanel(
                controller: appDelegate.controller,
                openSettings: { appDelegate.windows.showSettings() },
                reportProblem: { appDelegate.windows.showReportProblem() }
            )
            .environment(appDelegate.updates)
        } label: {
            Image(nsImage: MenuBarGlyph.image(
                for: appDelegate.controller.decision,
                lidSleepDisabled: appDelegate.controller.lidDecision.disablesLidSleep
            ))
        }
        .menuBarExtraStyle(.window)
        // Without this the window only ever grows: when the panel gets shorter, the content and its
        // blurred background shrink to the middle and leave see-through strips above and below.
        .windowResizability(.contentSize)
    }
}

/// Owns the controller so it starts at launch and restores lid sleep on quit.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AwakeController()
    let updates = UpdateChecker()
    lazy var windows = WindowManager(controller: controller, updates: updates)

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if CommandLine.arguments.contains("--render-snapshots") {
            Task { await SnapshotRenderer.runIfRequested(controller: controller) }
            return
        }
        if CommandLine.arguments.contains("--render-site") {
            Task { await DemoRenderer.renderSiteAssets(controller: controller) }
            return
        }
        if CommandLine.arguments.contains("--render-demo") {
            Task { await DemoRenderer.runIfRequested(controller: controller) }
            return
        }
        #endif
        controller.start()
        updates.start()
        if !windows.hasCompletedOnboarding {
            windows.showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        updates.stop()
        controller.stop()
    }
}
