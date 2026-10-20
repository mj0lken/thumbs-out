import Testing
@testable import ThumbsOutCore

@Suite("Lid-closed policy")
struct LidClosedPolicyTests {
    let onPower = PowerStatus(isOnBattery: false, batteryPercent: 15)

    func decide(
        keepsAwake: Bool = true, enabled: Bool = true, setUp: Bool = true, hasLid: Bool = true,
        power: PowerStatus = PowerStatus(isOnBattery: true, batteryPercent: 80)
    ) -> LidClosedDecision {
        LidClosedPolicy.decide(
            keepsAwake: keepsAwake, isEnabled: enabled, isSetUp: setUp, hasLid: hasLid, power: power,
            minimumBatteryPercent: 20
        )
    }

    @Test("desktop Macs have no lid, so the switch is never touched")
    func noLid() {
        #expect(decide(hasLid: false) == .allowLidSleep(.noLid))
    }

    @Test("disables lid sleep while staying awake")
    func disables() {
        #expect(decide() == .disableLidSleep)
        #expect(decide().disablesLidSleep)
    }

    @Test("does nothing when the feature is off")
    func featureOff() {
        #expect(decide(enabled: false) == .allowLidSleep(.turnedOff))
    }

    @Test("needs the one-time setup")
    func needsSetup() {
        #expect(decide(setUp: false) == .allowLidSleep(.setupRequired))
    }

    @Test("lets the lid sleep the Mac once there is nothing to stay awake for")
    func notNeeded() {
        #expect(decide(keepsAwake: false) == .allowLidSleep(.notNeeded))
    }

    @Test("gives up on low battery", arguments: [19, 5, 0])
    func lowBattery(percent: Int) {
        let power = PowerStatus(isOnBattery: true, batteryPercent: percent)
        #expect(decide(power: power) == .allowLidSleep(.lowBattery(percent)))
    }

    @Test("battery level does not matter on the power adapter")
    func pluggedIn() {
        #expect(decide(power: onPower) == .disableLidSleep)
    }

    @Test("an unknown battery level (desktop Mac) does not block")
    func unknownBattery() {
        #expect(decide(power: PowerStatus(isOnBattery: true, batteryPercent: nil)) == .disableLidSleep)
    }
}
