import Foundation
import Testing
@testable import ThumbsOutCore

/// Read-only checks against the real system tools: nothing is installed or changed.
@Suite("Lid sleep helper against system tools", .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/sbin/visudo")))
struct LidSleepHelperSystemTests {
    private func run(_ path: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    @Test("visudo accepts the generated rule")
    func visudoAcceptsRule() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("thumbs-out-rule-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        try LidSleepHelper.sudoersContent(user: "malcolm").write(to: file, atomically: true, encoding: .utf8)
        #expect(try run("/usr/sbin/visudo", ["-cf", file.path]) == 0)
    }

    @Test("generated shell scripts parse", arguments: [
        try! LidSleepHelper.installScript(user: "malcolm"),
        LidSleepHelper.uninstallScript(),
        LidSleepHelper.watchdogScript(appPID: 1, executablePath: "/Applications/thumbs-out.app/Contents/MacOS/ThumbsOut"),
    ])
    func scriptsParse(script: String) throws {
        #expect(try run("/bin/sh", ["-n", "-c", script]) == 0)
    }
}
