import ThumbsOutCore
import Foundation

/// UserDefaults keys shared by the controller and the `@AppStorage` bindings in the settings UI.
enum SettingsKey {
    static let isAutoEnabled = "isAutoEnabled"
    static let keepDisplayAwake = "keepDisplayAwake"
    static let gracePeriodMinutes = "gracePeriodMinutes"
    static let pollIntervalSeconds = "pollIntervalSeconds"
    static let ignoredProcessNames = "ignoredProcessNames"
    static let isLidClosedModeEnabled = "isLidClosedModeEnabled"
    static let minimumBatteryPercent = "minimumBatteryPercent"
    static let locksScreenOnLidClose = "locksScreenOnLidClose"
    static let checksForUpdates = "checksForUpdates"

    static func watch(_ agent: Agent) -> String { "watch.\(agent.id)" }
}

/// A snapshot of the user's settings, read once per detection tick.
struct AppSettings: Equatable {
    static let pollIntervalRange = 2...60
    static let minimumBatteryChoices = [10, 20, 30, 50]

    var isAutoEnabled = true
    var keepDisplayAwake = false
    var gracePeriodMinutes = 5
    var pollIntervalSeconds = 5
    var watchedAgents = Set(Agent.allCases.filter(\.isWatchedByDefault))
    var ignoredProcessNames = ActivityDetector.defaultIgnoredProcessNames
    /// Off by default: it needs a one-time admin setup and keeps a closed Mac running.
    var isLidClosedModeEnabled = false
    var minimumBatteryPercent = 20
    /// On by default: a Mac kept awake in a bag shouldn't open to an unlocked session.
    var locksScreenOnLidClose = true

    static let defaults = AppSettings()

    static var defaultIgnoredProcessNamesText: String {
        ActivityDetector.defaultIgnoredProcessNames.sorted().joined(separator: ", ")
    }

    static func registerDefaults(in store: UserDefaults = .standard) {
        var values: [String: Any] = [
            SettingsKey.isAutoEnabled: defaults.isAutoEnabled,
            SettingsKey.keepDisplayAwake: defaults.keepDisplayAwake,
            SettingsKey.gracePeriodMinutes: defaults.gracePeriodMinutes,
            SettingsKey.pollIntervalSeconds: defaults.pollIntervalSeconds,
            SettingsKey.ignoredProcessNames: defaultIgnoredProcessNamesText,
            SettingsKey.isLidClosedModeEnabled: defaults.isLidClosedModeEnabled,
            SettingsKey.minimumBatteryPercent: defaults.minimumBatteryPercent,
            SettingsKey.locksScreenOnLidClose: defaults.locksScreenOnLidClose,
            // On by default: one request to GitHub a day, and nothing is installed without the user.
            SettingsKey.checksForUpdates: true,
        ]
        for agent in Agent.allCases {
            values[SettingsKey.watch(agent)] = agent.isWatchedByDefault
        }
        store.register(defaults: values)
    }

    static func load(from store: UserDefaults = .standard) -> AppSettings {
        AppSettings(
            isAutoEnabled: store.bool(forKey: SettingsKey.isAutoEnabled),
            keepDisplayAwake: store.bool(forKey: SettingsKey.keepDisplayAwake),
            gracePeriodMinutes: max(0, store.integer(forKey: SettingsKey.gracePeriodMinutes)),
            pollIntervalSeconds: store.integer(forKey: SettingsKey.pollIntervalSeconds)
                .clamped(to: pollIntervalRange),
            watchedAgents: Set(Agent.allCases.filter { store.bool(forKey: SettingsKey.watch($0)) }),
            ignoredProcessNames: parseNames(store.string(forKey: SettingsKey.ignoredProcessNames) ?? ""),
            isLidClosedModeEnabled: store.bool(forKey: SettingsKey.isLidClosedModeEnabled),
            minimumBatteryPercent: store.integer(forKey: SettingsKey.minimumBatteryPercent).clamped(to: 0...100),
            locksScreenOnLidClose: store.bool(forKey: SettingsKey.locksScreenOnLidClose)
        )
    }

    /// Splits a comma- or newline-separated list into trimmed, non-empty names.
    static func parseNames(_ text: String) -> Set<String> {
        Set(
            text.split(whereSeparator: { $0 == "," || $0.isNewline })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
