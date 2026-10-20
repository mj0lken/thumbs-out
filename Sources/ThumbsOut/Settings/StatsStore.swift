import Foundation
import os
import ThumbsOutCore

/// Persists `AwakeStats` as JSON in UserDefaults.
enum StatsStore {
    private static let key = "awakeStats"
    private static let log = Logger(subsystem: "com.mj0lken.thumbs-out", category: "stats")

    static func load(from store: UserDefaults = .standard) -> AwakeStats {
        guard let data = store.data(forKey: key) else { return AwakeStats() }
        do {
            return try JSONDecoder().decode(AwakeStats.self, from: data)
        } catch {
            log.error("Discarding unreadable awake stats: \(error.localizedDescription, privacy: .public)")
            return AwakeStats()
        }
    }

    static func save(_ stats: AwakeStats, to store: UserDefaults = .standard) {
        do {
            store.set(try JSONEncoder().encode(stats), forKey: key)
        } catch {
            log.error("Couldn't save awake stats: \(error.localizedDescription, privacy: .public)")
        }
    }
}
