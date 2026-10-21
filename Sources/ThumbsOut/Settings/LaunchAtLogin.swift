import os
import ServiceManagement

/// Thin wrapper over SMAppService so the settings toggle reflects the real system state.
enum LaunchAtLogin {
    private static let log = Logger(subsystem: "com.mj0lken.thumbs-out", category: "login")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// The login item's state in words, for problem reports.
    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled: "on"
        case .requiresApproval: "waiting for approval in System Settings › General › Login Items"
        case .notRegistered: "off"
        case .notFound: "not found (is the app in Applications?)"
        @unknown default: "unknown"
        }
    }

    /// Registering may leave the item awaiting approval in System Settings › General › Login Items.
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Registers or unregisters the login item if needed. Returns a message for the user on failure.
    static func setEnabled(_ enabled: Bool) -> String? {
        guard enabled != isEnabled else { return nil }
        do {
            try enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            return nil
        } catch {
            log.error("Couldn't change the login item: \(error.localizedDescription, privacy: .public)")
            return "Couldn't change the login item: \(error.localizedDescription)"
        }
    }
}
