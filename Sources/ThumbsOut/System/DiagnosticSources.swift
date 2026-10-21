import Darwin
import Foundation
import OSLog

/// The hardware and account facts a problem report needs. Model and chip, never the serial number
/// or host name.
struct MacFacts: Sendable {
    /// `Mac16,7`: tells a MacBook (lid, battery) from a desktop Mac.
    let model: String?
    let chip: String?
    /// The one-time lid-closed setup needs an administrator's password.
    let isAdministrator: Bool?

    static func read() -> MacFacts {
        MacFacts(
            model: sysctlString("hw.model"),
            chip: sysctlString("machdep.cpu.brand_string"),
            isAdministrator: isMemberOfAdminGroup()
        )
    }

    /// Read only so the redactor can hide it, should it ever turn up in an error message.
    static func hostName() -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXHOSTNAMELEN) + 1)
        guard gethostname(&buffer, buffer.count) == 0 else { return "" }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func isMemberOfAdminGroup() -> Bool? {
        guard let admin = getgrnam("admin")?.pointee.gr_gid else { return nil }
        var groups = [Int32](repeating: 0, count: Int(NGROUPS_MAX) * 4)
        var count = Int32(groups.count)
        guard getgrouplist(NSUserName(), Int32(bitPattern: getgid()), &groups, &count) != -1 else { return nil }
        return groups.prefix(Int(count)).contains(Int32(bitPattern: admin))
    }
}

/// thumbs-out's own log entries from this run.
enum AppLog {
    static let subsystem = "com.mj0lken.thumbs-out"

    /// Only this process's entries: older runs need the system-wide log, which takes admin rights
    /// and holds every other app's messages too.
    static func recentLines(limit: Int) -> [String] {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let entries = try store.getEntries(matching: NSPredicate(format: "subsystem == %@", subsystem))
            return entries.compactMap { $0 as? OSLogEntryLog }.suffix(limit).map(format)
        } catch {
            return ["Couldn't read thumbs-out's log: \(error.localizedDescription)"]
        }
    }

    private static func format(_ entry: OSLogEntryLog) -> String {
        // UTC, so the report doesn't give away the time zone.
        let time = entry.date.formatted(.iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false))
        return "\(time) \(levelName(entry.level)) [\(entry.category)] \(entry.composedMessage)"
    }

    private static func levelName(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .error: "error"
        case .fault: "fault"
        case .undefined: "log"
        @unknown default: "log"
        }
    }
}

/// thumbs-out's crash reports. Their contents stay on the Mac; the user can attach them by hand.
struct CrashReport: Sendable {
    let url: URL
    let date: Date

    static func find() -> [CrashReport] {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/DiagnosticReports")
        let prefix = ProcessInfo.processInfo.processName
        // No folder simply means nothing has ever crashed.
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
            .compactMap { url in
                (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    .map { CrashReport(url: url, date: $0) }
            }
            .sorted { $0.date > $1.date }
    }
}
