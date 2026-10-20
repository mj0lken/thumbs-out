import Foundation

/// One running process, as captured in a snapshot of the process table.
public struct ProcessRecord: Sendable, Equatable {
    public let pid: Int32
    public let ppid: Int32
    /// Absolute path of the executable. May be empty if the kernel would not tell us.
    public let path: String
    /// `argv`, including `argv[0]`. May be empty for processes we are not allowed to inspect.
    public let arguments: [String]
    /// Total CPU time used so far, in seconds, when it could be read.
    public let cpuTime: TimeInterval?

    public init(pid: Int32, ppid: Int32, path: String, arguments: [String], cpuTime: TimeInterval? = nil) {
        self.pid = pid
        self.ppid = ppid
        self.path = path
        self.arguments = arguments
        self.cpuTime = cpuTime
    }

    /// Executable name, e.g. `zsh` for `/bin/zsh` or for a login shell reported as `-zsh`.
    public var name: String {
        Self.basename(path.isEmpty ? (arguments.first ?? "") : path)
    }

    /// Name the process was launched as (`argv[0]`). Differs from `name` when the binary is a
    /// symlink target, e.g. `claude` → `…/claude/versions/2.1.72`.
    public var launchName: String {
        Self.basename(arguments.first ?? "")
    }

    /// For script interpreters, the script being run: `gemini` for `node /opt/homebrew/bin/gemini`.
    public var scriptName: String? {
        // Framework Pythons run as `…/Python.app/Contents/MacOS/Python` with argv[0] `python3`.
        guard Self.isInterpreter(name) || Self.isInterpreter(launchName) else { return nil }
        var remaining = arguments.dropFirst().makeIterator()
        while let argument = remaining.next() {
            if argument == "-m" { return remaining.next().map { String($0.split(separator: ".").first ?? "") } }
            if Self.inlineCodeFlags.contains(argument) { return nil }
            if Self.flagsWithValues.contains(argument) { _ = remaining.next(); continue }
            if argument.hasPrefix("-") { continue }
            return Self.basename(argument)
        }
        return nil
    }

    /// Interpreter flags whose next argument is a value, not the script (`node --import ./x.mjs app.js`).
    private static let flagsWithValues: Set<String> = [
        "--import", "--require", "-r", "--loader", "--experimental-loader", "--conditions", "-C", "--title",
        "--inspect-port", "--env-file", "-W", "-X",
    ]

    /// Flags that run inline code, so there's no script file.
    private static let inlineCodeFlags: Set<String> = ["-e", "--eval", "-p", "--print", "-c"]

    private static func isInterpreter(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return ["node", "bun", "deno", "ruby", "perl"].contains(lowered) || lowered.hasPrefix("python")
    }

    private static func basename(_ source: String) -> String {
        let base = source.split(separator: "/").last.map(String.init) ?? source
        return base.hasPrefix("-") ? String(base.dropFirst()) : base
    }
}
