@testable import ThumbsOutCore

/// Small builders so each test reads like a process tree.
enum Fixtures {
    static let launchd = ProcessRecord(pid: 1, ppid: 0, path: "/sbin/launchd", arguments: ["/sbin/launchd"])

    static func process(_ pid: Int32, parent: Int32, _ path: String, _ args: String...) -> ProcessRecord {
        ProcessRecord(pid: pid, ppid: parent, path: path, arguments: [path] + args)
    }

    // The standalone installer symlinks ~/.local/bin/claude to a file named after the version.
    static let claudeCLIPath = "/Users/me/.local/share/claude/versions/2.1.72"
    static let claudeBundledPath =
        "/Users/me/Library/Application Support/Claude/claude-code/2.1.299/abc/claude.app/Contents/MacOS/claude"
    static let antigravityPath = "/Applications/Antigravity.app/Contents/MacOS/Antigravity"
    static let antigravityHelperPath =
        "/Applications/Antigravity.app/Contents/Frameworks/Antigravity Helper.app/Contents/MacOS/Antigravity Helper"
    static let chatGPTPath = "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT"
}
