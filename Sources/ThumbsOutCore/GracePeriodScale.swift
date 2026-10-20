/// The stops the grace-period meter snaps to.
public enum GracePeriodScale {
    public static let minutes = [0, 1, 2, 5, 10, 15, 20, 30, 60, 120, 240]

    /// Index of the closest stop; ties go to the shorter period.
    public static func nearestIndex(for value: Int) -> Int {
        minutes.indices.min { abs(minutes[$0] - value) < abs(minutes[$1] - value) } ?? 0
    }

    public static func label(for value: Int) -> String {
        guard value >= 60 else { return "\(max(value, 0))m" }
        let hours = value / 60
        let rest = value % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// Fractional stop index for any number of minutes, linear between neighbouring stops.
    public static func position(for value: Double) -> Double {
        guard let last = minutes.last, value > 0 else { return 0 }
        guard value < Double(last) else { return Double(minutes.count - 1) }
        let upper = minutes.firstIndex { Double($0) >= value } ?? minutes.count - 1
        let lower = max(upper - 1, 0)
        let span = Double(minutes[upper] - minutes[lower])
        return span == 0 ? Double(upper) : Double(lower) + (value - Double(minutes[lower])) / span
    }

    /// Compact labels under the meter: "0m", "1", "2", … "30", "1h", "2h".
    public static func tickLabel(for value: Int) -> String {
        if value == 0 { return "0m" }
        return value < 60 ? "\(value)" : label(for: value)
    }
}
