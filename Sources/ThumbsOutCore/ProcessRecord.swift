/// One running process, as captured in a snapshot of the process table.
public struct ProcessRecord: Sendable, Equatable {
    public let pid: Int32
    public let ppid: Int32
    /// Absolute path of the executable. May be empty if the kernel would not tell us.
    public let path: String
    /// `argv`, including `argv[0]`. May be empty for processes we are not allowed to inspect.
    public let arguments: [String]

    public init(pid: Int32, ppid: Int32, path: String, arguments: [String]) {
        self.pid = pid
        self.ppid = ppid
        self.path = path
        self.arguments = arguments
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

    private static func basename(_ source: String) -> String {
        let base = source.split(separator: "/").last.map(String.init) ?? source
        return base.hasPrefix("-") ? String(base.dropFirst()) : base
    }
}
