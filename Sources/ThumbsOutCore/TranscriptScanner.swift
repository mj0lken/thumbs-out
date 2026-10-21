import Foundation

/// Where an agent keeps session transcripts: a path under the home folder in which `*` matches
/// part of one path component, like `.claude/projects/*/*.jsonl`.
public struct TranscriptPattern: Sendable, Hashable, ExpressibleByStringLiteral {
    /// The folder components, each a name or a pattern.
    let folders: [String]
    /// The file name pattern.
    let file: String

    public init(_ pattern: String) {
        let components = pattern.split(separator: "/").map(String.init)
        folders = Array(components.dropLast())
        file = components.last ?? ""
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    static func matches(_ name: String, glob: String) -> Bool {
        let parts = glob.split(separator: "*", omittingEmptySubsequences: false)
        guard let first = parts.first, let last = parts.last, parts.count > 1 else { return name == glob }
        guard name.count >= first.count + last.count, name.hasPrefix(first), name.hasSuffix(last) else { return false }
        var rest = name.dropFirst(first.count).dropLast(last.count)
        for middle in parts.dropFirst().dropLast() where !middle.isEmpty {
            guard let range = rest.range(of: middle) else { return false }
            rest = rest[range.upperBound...]
        }
        return true
    }

    /// Every folder that may hold matching transcripts.
    func folders(under home: String, list: (String) -> [FileEntry]) -> [String] {
        folders.reduce([home]) { paths, component in
            guard component.contains("*") else { return paths.map { "\($0)/\(component)" } }
            return paths.flatMap { path in
                list(path)
                    .filter { $0.isDirectory && Self.matches($0.name, glob: component) }
                    .map { "\(path)/\($0.name)" }
            }
        }
    }
}

/// One entry of a folder listing: its name and modification time, nothing more.
public struct FileEntry: Sendable, Equatable {
    public let name: String
    public let isDirectory: Bool
    public let modified: Date

    public init(name: String, isDirectory: Bool, modified: Date) {
        self.name = name
        self.isDirectory = isDirectory
        self.modified = modified
    }
}

/// Notices agents writing to their session transcripts, which Claude Code does on every message and
/// tool call, including Read, Edit and Write, which run no process. Looks only at folder listings:
/// names and modification times, never what's in the files.
///
/// Appending to a file doesn't change its folder's modification time, so the scanner remembers the
/// folders whose transcripts were written in the last hour and lists only those on each tick. Every
/// minute it lists all of them, to notice a session picked up again after a long pause.
/// Immutable: `scanning` returns an updated copy.
public struct TranscriptScanner: Sendable, Equatable {
    /// How long a folder keeps being listed every tick after a transcript in it was written.
    public static let hotWindow: TimeInterval = 60 * 60
    public static let fullScanInterval: TimeInterval = 60
    /// Older writes don't count, such as those from just before the Mac slept.
    static let maxWriteAge: TimeInterval = 2 * fullScanInterval
    /// Files dated further ahead than this are ignored rather than counted on every tick.
    static let clockSlack: TimeInterval = 60

    struct Location: Sendable, Equatable {
        let agent: Agent
        let file: String
    }

    struct HotFolder: Sendable, Equatable {
        let location: Location
        /// The newest transcript seen in it, so only a later one counts as a new write.
        let newest: Date
    }

    /// Folders listed every tick.
    private(set) var hotFolders: [String: HotFolder] = [:]
    private var lastFullScan: Date?

    public init() {}

    /// Lists the transcript folders of `agents` and returns the agents that wrote a transcript since
    /// its folder was last looked at: the previous tick for busy folders, else the last full scan.
    public func scanning(
        _ agents: Set<Agent>, home: String, now: Date, list: (String) -> [FileEntry]
    ) -> (scanner: TranscriptScanner, writers: Set<Agent>) {
        let isFullScan = lastFullScan.map { now.timeIntervalSince($0) >= Self.fullScanInterval } ?? true
        // On launch, writes from the last minute count, as they would for a folder found by a full scan.
        let lastFullLook = lastFullScan ?? now.addingTimeInterval(-Self.fullScanInterval)
        var listings: [String: [FileEntry]] = [:]
        func cachedList(_ path: String) -> [FileEntry] {
            if let listing = listings[path] { return listing }
            let listing = list(path)
            listings[path] = listing
            return listing
        }

        let locations = isFullScan
            ? allLocations(of: agents, home: home, list: cachedList)
            : hotFolders.filter { agents.contains($0.value.location.agent) }.mapValues(\.location)
        var next = self
        next.hotFolders = [:]
        var writers: Set<Agent> = []
        for (path, location) in locations {
            guard let newest = cachedList(path)
                .filter({
                    !$0.isDirectory && TranscriptPattern.matches($0.name, glob: location.file)
                        && $0.modified.timeIntervalSince(now) <= Self.clockSlack
                })
                .map(\.modified).max()
            else { continue }
            let age = now.timeIntervalSince(newest)
            if age < Self.hotWindow { next.hotFolders[path] = HotFolder(location: location, newest: newest) }
            if newest > hotFolders[path]?.newest ?? lastFullLook, age <= Self.maxWriteAge {
                writers.insert(location.agent)
            }
        }
        if isFullScan { next.lastFullScan = now }
        return (next, writers)
    }

    private func allLocations(
        of agents: Set<Agent>, home: String, list: (String) -> [FileEntry]
    ) -> [String: Location] {
        var locations: [String: Location] = [:]
        for agent in agents {
            for pattern in agent.transcripts {
                for path in pattern.folders(under: home, list: list) {
                    locations[path] = Location(agent: agent, file: pattern.file)
                }
            }
        }
        return locations
    }
}
