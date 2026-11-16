/// macOS's "Require password after screen saver begins or display is turned off" setting.
///
/// thumbs-out's own lid-close lock is immediate, but when the Mac sleeps normally this delay applies:
/// opening the lid within it skips the password.
public enum ScreenLockDelay: Sendable, Equatable {
    case immediate
    case seconds(Int)
    /// "Never": waking doesn't ask for the password at all.
    case off

    /// Reads what `sysadminctl -screenLock status` prints to stderr. Nil for anything unrecognised.
    public init?(sysadminctlOutput output: String) {
        for line in output.split(whereSeparator: \.isNewline) {
            if line.hasSuffix("screenLock is off") {
                self = .off
                return
            }
            if line.hasSuffix("screenLock delay is immediate") {
                self = .immediate
                return
            }
            if let match = line.firstMatch(of: /screenLock delay is (\d+) seconds$/), let seconds = Int(match.1) {
                self = seconds == 0 ? .immediate : .seconds(seconds)
                return
            }
        }
        return nil
    }

    public var isImmediate: Bool { self == .immediate }

    /// "immediately", "5 minutes", "off".
    public var label: String {
        switch self {
        case .immediate: "immediately"
        case .off: "off"
        case .seconds(let seconds) where seconds % 3600 == 0: Self.count(seconds / 3600, "hour")
        case .seconds(let seconds) where seconds % 60 == 0: Self.count(seconds / 60, "minute")
        case .seconds(let seconds): Self.count(seconds, "second")
        }
    }

    private static func count(_ value: Int, _ unit: String) -> String {
        "\(value) \(unit)\(value == 1 ? "" : "s")"
    }
}
