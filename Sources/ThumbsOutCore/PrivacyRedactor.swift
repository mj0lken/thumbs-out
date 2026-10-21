import Foundation

/// Hides who uses this Mac in text that's about to be shared: the home folder becomes `~`, the
/// account and full name `<user>` and the host name `<host>`, wherever they show up (paths, sudo
/// errors, log lines).
public struct PrivacyRedactor: Sendable {
    public static let userPlaceholder = "<user>"
    public static let hostPlaceholder = "<host>"
    public static let elsewhere = "elsewhere (path left out)"

    private let homeDirectory: String
    /// Applied in order: the home folder first, so its path reads `~/…` rather than `/Users/<user>/…`.
    private let replacements: [(target: String, replacement: String)]

    public init(homeDirectory: String, userName: String, fullName: String = "", hostName: String = "") {
        self.homeDirectory = homeDirectory
        let shortHostName = hostName.hasSuffix(".local") ? String(hostName.dropLast(".local".count)) : hostName
        replacements = [
            (homeDirectory, "~"),
            (hostName, Self.hostPlaceholder), (shortHostName, Self.hostPlaceholder),
            (fullName, Self.userPlaceholder), (userName, Self.userPlaceholder),
        ]
    }

    public func redact(_ text: String) -> String {
        replacements.reduce(text) { result, pair in Self.replacingWord(pair.target, with: pair.replacement, in: result) }
    }

    /// Standard install folders say how something was installed. Any other folder can be personal
    /// (a client's name, a disk's name), so only the fact that it's elsewhere is reported.
    public func installLocation(_ path: String) -> String {
        let systemRoots = ["/Applications/", "/opt/homebrew/", "/usr/local/", "/usr/bin/"]
        // `~/.local`, `~/.bun`, `~/.nvm` and the like: where command-line tools install themselves.
        let homeRoots = homeDirectory.isEmpty ? [] : ["\(homeDirectory)/Applications/", "\(homeDirectory)/.", "\(homeDirectory)/go/"]
        guard (systemRoots + homeRoots).contains(where: path.hasPrefix) else { return Self.elsewhere }
        return redact(path)
    }

    /// Whole words only, ignoring case: `mal` leaves `malformed` and `/Users/malcolm` alone. A path
    /// may follow anything (`/System/Volumes/Data/Users/…`).
    private static func replacingWord(_ target: String, with replacement: String, in text: String) -> String {
        guard !target.isEmpty, target != "/" else { return text }
        let start = target.hasPrefix("/") ? "" : #"(?<!\w)"#
        let pattern = start + NSRegularExpression.escapedPattern(for: target) + #"(?!\w)"#
        // The pattern is escaped, so it always compiles.
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return text }
        return regex.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text),
            withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
        )
    }
}
