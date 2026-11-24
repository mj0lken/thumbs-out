import CryptoKit
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
    /// The downloadable macOS archive and its checksum metadata.
    public struct Asset: Sendable, Equatable {
        public let downloadURL: URL
        public let sha256: String?
        /// Companion `<zip>.sha256` asset, used when GitHub omits `digest`.
        public let checksumURL: URL?

        public init(downloadURL: URL, sha256: String?, checksumURL: URL? = nil) {
            self.downloadURL = downloadURL
            self.sha256 = sha256
            self.checksumURL = checksumURL
        }
    }

    /// One entry in GitHub's release `assets` array.
    public struct RawAsset: Sendable, Equatable, Decodable {
        public let name: String
        public let browserDownloadURL: URL
        public let digest: String?

        public init(name: String, browserDownloadURL: URL, digest: String? = nil) {
            self.name = name
            self.browserDownloadURL = browserDownloadURL
            self.digest = digest
        }

        private enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case digest
        }
    }

    public let version: AppVersion
    /// The release page: notes and the download.
    public let pageURL: URL
    /// Trusted arm64 zip asset for in-app updates, if present on the release.
    public let asset: Asset?

    public init(version: AppVersion, pageURL: URL, asset: Asset? = nil) {
        self.version = version
        self.pageURL = pageURL
        self.asset = asset
    }

    /// The page is opened in the browser, so only links that stay on GitHub are followed.
    public static func isTrustedPage(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "github.com"
    }

    /// Only downloads from this repository's GitHub Releases path, with no `..` traversal.
    public static func isTrustedDownload(_ url: URL) -> Bool {
        let prefix = "/mj0lken/thumbs-out/releases/download/"
        guard url.scheme == "https",
              url.host == "github.com",
              !url.pathComponents.contains(".."),
              url.path.hasPrefix(prefix),
              url.standardized.path.hasPrefix(prefix),
              url.path.count > prefix.count
        else { return false }
        return true
    }

    /// Picks the trusted `thumbs-out-*-arm64.zip` archive and optional `<zip>.sha256` companion.
    public static func pickAsset(from assets: [RawAsset]) -> Asset? {
        guard let zip = assets.first(where: {
            $0.name.hasPrefix("thumbs-out-")
                && $0.name.hasSuffix("-arm64.zip")
                && isTrustedDownload($0.browserDownloadURL)
        }) else {
            return nil
        }
        let checksumName = "\(zip.name).sha256"
        let checksumURL = assets.first(where: {
            $0.name == checksumName && isTrustedDownload($0.browserDownloadURL)
        })?.browserDownloadURL
        return Asset(
            downloadURL: zip.browserDownloadURL,
            sha256: UpdateCheck.parseDigest(zip.digest),
            checksumURL: checksumURL
        )
    }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
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
        let rawAssets = try container.decodeIfPresent([RawAsset].self, forKey: .assets) ?? []
        self.init(version: version, pageURL: page, asset: Self.pickAsset(from: rawAssets))
    }
}

/// When to look for a newer release, whether one is newer than what's running, and the pure
/// checks behind in-app self-updates.
public enum UpdateCheck {
    public static let interval: TimeInterval = 30 * 60

    public static func isDue(lastCheck: Date?, now: Date, interval: TimeInterval = interval) -> Bool {
        guard let lastCheck, lastCheck <= now else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }

    /// `current` is nil when the running build has no version (a debug build): never nag then.
    public static func availableUpdate(current: AppVersion?, latest: LatestRelease?) -> LatestRelease? {
        guard let current, let latest, latest.version > current else { return nil }
        return latest
    }

    /// Validates a 64-character lowercase/uppercase hex SHA-256 string.
    public static func isValidSHA256(_ value: String) -> Bool {
        isHexSHA256(value[...])
    }

    /// Validates a GitHub asset digest of the form `"sha256:<64 hex chars>"`.
    public static func parseDigest(_ digest: String?) -> String? {
        guard let digest, digest.hasPrefix("sha256:") else { return nil }
        let hex = digest.dropFirst("sha256:".count)
        guard isHexSHA256(hex) else { return nil }
        return hex.lowercased()
    }

    /// Extracts the leading 64-character hex digest from `shasum -a 256` output.
    public static func parseChecksumFile(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token = trimmed.split(whereSeparator: \.isWhitespace).first,
              isHexSHA256(token)
        else { return nil }
        return token.lowercased()
    }

    /// Detects whether the running app bundle is managed by Homebrew Cask rather than matching
    /// any leftover Caskroom directory on disk (e.g. when running a local `build/thumbs-out.app`).
    public static func detectHomebrewInstall(
        bundleURL: URL,
        caskroomPaths: [String] = ["/opt/homebrew/Caskroom/thumbs-out", "/usr/local/Caskroom/thumbs-out"],
        applicationsDirs: [String] = ["/Applications", (NSHomeDirectory() as NSString).appendingPathComponent("Applications")],
        fileManager: FileManager = .default
    ) -> Bool {
        let standardized = bundleURL.resolvingSymlinksInPath().standardizedFileURL
        guard standardized.pathExtension == "app" else { return false }

        let parentPath = standardized.deletingLastPathComponent().standardizedFileURL.path
        let isInApplicationsDir = applicationsDirs.contains { appDir in
            parentPath == URL(fileURLWithPath: appDir).resolvingSymlinksInPath().standardizedFileURL.path
        }

        for caskroom in caskroomPaths {
            let caskroomURL = URL(fileURLWithPath: caskroom).resolvingSymlinksInPath().standardizedFileURL
            guard fileManager.fileExists(atPath: caskroomURL.path) else { continue }

            // Direct launch from inside Caskroom
            if standardized.path.hasPrefix(caskroomURL.path + "/") {
                return true
            }

            // Standard Homebrew cask installs thumbs-out.app to /Applications and keeps Caskroom metadata
            if isInApplicationsDir {
                let metadataPath = caskroomURL.appendingPathComponent(".metadata").path
                if fileManager.fileExists(atPath: metadataPath) {
                    return true
                }
                if let entries = try? fileManager.contentsOfDirectory(at: caskroomURL, includingPropertiesForKeys: nil) {
                    for entry in entries where !entry.lastPathComponent.hasPrefix(".") {
                        let candidate = entry.appendingPathComponent(standardized.lastPathComponent)
                        if fileManager.fileExists(atPath: candidate.path),
                           candidate.resolvingSymlinksInPath().standardizedFileURL == standardized {
                            return true
                        }
                    }
                }
            }
        }
        return false
    }

    /// Any writable, non-translocated `.app` bundle with the expected bundle ID can swap itself in
    /// place (including Homebrew's `/Applications/thumbs-out.app`, paired with `auto_updates true`).
    public static func canSelfUpdate(
        bundlePath: String,
        bundleIdentifier: String?,
        expectedBundleID: String,
        isParentWritable: Bool,
        isBundleWritable: Bool
    ) -> Bool {
        guard bundlePath.hasSuffix(".app"),
              bundleIdentifier == expectedBundleID,
              !bundlePath.contains("/AppTranslocation/"),
              isParentWritable,
              isBundleWritable
        else { return false }
        return true
    }

    /// Streams a file in 1 MiB chunks through CryptoKit's SHA-256 and returns the lowercase hex digest.
    public static func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        let chunkSize = 1024 * 1024
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Detached bash helper that waits for the running app to exit, swaps the bundle with guarded
    /// rollback on failure, cleans up the staging directory, and relaunches the updated app.
    public static func installScript() -> String {
        """
        #!/usr/bin/env bash
        set -euo pipefail
        trap '' HUP

        PID="$1"
        NEW_APP="$2"
        TARGET_APP="${3%/}"
        WORK_DIR="$(cd "$(dirname "$0")" && pwd)"
        BACKUP="${TARGET_APP}.backup-$$"

        # Wait up to 30 seconds for thumbs-out to exit cleanly.
        for _ in $(seq 1 300); do
          kill -0 "$PID" 2>/dev/null || break
          sleep 0.1
        done

        # Don't swap under a live process.
        if kill -0 "$PID" 2>/dev/null; then
          rm -rf "$WORK_DIR"
          exit 1
        fi

        rollback() {
          if [[ -e "$BACKUP" ]]; then
            rm -rf "$TARGET_APP"
            mv "$BACKUP" "$TARGET_APP" || true
          fi
          rm -rf "$WORK_DIR"
        }
        trap rollback ERR

        if [[ -e "$TARGET_APP" ]]; then
          mv "$TARGET_APP" "$BACKUP"
        fi
        /usr/bin/ditto "$NEW_APP" "$TARGET_APP"
        rm -rf "$BACKUP"
        /usr/bin/open "$TARGET_APP"
        rm -rf "$WORK_DIR"
        """
    }

    private static func isHexSHA256(_ value: Substring) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isASCII && $0.isHexDigit }
    }
}
