import AppKit
import SwiftUI
import ThumbsOutCore

/// A quiet nudge under "Lock the screen when the lid closes": thumbs-out's own lock is immediate,
/// but when the Mac sleeps normally, macOS's password delay applies. Shows nothing when the delay is
/// Immediately or couldn't be read. Never changes the setting: it's a security setting that needs
/// the user's password.
struct LockDelayHint: View {
    let delay: ScreenLockDelay?

    private static let lockScreenSettings = URL(string: "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension")!

    var body: some View {
        if let delay, !delay.isImmediate {
            VStack(alignment: .leading, spacing: 8) {
                Text(message(for: delay))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Lock Screen Settings…") { NSWorkspace.shared.open(Self.lockScreenSettings) }
                    .controlSize(.small)
            }
        }
    }

    private func message(for delay: ScreenLockDelay) -> String {
        let wait = delay == .off
            ? "doesn't ask for your password at all"
            : "waits \(delay.label) before asking for your password"
        return "thumbs-out locks the screen when it keeps the closed Mac awake. When the Mac sleeps normally, macOS \(wait). Requiring it “Immediately” closes that gap."
    }
}

extension View {
    /// Keeps `delay` current for a `LockDelayHint`: read when this view appears and again whenever
    /// the app becomes active, like coming back from System Settings, so the hint goes away once
    /// it's fixed. Attach it to a view that's always there; the hint itself may be empty.
    func readsScreenLockDelay(into delay: Binding<ScreenLockDelay?>) -> some View {
        task { delay.wrappedValue = await ScreenLockDelayReader.read() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                Task { delay.wrappedValue = await ScreenLockDelayReader.read() }
            }
    }
}
