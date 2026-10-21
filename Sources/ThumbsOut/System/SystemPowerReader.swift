import CoreGraphics
import Foundation
import IOKit.ps
import IOKit.pwr_mgt
import ThumbsOutCore

/// Everything about the Mac's power situation that the menu and the lid-closed policy need.
struct SystemPowerState: Sendable, Equatable {
    var blockers: [SleepBlocker] = []
    /// False in Apple's clamshell mode (power + external display) or when sleep is disabled.
    var clamshellCausesSleep = true
    var sleepDisabled = false
    /// Desktop Macs (mini, Studio, iMac, Pro) have no lid, so lid-closed mode doesn't apply.
    var hasLid = true
    var power = PowerStatus(isOnBattery: false, batteryPercent: nil)
    var isLidClosed = false
    /// A display other than the built-in one is connected, even if asleep: a monitor, AirPlay or Sidecar.
    var hasExternalDisplay = false
}

enum SystemPowerReader {
    static func read() -> SystemPowerState {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        defer { if root != 0 { IOObjectRelease(root) } }
        let clamshellClosed = boolProperty("AppleClamshellState", of: root)
        return SystemPowerState(
            blockers: blockers(),
            clamshellCausesSleep: boolProperty("AppleClamshellCausesSleep", of: root) ?? true,
            sleepDisabled: boolProperty("SleepDisabled", of: root) ?? false,
            // The clamshell state is only published on Macs that have a lid. If the power domain
            // can't be read at all, assume a lid rather than hiding the controls.
            hasLid: root == 0 || clamshellClosed != nil,
            power: powerStatus(),
            isLidClosed: clamshellClosed ?? false,
            hasExternalDisplay: externalDisplayIsConnected()
        )
    }

    /// Online rather than active displays, so a docked monitor that's asleep still counts.
    private static func externalDisplayIsConnected() -> Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return false }
        return displays.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) == 0 }
    }

    private static func boolProperty(_ key: String, of entry: io_registry_entry_t) -> Bool? {
        guard entry != 0 else { return nil }
        return IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool
    }

    private static func blockers() -> [SleepBlocker] {
        var result: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&result) == kIOReturnSuccess,
              let byPID = result?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return [] }

        let assertions = byPID.flatMap { pid, entries in
            entries
                .filter { ($0["AssertLevel"] as? NSNumber)?.intValue ?? 0 > 0 }
                .map { entry in
                    RawAssertion(
                        pid: pid.int32Value,
                        processName: entry["Process Name"] as? String,
                        type: (entry["AssertionTrueType"] as? String) ?? (entry["AssertType"] as? String) ?? "",
                        name: entry["AssertName"] as? String ?? "",
                        onBehalfOfPID: (entry["AssertionOnBehalfOfPID"] as? NSNumber)?.int32Value
                    )
                }
        }
        // thumbs-out itself is shown in the menu header, not in the list.
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return SleepBlockers.from(assertions, excludingPIDs: [ownPID]) { pid in
            let name = ProcessDisplayName.from(path: ProcessLister.executablePath(pid))
            return name.isEmpty ? nil : name
        }
    }

    private static func powerStatus() -> PowerStatus {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return PowerStatus(isOnBattery: false, batteryPercent: nil)
        }
        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
        let battery = sources
            .compactMap { IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any] }
            .first { $0[kIOPSTypeKey] as? String == kIOPSInternalBatteryType }

        var percent: Int?
        if let battery,
           let current = battery[kIOPSCurrentCapacityKey] as? Int,
           let max = battery[kIOPSMaxCapacityKey] as? Int, max > 0 {
            percent = current * 100 / max
        }
        return PowerStatus(isOnBattery: providing == kIOPMBatteryPowerKey, batteryPercent: percent)
    }
}
