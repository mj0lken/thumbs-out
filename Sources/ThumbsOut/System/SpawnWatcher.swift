import Darwin
import Dispatch
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

    private let queue = DispatchQueue(label: "com.mj0lken.thumbs-out.spawn", qos: .utility)
    private let kq: Int32
    private var source: DispatchSourceRead?
    private var entries: [pid_t: Entry] = [:]
    /// Processes watched since the last update, which may be newer than the snapshot it brings.
    private var adoptedSinceUpdate: Set<pid_t> = []
    private var detector = ActivityDetector()
    private var agents: Set<Agent> = []
    private var commands: [DetectedCommand] = []
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
    func update(targets: [SpawnWatchTarget], detector: ActivityDetector, watching agents: Set<Agent>) {
        queue.async { [self] in
            self.detector = detector
            self.agents = agents
            let wanted = Dictionary(targets.map { ($0.process.pid, $0) }, uniquingKeysWith: { first, _ in first })
            for (pid, entry) in entries where wanted[pid] == nil {
                guard case .spawner(let target, _) = entry else { continue }
                let isNewerThanSnapshot = adoptedSinceUpdate.contains(pid) && agents.contains(target.agent)
                if !isNewerThanSnapshot || targets.isEmpty { stopWatching(pid) }
            }
            adoptedSinceUpdate = []
            for (pid, target) in wanted {
                if case .spawner(_, let children)? = entries[pid] {
                    entries[pid] = .spawner(target, children: children)
                } else if register(pid) {
                    entries[pid] = .spawner(target, children: Set(ProcessLister.childPIDs(of: pid)))
                }
            }
        }
    }

    /// Commands that started since the last call, oldest first.
    func takeCommands() -> [DetectedCommand] {
        queue.sync {
            defer { commands = [] }
            return commands
        }
    }

    // MARK: Events

    private func drainEvents() {
        // A type annotation, since `[kevent](…)` would mean an array of the `kevent` function.
        var events: [kevent] = Array(repeating: kevent(), count: 32)
        var timeout = timespec(tv_sec: 0, tv_nsec: 0)
        while true {
            let count = kevent(kq, nil, 0, &events, Int32(events.count), &timeout)
            guard count > 0 else { return }
            events.prefix(Int(count)).forEach(handle)
        }
    }

    private func handle(_ event: kevent) {
        let pid = pid_t(event.ident)
        guard let entry = entries[pid] else { return }
        switch entry {
        case .spawner(let target, let children):
            if event.fflags & UInt32(NOTE_EXEC) != 0 {
                // Now running another program (`sandbox-exec` becoming the shell it sandboxes).
                adopt(pid, startedBy: SpawnWatchTarget(process: target.process, agent: target.agent, role: .process))
            } else if event.fflags & UInt32(NOTE_FORK) != 0 {
                let current = Set(ProcessLister.childPIDs(of: pid))
                entries[pid] = .spawner(target, children: current)
                current.subtracting(children).sorted().forEach { adopt($0, startedBy: target) }
            }
        case .awaitingExec(let parent):
            if event.fflags & UInt32(NOTE_EXEC) != 0 { adopt(pid, startedBy: parent) }
        }
        if event.fflags & UInt32(NOTE_EXIT) != 0 { stopWatching(pid) }
    }

    /// Decides what a new child of `parent` is, and watches it if commands may start under it.
    private func adopt(_ pid: pid_t, startedBy parent: SpawnWatchTarget, isRetry: Bool = false) {
        guard let child = ProcessLister.record(pid, buffer: &argumentBuffer) else { return stopWatching(pid) }
        switch detector.classify(child, startedBy: parent, watching: agents) {
        case .command(let command):
            Self.log.debug("Short command for \(command.agent.id, privacy: .public): \(command.summary)")
            commands = Array((commands + [command]).suffix(Self.maxPendingCommands))
            stopWatching(pid) // Whatever it starts belongs to the command.
        case .ignored:
            stopWatching(pid)
        case .watch(let target):
            guard register(pid) else { return }
            // It's new, so any children it already has are new too.
            let children = ProcessLister.childPIDs(of: pid)
            entries[pid] = .spawner(target, children: Set(children))
            adoptedSinceUpdate.insert(pid)
            children.forEach { adopt($0, startedBy: target) }
        case .awaitingExec:
            guard register(pid) else { return }
            entries[pid] = .awaitingExec(parent: parent)
            // It may have exec'd before the watch was in place, so the event never comes.
            if !isRetry, let now = ProcessLister.record(pid, buffer: &argumentBuffer),
               now.path != child.path || now.arguments != child.arguments {
                adopt(pid, startedBy: parent, isRetry: true)
            }
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
