import Foundation

/// A release version like 1.2.0, compared part by part as numbers, so 1.10.0 is newer than 1.9.0.
public struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    /// Accepts "1.2.0" and release tags like "v1.2.0". Pre-release suffixes ("1.2.0-beta") aren't
    /// versions thumbs-out publishes, so they don't parse.
    public init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") { trimmed.removeFirst() }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        self.parts = parts.compactMap { $0 }
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        compare(lhs, rhs) == 0
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        compare(lhs, rhs) < 0
    }

    /// Missing trailing parts count as zero: 1.2 equals 1.2.0.
    private static func compare(_ lhs: AppVersion, _ rhs: AppVersion) -> Int {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right ? -1 : 1 }
        }
        return 0
    }
}

/// The latest published release, read from GitHub's `releases/latest` API (which skips drafts and
/// pre-releases).
public struct LatestRelease: Sendable, Equatable, Decodable {
    public let version: AppVersion
    /// The release page: notes and the download.
    public let pageURL: URL

    public init(version: AppVersion, pageURL: URL) {
        self.version = version
        self.pageURL = pageURL
    }

    /// The page is opened in the browser, so only links that stay on GitHub are followed.
    public static func isTrustedPage(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "github.com"
    }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(String.self, forKey: .tagName)
        guard let version = AppVersion(tag) else {
            throw DecodingError.dataCorruptedError(forKey: .tagName, in: container, debugDescription: "Not a version: \(tag)")
        }
        let page = try container.decode(URL.self, forKey: .htmlURL)
        guard Self.isTrustedPage(page) else {
            throw DecodingError.dataCorruptedError(forKey: .htmlURL, in: container, debugDescription: "Not a GitHub page: \(page)")
        }
        self.init(version: version, pageURL: page)
    }
}

/// When to look for a newer release, and whether the one found is newer than what's running.
public enum UpdateCheck {
    public static let interval: TimeInterval = 24 * 60 * 60

    public static func isDue(lastCheck: Date?, now: Date, interval: TimeInterval = interval) -> Bool {
        guard let lastCheck, lastCheck <= now else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }

    /// `current` is nil when the running build has no version (a debug build): never nag then.
    public static func availableUpdate(current: AppVersion?, latest: LatestRelease?) -> LatestRelease? {
        guard let current, let latest, latest.version > current else { return nil }
        return latest
    }
}
