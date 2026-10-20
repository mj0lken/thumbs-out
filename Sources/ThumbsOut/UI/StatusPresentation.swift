import Foundation
import ThumbsOutCore

/// Text and icons for the menu bar, derived from the controller's state.
enum StatusPresentation {
    static func symbolName(for decision: AwakeDecision, lidSleepDisabled: Bool) -> String {
        switch decision {
        case .sleepAllowed: "hand.thumbsup"
        case .gracePeriod: "hand.thumbsup.circle"
        case .agentsActive, .manual: lidSleepDisabled ? "hand.thumbsup.circle.fill" : "hand.thumbsup.fill"
        }
    }

    static func lidLine(for behavior: LidClosedBehavior) -> String {
        switch behavior {
        case .sleeps: "Off: the Mac sleeps when you close it"
        case .staysAwakeSleepDisabled(byThumbsOut: true): "On: stays awake when you close it"
        case .staysAwakeSleepDisabled(byThumbsOut: false): "Sleep is disabled by pmset or another app"
        case .staysAwakeExternalDisplay: "External display + power keeps it awake"
        }
    }

    /// Why lid-closed mode isn't active, when the user has asked for it.
    static func lidModeNote(for decision: LidClosedDecision) -> String? {
        switch decision {
        case .allowLidSleep(.lowBattery(let percent)): "Paused: battery at \(percent)%"
        case .allowLidSleep(.setupRequired): "Needs your admin password once"
        case .allowLidSleep(.noLid): "This Mac has no lid"
        default: nil
        }
    }
}
