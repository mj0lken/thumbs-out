import Darwin
import Foundation
import os
import ThumbsOutCore

/// Catches commands too short for a process snapshot. Watches the processes an agent's commands
/// start under with kqueue (`EVFILT_PROC`) and looks at each new child on `NOTE_FORK`, while even
/// a millisecond `zsh -c` is still running. The detector decides what counts, so helpers such as
/// MCP servers never do.
///
/// All state lives on `queue`; the controller hands over the targets from each snapshot and
/// collects the commands seen since the last tick.
final class SpawnWatcher: @unchecked Sendable {
    private enum Entry {
        /// Watched for new children; `children` are the ones already seen.
        case spawner(SpawnWatchTarget, children: Set<pid_t>)
        /// Forked by `parent` but not yet running its own program.
        case awaitingExec(parent: SpawnWatchTarget)
    }

    private static let log = Logger(subsystem: "com.mj0lken.thumbs-out", category: "spawn")
    private static let events = UInt32(NOTE_FORK) | UInt32(NOTE_EXEC) | UInt32(NOTE_EXIT)
    /// Only the latest command per agent is shown, so a few are plenty between two ticks.
    private static let maxPendingCommands = 64
    /// Events handled per wake-up, so a burst of forks can't hold up `takeCommands` for long.
    private static let eventsPerDrain = 32

    private let queue = DispatchQueue(label: "com.mj0lken.thumbs-out.spawn", qos: .utility)
    private let kq: Int32
    private var source: DispatchSourceRead?
    private var entries: [pid_t: Entry] = [:]
    /// Processes watched since the last update, which may be newer than the snapshot it brings.
    private var adoptedSinceUpdate: Set<pid_t> = []
    private var detector = ActivityDetector()
    private var agents: Set<Agent> = []
    private var commands: [SpawnedCommand] = []
    private lazy var argumentBuffer = ProcessLister.makeArgumentBuffer()

    init() {
        kq = kqueue()
        guard kq >= 0 else {
            Self.log.error("kqueue failed: \(errno, privacy: .public)")
            return
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: kq, queue: queue)
        source.setEventHandler { [weak self] in self?.drainEvents() }
        source.setCancelHandler { [kq] in close(kq) }
        source.activate()
        self.source = source
    }

    deinit {
        source?.cancel()
    }

    /// Watches these processes from now on, plus children still waiting to exec.
    /// - Parameter snapshotPIDs: every process in the snapshot the targets come from.
    func update(
        targets: [SpawnWatchTarget], snapshotPIDs: Set<pid_t>, detector: ActivityDetector, watching agents: Set<Agent>
    ) {
        queue.async { [self] in
            self.detector = detector
            self.agents = agents
            let wanted = Dictionary(targets.map { ($0.process.pid, $0) }, uniquingKeysWith: { first, _ in first })
            for (pid, entry) in entries where wanted[pid] == nil {
                guard case .spawner(let target, _) = entry else { continue }
                // Watched since the snapshot was taken, so it couldn't be in it.
                let isNewerThanSnapshot = adoptedSinceUpdate.contains(pid) && agents.contains(target.agent)
                if !isNewerThanSnapshot || targets.isEmpty { stopWatching(pid) }
            }
            adoptedSinceUpdate = []
            for (pid, target) in wanted {
                if case .spawner(_, let children)? = entries[pid] {
                    entries[pid] = .spawner(target, children: children)
                } else if register(pid) {
                    // The snapshot's children were judged by the walk; any newer one is new.
                    let children = ProcessLister.childPIDs(of: pid)
                    entries[pid] = .spawner(target, children: Set(children).intersection(snapshotPIDs))
                    children.filter { !snapshotPIDs.contains($0) }.forEach { adopt($0, startedBy: target) }
                }
            }
        }
    }

    /// Commands that started since the last call.
    func takeCommands() -> [SpawnedCommand] {
        queue.sync {
            defer { commands = [] }
            return commands
        }
    }

    // MARK: Events

    /// Handles one batch; the source fires again while more events are waiting.
    private func drainEvents() {
        // A type annotation, since `[kevent](…)` would mean an array of the `kevent` function.
        var events: [kevent] = Array(repeating: kevent(), count: Self.eventsPerDrain)
        var timeout = timespec(tv_sec: 0, tv_nsec: 0)
        let count = kevent(kq, nil, 0, &events, Int32(events.count), &timeout)
        events.prefix(Int(max(count, 0))).forEach(handle)
    }

    /// `EV_CLEAR` folds everything since the last look into one event, so forks come first, then
    /// an exec, then the exit.
    private func handle(_ event: kevent) {
        let pid = pid_t(event.ident)
        if event.fflags & UInt32(NOTE_FORK) != 0, case .spawner(let target, let children)? = entries[pid] {
            let current = Set(ProcessLister.childPIDs(of: pid))
            entries[pid] = .spawner(target, children: current)
            current.subtracting(children).sorted().forEach { adopt($0, startedBy: target) }
        }
        if event.fflags & UInt32(NOTE_EXEC) != 0 {
            switch entries[pid] {
            case .spawner(let target, let children)?:
                // Now running another program (`sandbox-exec` becoming the shell it sandboxes).
                let before = SpawnWatchTarget(process: target.process, agent: target.agent, role: .process)
                adopt(pid, startedBy: before, knownChildren: children)
            case .awaitingExec(let parent)?:
                adopt(pid, startedBy: parent)
            case nil:
                break
            }
        }
        if event.fflags & UInt32(NOTE_EXIT) != 0 { stopWatching(pid) }
    }

    /// Decides what a new child of `parent` is, and watches it if commands may start under it.
    /// - Parameter knownChildren: its children already looked at; none for a new process.
    private func adopt(
        _ pid: pid_t, startedBy parent: SpawnWatchTarget, knownChildren: Set<pid_t> = [], isRetry: Bool = false
    ) {
        guard let child = ProcessLister.record(pid, buffer: &argumentBuffer) else { return stopWatching(pid) }
        var seen = knownChildren
        switch detector.classify(child, startedBy: parent, watching: agents) {
        case .command(let command):
            Self.log.debug("Short command for \(command.agent.id, privacy: .public): \(command.summary)")
            let spawned = SpawnedCommand(command: command, parentPID: parent.process.pid, date: Date())
            commands = Array((commands + [spawned]).suffix(Self.maxPendingCommands))
            return stopWatching(pid) // Whatever it starts belongs to the command.
        case .ignored:
            return stopWatching(pid)
        case .watch(let target):
            guard register(pid) else { return }
            let children = ProcessLister.childPIDs(of: pid)
            entries[pid] = .spawner(target, children: Set(children))
            adoptedSinceUpdate.insert(pid)
            children.filter { !seen.contains($0) }.forEach { adopt($0, startedBy: target) }
            seen.formUnion(children)
        case .awaitingExec:
            guard register(pid) else { return }
            entries[pid] = .awaitingExec(parent: parent)
        }
        // Read mid-exec, or exec'd before the watch was in place: then no event is coming.
        if !isRetry, let now = ProcessLister.record(pid, buffer: &argumentBuffer),
           now.path != child.path || now.arguments != child.arguments {
            adopt(pid, startedBy: parent, knownChildren: seen, isRetry: true)
        }
    }

    // MARK: kqueue

    private func register(_ pid: pid_t) -> Bool {
        var change = kevent(
            ident: UInt(pid), filter: Int16(EVFILT_PROC), flags: UInt16(EV_ADD | EV_CLEAR),
            fflags: Self.events, data: 0, udata: nil
        )
        return kevent(kq, &change, 1, nil, 0, nil) == 0 // Fails once the process has exited.
    }

    private func stopWatching(_ pid: pid_t) {
        adoptedSinceUpdate.remove(pid)
        guard entries.removeValue(forKey: pid) != nil else { return }
        var change = kevent(
            ident: UInt(pid), filter: Int16(EVFILT_PROC), flags: UInt16(EV_DELETE), fflags: 0, data: 0, udata: nil
        )
        _ = kevent(kq, &change, 1, nil, 0, nil) // Already gone if the process exited.
    }
}
