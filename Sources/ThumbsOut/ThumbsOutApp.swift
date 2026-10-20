import AppKit
import SwiftUI

@main
struct ThumbsOutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuPanel(controller: appDelegate.controller) { appDelegate.windows.showSettings() }
        } label: {
            Image(systemName: StatusPresentation.symbolName(
                for: appDelegate.controller.decision,
                lidSleepDisabled: appDelegate.controller.lidDecision.disablesLidSleep
            ))
        }
        .menuBarExtraStyle(.window)
    }
}

/// Owns the controller so it starts at launch and restores lid sleep on quit.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AwakeController()
    lazy var windows = WindowManager(controller: controller)

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if CommandLine.arguments.contains("--render-snapshots") {
            Task { await SnapshotRenderer.runIfRequested(controller: controller) }
            return
        }
        #endif
        controller.start()
        if !windows.hasCompletedOnboarding {
            windows.showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }
}
