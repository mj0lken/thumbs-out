import AppKit
import SwiftUI

/// Opens the onboarding, settings and report windows. A menu bar app has no Dock icon or main window,
/// so these are plain AppKit windows hosting SwiftUI, brought to the front on demand.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    private static let onboardingKey = "hasCompletedOnboarding"

    private let controller: AwakeController
    private let updates: UpdateChecker
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var reportWindow: NSWindow?

    init(controller: AwakeController, updates: UpdateChecker) {
        self.controller = controller
        self.updates = updates
    }

    var hasCompletedOnboarding: Bool {
        UserDefaults.standard.bool(forKey: Self.onboardingKey)
    }

    func showOnboarding() {
        if let onboardingWindow {
            present(onboardingWindow)
            return
        }
        let view = OnboardingView(controller: controller, suggestLaunchAtLogin: !hasCompletedOnboarding) { [weak self] in
            self?.onboardingWindow?.close()
        }
        let window = makeWindow(content: view, title: "Welcome to thumbs-out")
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        onboardingWindow = window
        present(window)
    }

    func showSettings() {
        if let settingsWindow {
            present(settingsWindow)
            return
        }
        let view = SettingsView(
            controller: controller,
            showWelcome: { [weak self] in self?.showOnboarding() },
            reportProblem: { [weak self] in self?.showReportProblem() }
        )
        .environment(updates)
        let window = makeWindow(content: view, title: "thumbs-out Settings")
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 520, height: 720))
        window.setFrameAutosaveName("SettingsWindow")
        settingsWindow = window
        present(window)
    }

    /// The view refreshes its diagnostics whenever the window comes to the front, and keeps what
    /// the user typed.
    func showReportProblem() {
        if let reportWindow {
            present(reportWindow)
            return
        }
        let view = ReportProblemView(controller: controller) { [weak self] in self?.reportWindow?.close() }
        let window = makeWindow(content: view, title: "Report a Bug")
        window.styleMask = [.titled, .closable, .miniaturizable]
        reportWindow = window
        present(window)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === onboardingWindow {
            // Closing the welcome window by any route counts as done; Settings can reopen it.
            UserDefaults.standard.set(true, forKey: Self.onboardingKey)
            onboardingWindow = nil
        } else if window === settingsWindow {
            settingsWindow = nil
        } else if window === reportWindow {
            reportWindow = nil
        }
    }

    private func makeWindow(content: some View, title: String) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = title
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    private func present(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
