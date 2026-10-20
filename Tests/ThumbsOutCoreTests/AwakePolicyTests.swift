import Foundation
import Testing
@testable import ThumbsOutCore

@Suite("Awake policy")
struct AwakePolicyTests {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let fiveMinutes: TimeInterval = 300

    func decide(
        active: [Agent] = [],
        lastActivity: Date? = nil,
        manual: ManualSession? = nil,
        autoEnabled: Bool = true
    ) -> AwakeDecision {
        AwakePolicy.decide(
            now: now, activeAgents: active, lastActivity: lastActivity,
            gracePeriod: fiveMinutes, manual: manual, isAutoEnabled: autoEnabled
        )
    }

    @Test("allows sleep when nothing is going on")
    func idle() {
        #expect(decide() == .sleepAllowed)
        #expect(decide().keepsAwake == false)
    }

    @Test("keeps awake while agents run commands")
    func agentsActive() {
        let decision = decide(active: [.claudeCode, .antigravity])
        #expect(decision == .agentsActive([.claudeCode, .antigravity]))
        #expect(decision.keepsAwake)
    }

    @Test("keeps awake through the grace period after the last command")
    func gracePeriod() {
        let last = now.addingTimeInterval(-60)
        #expect(decide(lastActivity: last) == .gracePeriod(until: last.addingTimeInterval(fiveMinutes)))
    }

    @Test("allows sleep once the grace period has passed")
    func graceExpired() {
        #expect(decide(lastActivity: now.addingTimeInterval(-fiveMinutes - 1)) == .sleepAllowed)
    }

    @Test("ignores agents when automatic mode is off")
    func autoDisabled() {
        #expect(decide(active: [.chatGPT], lastActivity: now, autoEnabled: false) == .sleepAllowed)
    }

    @Test("manual sessions keep awake even with automatic mode off")
    func manualIndefinite() {
        #expect(decide(manual: .indefinite, autoEnabled: false) == .manual(until: nil))
    }

    @Test("timed manual session keeps awake until it ends")
    func manualTimed() {
        let end = now.addingTimeInterval(600)
        #expect(decide(manual: .until(end)) == .manual(until: end))
        #expect(decide(manual: .until(now.addingTimeInterval(-1))) == .sleepAllowed)
    }

    @Test("active agents take precedence over a manual session in the status")
    func agentsBeatManual() {
        #expect(decide(active: [.claudeCode], manual: .indefinite) == .agentsActive([.claudeCode]))
    }

    @Test("manual session takes precedence over the grace period")
    func manualBeatsGrace() {
        #expect(decide(lastActivity: now, manual: .indefinite) == .manual(until: nil))
    }

    @Test("manual session expiry is detected")
    func manualExpiry() {
        #expect(ManualSession.until(now).isExpired(at: now))
        #expect(ManualSession.until(now.addingTimeInterval(1)).isExpired(at: now) == false)
        #expect(ManualSession.indefinite.isExpired(at: now) == false)
    }
}
