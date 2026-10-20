import Testing
@testable import ThumbsOutCore

@Suite("Grace period scale")
struct GracePeriodScaleTests {
    @Test("snaps at the agreed stops")
    func stops() {
        #expect(GracePeriodScale.minutes == [0, 1, 2, 5, 10, 15, 20, 30, 60, 120, 240])
    }

    @Test("finds the nearest stop for any stored value", arguments: [
        (0, 0), (1, 1), (5, 3), (7, 3), (8, 4), (45, 7), (46, 8), (90, 8), (1000, 10), (-3, 0),
    ])
    func nearestIndex(minutes: Int, expected: Int) {
        #expect(GracePeriodScale.nearestIndex(for: minutes) == expected)
    }

    @Test("labels minutes and hours compactly", arguments: [
        (0, "0m"), (5, "5m"), (30, "30m"), (60, "1h"), (120, "2h"), (90, "1h 30m"),
    ])
    func labels(minutes: Int, expected: String) {
        #expect(GracePeriodScale.label(for: minutes) == expected)
    }

    @Test("maps minutes onto the meter between stops", arguments: [
        (0.0, 0.0), (5.0, 3.0), (7.5, 3.5), (45.0, 7.5), (240.0, 10.0), (500.0, 10.0), (-1.0, 0.0),
    ])
    func position(minutes: Double, expected: Double) {
        #expect(GracePeriodScale.position(for: minutes) == expected)
    }

    @Test("short tick labels for the meter")
    func tickLabels() {
        #expect(GracePeriodScale.minutes.map(GracePeriodScale.tickLabel)
            == ["0m", "1", "2", "5", "10", "15", "20", "30", "1h", "2h", "4h"])
    }
}
