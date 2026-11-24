import AppKit
import Foundation
import Observation
import os
import ThumbsOutCore

/// Downloads, verifies, unpacks, and swaps in a newer `thumbs-out.app` release for direct installs.
@MainActor
@Observable
final class UpdateInstaller {
    enum Phase: Equatable {
        case idle
        case downloading(fraction: Double?)
        case verifying
        case restarting
        case failed(String)
    }

    nonisolated static let expectedBundleID = "com.mj0lken.thumbs-out"
    private static let log = Logger(subsystem: expectedBundleID, category: "updates")

    private(set) var phase: Phase = .idle

    var isBusy: Bool {
        switch phase {
        case .downloading, .verifying, .restarting: true
        case .idle, .failed: false
        }
    }

    static func canSelfUpdate() -> Bool {
        let bundleURL = Bundle.main.bundleURL
        let parentURL = bundleURL.deletingLastPathComponent()
        let fm = FileManager.default
        return UpdateCheck.canSelfUpdate(
            bundlePath: bundleURL.path,
            bundleIdentifier: Bundle.main.bundleIdentifier,
            expectedBundleID: expectedBundleID,
            isParentWritable: fm.isWritableFile(atPath: parentURL.path),
            isBundleWritable: fm.isWritableFile(atPath: bundleURL.path)
        )
    }

    func fail(_ message: String) {
        phase = .failed(message)
    }

    func clearFailure() {
        if case .failed = phase {
            phase = .idle
        }
    }

    func install(_ release: LatestRelease, userAgentVersion: AppVersion?) async {
        guard !isBusy else { return }
        guard let asset = release.asset else {
            phase = .failed("This release has no macOS archive to install.")
            return
        }

        let userAgent = "thumbs-out/\(userAgentVersion?.description ?? "0")"
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("thumbs-out-update-\(UUID().uuidString)", isDirectory: true)
        var handedOff = false
        defer {
            if !handedOff {
                try? FileManager.default.removeItem(at: workDir)
            }
        }

        phase = .downloading(fraction: nil)
        do {
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

            let expectedSHA = try await Self.resolveExpectedSHA256(for: asset, userAgent: userAgent)

            let zipURL = workDir.appendingPathComponent("update.zip")
            try await Self.download(from: asset.downloadURL, to: zipURL, userAgent: userAgent) { [weak self] fraction in
                guard let self, case .downloading = self.phase else { return }
                self.phase = .downloading(fraction: fraction)
            }

            phase = .verifying

            let actualSHA = try await Task.detached(priority: .userInitiated) {
                try UpdateCheck.sha256(of: zipURL)
            }.value
            guard actualSHA == expectedSHA else {
                throw InstallError.checksumMismatch
            }

            let unpackDir = workDir.appendingPathComponent("unpacked", isDirectory: true)
            try FileManager.default.createDirectory(at: unpackDir, withIntermediateDirectories: true)
            let unpack = await CommandRunner.run("/usr/bin/ditto", ["-x", "-k", zipURL.path, unpackDir.path])
            guard unpack.succeeded else {
                throw InstallError.unpackFailed(unpack.errorOutput)
            }

            let appURL = unpackDir.appendingPathComponent("thumbs-out.app")
            try Self.validateAppBundle(at: appURL, expectedVersion: release.version)

            let codesign = await CommandRunner.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", appURL.path])
            guard codesign.succeeded else {
                throw InstallError.invalidSignature(codesign.errorOutput)
            }

            // Best-effort: clears Gatekeeper quarantine so the ad-hoc signed relaunch opens smoothly.
            _ = await CommandRunner.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", appURL.path])

            phase = .restarting

            let scriptURL = workDir.appendingPathComponent("install.sh")
            try UpdateCheck.installScript().write(to: scriptURL, atomically: true, encoding: .utf8)

            let helper = Process()
            helper.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
            helper.arguments = [
                "/bin/bash",
                scriptURL.path,
                String(ProcessInfo.processInfo.processIdentifier),
                appURL.path,
                Bundle.main.bundleURL.path,
            ]
            helper.standardInput = FileHandle.nullDevice
            helper.standardOutput = FileHandle.nullDevice
            helper.standardError = FileHandle.nullDevice
            try helper.run()
            handedOff = true

            NSApp.terminate(nil)
        } catch {
            Self.log.error("Update install failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed(Self.describe(error))
        }
    }

    private nonisolated static func resolveExpectedSHA256(
        for asset: LatestRelease.Asset,
        userAgent: String
    ) async throws -> String {
        if let sha256 = asset.sha256 {
            return sha256
        }
        guard let checksumURL = asset.checksumURL else {
            throw InstallError.missingChecksum
        }
        var request = URLRequest(url: checksumURL, timeoutInterval: 30)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw InstallError.checksumFetchFailed(status)
        }
        guard let text = String(data: data, encoding: .utf8),
              let sha256 = UpdateCheck.parseChecksumFile(text)
        else {
            throw InstallError.missingChecksum
        }
        return sha256
    }

    private nonisolated static func download(
        from url: URL,
        to destination: URL,
        userAgent: String,
        onProgress: @MainActor @Sendable @escaping (Double?) -> Void
    ) async throws {
        var request = URLRequest(url: url, timeoutInterval: 300)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        var observation: NSKeyValueObservation?
        defer { observation?.invalidate() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let task = URLSession.shared.downloadTask(with: request) { tempURL, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200, let tempURL else {
                    continuation.resume(throwing: InstallError.downloadFailed(status))
                    return
                }
                do {
                    try FileManager.default.moveItem(at: tempURL, to: destination)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            observation = task.progress.observe(\.fractionCompleted, options: [.new]) { progress, _ in
                let fraction: Double? = progress.totalUnitCount > 0 ? progress.fractionCompleted : nil
                Task { @MainActor in onProgress(fraction) }
            }
            task.resume()
        }
    }

    private nonisolated static func validateAppBundle(at appURL: URL, expectedVersion: AppVersion) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: appURL.path), let bundle = Bundle(url: appURL) else {
            throw InstallError.invalidBundle("The downloaded archive didn't contain thumbs-out.app.")
        }
        guard bundle.bundleIdentifier == expectedBundleID else {
            throw InstallError.invalidBundle("The downloaded app has an unexpected bundle identifier.")
        }
        let versionText = bundle.infoDictionary?["CFBundleShortVersionString"] as? String
        guard let unpackedVersion = versionText.flatMap(AppVersion.init), unpackedVersion == expectedVersion else {
            throw InstallError.invalidBundle("The downloaded app version didn't match \(expectedVersion.description).")
        }
        let executableURL = appURL.appendingPathComponent("Contents/MacOS/ThumbsOut")
        guard fm.isExecutableFile(atPath: executableURL.path) else {
            throw InstallError.invalidBundle("The downloaded app is missing its executable.")
        }
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case InstallError.missingChecksum:
            "This release has no SHA-256 checksum to verify."
        case InstallError.checksumFetchFailed(let status):
            "Couldn't fetch the checksum (HTTP \(status))."
        case InstallError.downloadFailed(let status):
            "Couldn't download the update (HTTP \(status))."
        case InstallError.checksumMismatch:
            "The download didn't match its SHA-256 checksum."
        case InstallError.unpackFailed:
            "Couldn't unpack the downloaded archive."
        case InstallError.invalidBundle(let reason):
            reason
        case InstallError.invalidSignature:
            "The downloaded app failed signature verification."
        default:
            error.localizedDescription
        }
    }

    private enum InstallError: Error {
        case missingChecksum
        case checksumFetchFailed(Int)
        case downloadFailed(Int)
        case checksumMismatch
        case unpackFailed(String)
        case invalidBundle(String)
        case invalidSignature(String)
    }
}
