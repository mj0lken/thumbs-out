import AppKit
import Foundation
import Observation
import os
import ThumbsOutCore

/// Checks GitHub every 30 minutes (and on wake) using conditional ETag requests. Any writable
/// `.app` bundle (including Homebrew installs paired with `auto_updates true`) can download,
/// verify, and install in place via `installer`.
@MainActor
@Observable
final class UpdateChecker {
    /// What the latest check is doing or did. A found release is kept separately, so a check that's
    /// running or failed doesn't hide it.
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var lastCheck: Date?
    /// The newest release seen that's newer than this build; kept until a successful check says otherwise.
    private(set) var availableUpdate: LatestRelease?

    let installer = UpdateInstaller()

    /// Nil in debug builds, which aren't app bundles: those never check.
    let currentVersion: AppVersion?
    let isHomebrewInstall: Bool

    #if DEBUG
    private let canSelfUpdateOverride: Bool?
    #endif

    var canSelfUpdate: Bool {
        #if DEBUG
        if let canSelfUpdateOverride { return canSelfUpdateOverride }
        #endif
        return UpdateInstaller.canSelfUpdate()
    }

    static let homebrewCommand = "brew upgrade --cask thumbs-out"

    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var cachedLatest: LatestRelease?

    private static let log = Logger(subsystem: "com.mj0lken.thumbs-out", category: "updates")
    private nonisolated static let endpoint = URL(string: "https://api.github.com/repos/mj0lken/thumbs-out/releases/latest")!
    private static let lastCheckKey = "lastUpdateCheck"
    private static let latestTagKey = "latestReleaseTag"
    private static let latestPageKey = "latestReleasePage"
    private static let latestAssetURLKey = "latestReleaseAssetURL"
    private static let latestSHA256Key = "latestReleaseSHA256"
    private static let latestChecksumURLKey = "latestReleaseChecksumURL"
    private static let lastETagKey = "lastReleaseETag"
    /// How often the timer wakes to see whether a check is due.
    private static let wakeInterval: Duration = .seconds(30 * 60)
    /// Leaves launch to the rest of the app before going to the network.
    private static let launchDelay: Duration = .seconds(5)

    init() {
        currentVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
        isHomebrewInstall = UpdateCheck.detectHomebrewInstall(bundleURL: Bundle.main.bundleURL)
        #if DEBUG
        canSelfUpdateOverride = nil
        #endif

        let defaults = UserDefaults.standard
        lastCheck = defaults.object(forKey: Self.lastCheckKey) as? Date
        // Keep showing a release found earlier, until it's installed or a newer check says otherwise.
        if let tag = defaults.string(forKey: Self.latestTagKey).flatMap(AppVersion.init),
           let page = defaults.url(forKey: Self.latestPageKey), LatestRelease.isTrustedPage(page) {
            let asset: LatestRelease.Asset?
            if let assetURL = defaults.url(forKey: Self.latestAssetURLKey),
               LatestRelease.isTrustedDownload(assetURL) {
                let rawSHA = defaults.string(forKey: Self.latestSHA256Key)?.lowercased()
                let sha = rawSHA.flatMap { UpdateCheck.isValidSHA256($0) ? $0 : nil }
                let checksumURL = defaults.url(forKey: Self.latestChecksumURLKey)
                    .flatMap { LatestRelease.isTrustedDownload($0) ? $0 : nil }
                asset = LatestRelease.Asset(downloadURL: assetURL, sha256: sha, checksumURL: checksumURL)
            } else {
                asset = nil
            }
            let cached = LatestRelease(version: tag, pageURL: page, asset: asset)
            cachedLatest = cached
            availableUpdate = UpdateCheck.availableUpdate(current: currentVersion, latest: cached)
        }
    }

    #if DEBUG
    /// Snapshots: show a found update without touching the network or the user's defaults.
    init(previewing release: LatestRelease, canSelfUpdate: Bool = false) {
        currentVersion = nil
        isHomebrewInstall = false
        canSelfUpdateOverride = canSelfUpdate
        availableUpdate = release
    }
    #endif

    func start() {
        guard loop == nil, currentVersion != nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkIfDue()
            }
        }
        loop = Task { [weak self] in
            try? await Task.sleep(for: Self.launchDelay)
            while !Task.isCancelled {
                await self?.checkIfDue()
                try? await Task.sleep(for: Self.wakeInterval)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    /// Checks now, whatever the schedule and the automatic setting say. Uses conditional ETag when possible.
    @discardableResult
    func checkNow() async -> LatestRelease? {
        guard status != .checking else { return availableUpdate }
        installer.clearFailure()
        guard let currentVersion else {
            status = .failed("This build has no version number to compare.")
            return nil
        }
        status = .checking
        let defaults = UserDefaults.standard
        // Only send ETag when cached metadata already includes the downloadable asset (or we're up to date).
        let canUseETag = cachedLatest != nil && (availableUpdate == nil || availableUpdate?.asset != nil)
        let etag = canUseETag ? defaults.string(forKey: Self.lastETagKey) : nil
        do {
            let now = Date()
            switch try await Self.fetchLatest(currentVersion: currentVersion, etag: etag) {
            case .notModified:
                lastCheck = now
                defaults.set(now, forKey: Self.lastCheckKey)
                availableUpdate = UpdateCheck.availableUpdate(current: currentVersion, latest: cachedLatest)
                status = availableUpdate == nil ? .upToDate : .idle
                return availableUpdate
            case .fetched(let latest, let newETag):
                record(latest, etag: newETag, at: now)
                cachedLatest = latest
                availableUpdate = UpdateCheck.availableUpdate(current: currentVersion, latest: latest)
                status = availableUpdate == nil ? .upToDate : .idle
                return availableUpdate
            }
        } catch {
            // Not recorded as a check, so the next wake tries again; a release found earlier stays.
            Self.log.error("Update check failed: \(error.localizedDescription, privacy: .public)")
            status = .failed(Self.describe(error))
            return nil
        }
    }

    /// Installs the available update, refreshing metadata first if restored from UserDefaults without an asset.
    func installAvailableUpdate() async {
        guard !installer.isBusy, status != .checking else { return }
        var release = availableUpdate
        if release?.asset == nil {
            release = await checkNow()
        }
        guard let release else {
            if case .failed(let message) = status {
                installer.fail("Couldn't fetch update details: \(message)")
            }
            return
        }
        await installer.install(release, userAgentVersion: currentVersion)
    }

    func checkIfDue() async {
        guard UserDefaults.standard.bool(forKey: SettingsKey.checksForUpdates),
              UpdateCheck.isDue(lastCheck: lastCheck, now: Date())
        else { return }
        await checkNow()
    }

    private func record(_ latest: LatestRelease, etag: String?, at date: Date) {
        lastCheck = date
        let defaults = UserDefaults.standard
        defaults.set(date, forKey: Self.lastCheckKey)
        defaults.set(latest.version.description, forKey: Self.latestTagKey)
        defaults.set(latest.pageURL, forKey: Self.latestPageKey)

        if let asset = latest.asset {
            defaults.set(asset.downloadURL, forKey: Self.latestAssetURLKey)
            if let sha = asset.sha256 {
                defaults.set(sha, forKey: Self.latestSHA256Key)
            } else {
                defaults.removeObject(forKey: Self.latestSHA256Key)
            }
            if let checksumURL = asset.checksumURL {
                defaults.set(checksumURL, forKey: Self.latestChecksumURLKey)
            } else {
                defaults.removeObject(forKey: Self.latestChecksumURLKey)
            }
        } else {
            defaults.removeObject(forKey: Self.latestAssetURLKey)
            defaults.removeObject(forKey: Self.latestSHA256Key)
            defaults.removeObject(forKey: Self.latestChecksumURLKey)
        }

        if let etag, !etag.isEmpty {
            defaults.set(etag, forKey: Self.lastETagKey)
        }
    }

    private enum FetchResult: Sendable {
        case notModified
        case fetched(LatestRelease, etag: String?)
    }

    private nonisolated static func fetchLatest(currentVersion: AppVersion, etag: String?) async throws -> FetchResult {
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("thumbs-out/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        if let etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        if status == 304 {
            return .notModified
        }
        guard status == 200 else {
            throw UpdateError.badStatus(status)
        }
        let release = try JSONDecoder().decode(LatestRelease.self, from: data)
        return .fetched(release, etag: http?.value(forHTTPHeaderField: "ETag"))
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case UpdateError.badStatus(let status): "GitHub answered with status \(status)."
        case is DecodingError: "GitHub's answer didn't look like a release."
        default: error.localizedDescription
        }
    }

    private enum UpdateError: Error {
        case badStatus(Int)
    }
}
