public struct PowerStatus: Sendable, Equatable {
    public let isOnBattery: Bool
    /// `nil` when there is no internal battery.
    public let batteryPercent: Int?

    public init(isOnBattery: Bool, batteryPercent: Int?) {
        self.isOnBattery = isOnBattery
        self.batteryPercent = batteryPercent
    }
}

public enum LidClosedDecision: Sendable, Equatable {
    case disableLidSleep
    case allowLidSleep(Reason)

    public enum Reason: Sendable, Equatable {
        case turnedOff
        case noLid
        case setupRequired
        case notNeeded
        case lowBattery(Int)
    }

    public var disablesLidSleep: Bool { self == .disableLidSleep }
}

/// Decides whether to flip the system-wide `SleepDisabled` switch so closing the lid doesn't sleep the Mac.
public enum LidClosedPolicy {
    public static func decide(
        keepsAwake: Bool,
        isEnabled: Bool,
        isSetUp: Bool,
        hasLid: Bool,
        power: PowerStatus,
        minimumBatteryPercent: Int
    ) -> LidClosedDecision {
        guard isEnabled else { return .allowLidSleep(.turnedOff) }
        guard hasLid else { return .allowLidSleep(.noLid) }
        guard isSetUp else { return .allowLidSleep(.setupRequired) }
        guard keepsAwake else { return .allowLidSleep(.notNeeded) }
        if power.isOnBattery, let percent = power.batteryPercent, percent < minimumBatteryPercent {
            return .allowLidSleep(.lowBattery(percent))
        }
        return .disableLidSleep
    }
}
