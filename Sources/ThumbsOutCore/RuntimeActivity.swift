import Foundation

/// CPU time per process at one moment, to measure usage between two detection ticks.
public struct CPUSample: Sendable, Equatable {
    public let uptime: TimeInterval
    public let cpuByPID: [Int32: TimeInterval]
}

/// Local model runtimes (Ollama, LM Studio) never start shells, so "busy" means CPU use:
/// a runtime is generating when its process tree used more than a threshold since the last tick.
public struct RuntimeActivityDetector: Sendable {
    /// 15% of one core: an idle runtime with a model loaded sits near zero.
    public static let defaultBusyThreshold = 0.15
    /// Shorter gaps (a settings-triggered refresh) make tiny CPU blips look like heavy use.
    static let minimumInterval: TimeInterval = 1

    public let busyThreshold: Double

    public init(busyThreshold: Double = defaultBusyThreshold) {
        self.busyThreshold = busyThreshold
    }

    public static func sample(_ snapshot: [ProcessRecord], uptime: TimeInterval) -> CPUSample {
        CPUSample(
            uptime: uptime,
            cpuByPID: Dictionary(
                snapshot.compactMap { record in record.cpuTime.map { (record.pid, $0) } },
                uniquingKeysWith: { first, _ in first }
            )
        )
    }

    public func busyRuntimes(
        in snapshot: [ProcessRecord],
        uptime: TimeInterval,
        previous: CPUSample?,
        watching agents: Set<Agent>
    ) -> [DetectedCommand] {
        guard let previous, uptime - previous.uptime >= Self.minimumInterval else { return [] }
        let elapsed = uptime - previous.uptime
        let tree = ProcessTree(snapshot)
        let runtimes = agents.filter { $0.category == .modelRuntime }

        return tree.roots(for: runtimes).compactMap { root, agent in
            let used = tree.subtree(of: root).reduce(0.0) { total, process in
                guard let now = process.cpuTime else { return total }
                // A process missing from the last sample (or a reused pid) started since then,
                // so all of its CPU time falls inside this interval.
                guard let before = previous.cpuByPID[process.pid], now >= before else { return total + now }
                return total + (now - before)
            }
            let usage = used / elapsed
            guard usage >= busyThreshold else { return nil }
            return DetectedCommand(agent: agent, pid: root.pid, summary: "Generating · \(Int((usage * 100).rounded()))% CPU")
        }
    }
}

public enum MachTime {
    /// CPU times from `proc_pidinfo` are Mach ticks, 41.67 ns each on Apple Silicon (timebase 125/3).
    /// Reading them as nanoseconds would underreport CPU 24×.
    public static func seconds(ticks: UInt64, numer: UInt32, denom: UInt32) -> TimeInterval {
        guard denom > 0 else { return 0 }
        return Double(ticks) * Double(numer) / Double(denom) / 1_000_000_000
    }
}
