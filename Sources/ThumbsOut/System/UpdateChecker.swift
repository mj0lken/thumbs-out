import Foundation
import Observation
import os
import ThumbsOutCore

/// Asks GitHub once a day whether a newer release exists. It only tells; installing is up to the
/// user (the release page, or `brew upgrade` for Homebrew installs).
@MainActor
@Observable
final class UpdateChecker {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(LatestRelease)
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var lastCheck: Date?

    /// Nil in debug builds, which aren't app bundles: those never check.
    let currentVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
    let isHomebrewInstall = ["/opt/homebrew/Caskroom/thumbs-out", "/usr/local/Caskroom/thumbs-out"]
        .contains { FileManager.default.fileExists(atPath: $0) }

    static let homebrewCommand = "brew upgrade --cask thumbs-out"

    var availableUpdate: LatestRelease? {
        if case .available(let release) = state { release } else { nil }
    }

    @ObservationIgnored private var loop: Task<Void, Never>?
    private static let log = Logger(subsystem: "com.mj0lken.thumbs-out", category: "updates")
    private nonisolated static let endpoint = URL(string: "https://api.github.com/repos/mj0lken/thumbs-out/releases/latest")!
    private static let lastCheckKey = "lastUpdateCheck"
    private static let latestTagKey = "latestReleaseTag"
    private static let latestPageKey = "latestReleasePage"
    /// How often to see whether a daily check is due; cheap, no network unless it is.
    private static let wakeInterval: Duration = .seconds(60 * 60)
    /// Leaves launch to the rest of the app before going to the network.
    private static let launchDelay: Duration = .seconds(20)

    init() {
        let defaults = UserDefaults.standard
        lastCheck = defaults.object(forKey: Self.lastCheckKey) as? Date
        // Keep showing a release found earlier, until it's installed or a newer check says otherwise.
        if let tag = defaults.string(forKey: Self.latestTagKey).flatMap(AppVersion.init),
           let page = defaults.url(forKey: Self.latestPageKey),
           let update = UpdateCheck.availableUpdate(current: currentVersion, latest: LatestRelease(version: tag, pageURL: page)) {
            state = .available(update)
        }
    }

    #if DEBUG
    /// Snapshots: show a found update without touching the network or the user's defaults.
    init(previewing release: LatestRelease) {
        state = .available(release)
    }
    #endif

    func start() {
        guard loop == nil, currentVersion != nil else { return }
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
    }

    /// The Settings button: checks now, whatever the schedule and the automatic setting say.
    func checkNow() async {
        guard state != .checking else { return }
        guard let currentVersion else {
            state = .failed("This build has no version number to compare.")
            return
        }
        state = .checking
        do {
            let latest = try await Self.fetchLatest(currentVersion: currentVersion)
            record(latest, at: Date())
            state = UpdateCheck.availableUpdate(current: currentVersion, latest: latest).map(State.available) ?? .upToDate
        } catch {
            Self.log.error("Update check failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(Self.describe(error))
        }
    }

    private func checkIfDue() async {
        guard UserDefaults.standard.bool(forKey: SettingsKey.checksForUpdates),
              UpdateCheck.isDue(lastCheck: lastCheck, now: Date())
        else { return }
        await checkNow()
    }

    private func record(_ latest: LatestRelease, at date: Date) {
        lastCheck = date
        let defaults = UserDefaults.standard
        defaults.set(date, forKey: Self.lastCheckKey)
        defaults.set(latest.version.description, forKey: Self.latestTagKey)
        defaults.set(latest.pageURL, forKey: Self.latestPageKey)
    }

    private nonisolated static func fetchLatest(currentVersion: AppVersion) async throws -> LatestRelease {
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("thumbs-out/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, status == 200 else {
            throw UpdateError.badStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(LatestRelease.self, from: data)
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
