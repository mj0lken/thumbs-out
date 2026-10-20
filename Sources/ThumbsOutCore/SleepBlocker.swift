import Foundation

/// One power assertion as reported by `IOPMCopyAssertionsByProcess`.
public struct RawAssertion: Sendable, Equatable {
    public let pid: Int32
    public let processName: String?
    /// `AssertionTrueType` when present (it resolves deprecated aliases), else `AssertType`.
    public let type: String
    public let name: String
    /// Daemons like coreaudiod take assertions on behalf of the app actually playing audio.
    public let onBehalfOfPID: Int32?

    public init(pid: Int32, processName: String?, type: String, name: String, onBehalfOfPID: Int32?) {
        self.pid = pid
        self.processName = processName
        self.type = type
        self.name = name
        self.onBehalfOfPID = onBehalfOfPID
    }
}

/// An app that is currently keeping the Mac awake, with every reason it gave.
public struct SleepBlocker: Sendable, Equatable, Identifiable {
    public let processName: String
    public let reasons: [String]
    public let keepsDisplayOn: Bool

    public var id: String { processName }

    public init(processName: String, reasons: [String], keepsDisplayOn: Bool) {
        self.processName = processName
        self.reasons = reasons
        self.keepsDisplayOn = keepsDisplayOn
    }

    /// A readable reason for the first assertion that says something beyond the app's name.
    public var summary: String? {
        reasons.lazy.compactMap { Self.readable($0, processName: processName) }.first
    }

    private static let genericRuntimeNames: Set<String> = ["Electron", "Chromium", "WebKit"]

    private static func readable(_ reason: String, processName: String) -> String? {
        let trimmed = reason.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed == processName { return nil }
        if trimmed.hasPrefix("com.apple.audio.") { return "Playing audio" }
        if genericRuntimeNames.contains(trimmed) { return "Keeping the app active" }
        let ownPrefix = processName + ": "
        if trimmed.hasPrefix(ownPrefix) {
            let rest = trimmed.dropFirst(ownPrefix.count).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? nil : rest
        }
        return trimmed
    }
}

public enum SleepBlockers {
    static let systemSleepTypes: Set<String> = [
        "PreventUserIdleSystemSleep", "NoIdleSleepAssertion", "PreventSystemSleep",
    ]
    static let displaySleepTypes: Set<String> = ["PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion"]

    /// powerd mirrors user activity into its own assertions; listing it would only confuse.
    static let hiddenProcesses: Set<String> = ["powerd"]

    public static func from(
        _ assertions: [RawAssertion],
        excludingPIDs: Set<Int32> = [],
        nameForPID: (Int32) -> String?
    ) -> [SleepBlocker] {
        let relevant = assertions.filter { assertion in
            !excludingPIDs.contains(assertion.pid)
                && (systemSleepTypes.contains(assertion.type) || displaySleepTypes.contains(assertion.type))
                && !hiddenProcesses.contains(assertion.processName ?? "")
        }
        let grouped = Dictionary(grouping: relevant) { displayName(of: $0, nameForPID: nameForPID) }
        return grouped
            .map { name, assertions in
                SleepBlocker(
                    processName: name,
                    reasons: assertions.map(\.name),
                    keepsDisplayOn: assertions.contains { displaySleepTypes.contains($0.type) }
                )
            }
            .sorted { $0.processName.localizedCaseInsensitiveCompare($1.processName) == .orderedAscending }
    }

    private static func displayName(of assertion: RawAssertion, nameForPID: (Int32) -> String?) -> String {
        if let owner = assertion.onBehalfOfPID, let name = nameForPID(owner) { return name }
        return nameForPID(assertion.pid) ?? assertion.processName ?? "pid \(assertion.pid)"
    }
}

public enum ProcessDisplayName {
    /// The outermost `.app` bundle's name, so helpers show up as their app ("Claude Helper" → "Claude").
    public static func from(path: String) -> String {
        let components = path.split(separator: "/")
        if let bundle = components.first(where: { $0.hasSuffix(".app") }) {
            return String(bundle.dropLast(".app".count))
        }
        return components.last.map(String.init) ?? ""
    }
}

/// What will happen if the lid is closed right now.
public enum LidClosedBehavior: Sendable, Equatable {
    case sleeps
    case staysAwakeSleepDisabled(byThumbsOut: Bool)
    /// Apple's clamshell mode: power adapter plus an external display.
    case staysAwakeExternalDisplay

    public static func evaluate(clamshellCausesSleep: Bool, sleepDisabled: Bool, disabledByUs: Bool) -> Self {
        if sleepDisabled { return .staysAwakeSleepDisabled(byThumbsOut: disabledByUs) }
        return clamshellCausesSleep ? .sleeps : .staysAwakeExternalDisplay
    }
}
