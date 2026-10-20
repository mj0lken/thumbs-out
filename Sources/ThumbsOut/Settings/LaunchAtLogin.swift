import ServiceManagement

/// Thin wrapper over SMAppService so the settings toggle reflects the real system state.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
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
            return "Couldn't change the login item: \(error.localizedDescription)"
        }
    }
}
