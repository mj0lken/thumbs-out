import ThumbsOutCore
import Darwin
import Foundation

/// Reads the process table through libproc and sysctl. Arguments are only read for the current
/// user's processes; others (e.g. a `sudo` child of an agent's shell) are still listed so the
/// tree stays complete.
enum ProcessLister {
    private static let zombieStatus: UInt32 = 5 // SZOMB in <sys/proc.h>

    /// Converts `proc_taskinfo` CPU times, which are Mach ticks (not nanoseconds on Apple Silicon).
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private static let pathBufferSize = 4 * Int(MAXPATHLEN) // PROC_PIDPATHINFO_MAXSIZE

    private static let argumentBufferSize: Int = {
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctl(&mib, 2, &value, &size, nil, 0) == 0, value > 0 else { return 1 << 18 }
        return Int(value)
    }()

    static func snapshot() -> [ProcessRecord] {
        // One buffer for the whole scan: KERN_ARGMAX is 1 MB, too big to allocate per process.
        var argumentBuffer = makeArgumentBuffer()
        return allPids().compactMap { record($0, buffer: &argumentBuffer, includeCPUTime: true) }
    }

    static func makeArgumentBuffer() -> [UInt8] {
        [UInt8](repeating: 0, count: argumentBufferSize)
    }

    /// One process, or `nil` once it has exited. Arguments are read into `buffer`.
    static func record(_ pid: pid_t, buffer: inout [UInt8], includeCPUTime: Bool = false) -> ProcessRecord? {
        guard let info = bsdInfo(pid), info.pbi_status != zombieStatus else { return nil }
        let isOwn = info.pbi_uid == getuid()
        return ProcessRecord(
            pid: pid,
            ppid: Int32(info.pbi_ppid),
            path: isOwn ? executablePath(pid) : "",
            arguments: isOwn ? arguments(pid, buffer: &buffer) : [],
            cpuTime: isOwn && includeCPUTime ? cpuTime(pid) : nil
        )
    }

    static func childPIDs(of pid: pid_t) -> [pid_t] {
        var capacity = 64
        while true {
            var pids = [pid_t](repeating: 0, count: capacity)
            let count = pids.withUnsafeMutableBytes { buffer in
                proc_listchildpids(pid, buffer.baseAddress, Int32(buffer.count))
            }
            guard count > 0 else { return [] }
            // A full buffer may have been cut short; ask again with room to spare.
            if count < capacity || capacity >= maxChildren { return Array(pids.prefix(Int(count))) }
            capacity *= 4
        }
    }

    private static let maxChildren = 4096

    private static func allPids() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        // Leave headroom for processes spawned between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 128)
        let count = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        return count > 0 ? Array(pids.prefix(Int(count))).filter { $0 > 0 } : []
    }

    private static func bsdInfo(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let expected = Int32(MemoryLayout<proc_bsdinfo>.size)
        let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, expected)
        return size == expected ? info : nil
    }

    private static func cpuTime(_ pid: pid_t) -> TimeInterval? {
        var info = proc_taskinfo()
        let expected = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, expected) == expected else { return nil }
        return MachTime.seconds(
            ticks: info.pti_total_user + info.pti_total_system, numer: timebase.numer, denom: timebase.denom
        )
    }

    static func executablePath(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: pathBufferSize)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "" }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// Parses KERN_PROCARGS2: `argc` (Int32), the exec path, NUL padding, then `argc` NUL-terminated strings.
    private static func arguments(_ pid: pid_t, buffer: inout [UInt8]) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = buffer.count
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }

        let argc = buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        let data = buffer[MemoryLayout<Int32>.size..<size]

        // Skip the exec path and the NULs that pad it.
        guard let pathEnd = data.firstIndex(of: 0),
              let argsStart = data[pathEnd...].firstIndex(where: { $0 != 0 })
        else { return [] }

        return data[argsStart...]
            .split(separator: 0, maxSplits: Int(max(argc, 0)), omittingEmptySubsequences: false)
            .prefix(Int(max(argc, 0)))
            .map { String(decoding: $0, as: UTF8.self) }
    }
}
