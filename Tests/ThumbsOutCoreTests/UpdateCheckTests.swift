import Foundation
import Testing
@testable import ThumbsOutCore

@Suite("App version")
struct AppVersionTests {
    @Test("reads plain and v-prefixed tags", arguments: ["1.2.0", "v1.2.0", " v1.2.0\n"])
    func parses(text: String) throws {
        let version = try #require(AppVersion(text))
        #expect(version.description == "1.2.0")
    }

    @Test("rejects anything that isn't a dotted number", arguments: ["", "v", "latest", "1..2", "1.2.x", "1.2.0-beta"])
    func rejects(text: String) {
        #expect(AppVersion(text) == nil)
    }

    @Test("compares numerically, not as text")
    func numericOrder() throws {
        #expect(try #require(AppVersion("1.10.0")) > #require(AppVersion("1.9.0")))
        #expect(try #require(AppVersion("2.0.0")) > #require(AppVersion("1.99.99")))
    }

    @Test("missing trailing parts count as zero")
    func trailingZeros() throws {
        #expect(try #require(AppVersion("1.2")) == #require(AppVersion("1.2.0")))
        #expect(try #require(AppVersion("1.2.1")) > #require(AppVersion("1.2")))
    }
}

@Suite("Update check")
struct UpdateCheckTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let page = URL(string: "https://github.com/mj0lken/thumbs-out/releases/tag/v1.2.0")!

    @Test("checks right away the first time")
    func firstCheck() {
        #expect(UpdateCheck.isDue(lastCheck: nil, now: now))
    }

    @Test("then every 30 minutes")
    func periodic() {
        #expect(!UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-600), now: now))
        #expect(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-UpdateCheck.interval), now: now))
    }

    @Test("a last check in the future (the clock moved back) doesn't block checks")
    func clockMovedBack() {
        #expect(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(3600), now: now))
    }

    @Test("offers a newer release")
    func newer() throws {
        let latest = LatestRelease(version: try #require(AppVersion("1.2.0")), pageURL: page)
        #expect(UpdateCheck.availableUpdate(current: AppVersion("1.1.0"), latest: latest) == latest)
    }

    @Test("stays quiet for the same or an older release")
    func sameOrOlder() throws {
        let latest = LatestRelease(version: try #require(AppVersion("1.2.0")), pageURL: page)
        #expect(UpdateCheck.availableUpdate(current: AppVersion("1.2.0"), latest: latest) == nil)
        #expect(UpdateCheck.availableUpdate(current: AppVersion("1.3.0"), latest: latest) == nil)
    }

    @Test("stays quiet without a known current version, as in a debug build")
    func unknownCurrent() throws {
        let latest = LatestRelease(version: try #require(AppVersion("1.2.0")), pageURL: page)
        #expect(UpdateCheck.availableUpdate(current: nil, latest: latest) == nil)
    }

    @Test("reads GitHub's latest-release response")
    func decodesGitHub() throws {
        let json = Data("""
        {"tag_name": "v1.2.0", "html_url": "https://github.com/mj0lken/thumbs-out/releases/tag/v1.2.0",
         "name": "thumbs-out 1.2.0", "draft": false, "prerelease": false, "assets": []}
        """.utf8)
        let release = try JSONDecoder().decode(LatestRelease.self, from: json)
        #expect(release == LatestRelease(version: try #require(AppVersion("1.2.0")), pageURL: page))
    }

    @Test("rejects a response whose tag isn't a version")
    func rejectsOddTag() {
        let json = Data(#"{"tag_name": "nightly", "html_url": "https://github.com/mj0lken/thumbs-out/releases/tag/nightly"}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(LatestRelease.self, from: json) }
    }

    @Test("trusts only https pages on github.com")
    func trustedPages() throws {
        #expect(LatestRelease.isTrustedPage(page))
        #expect(!LatestRelease.isTrustedPage(try #require(URL(string: "http://github.com/mj0lken/thumbs-out"))))
        #expect(!LatestRelease.isTrustedPage(try #require(URL(string: "https://github.com.example.com/x"))))
    }

    @Test("only trusts release pages on github.com")
    func rejectsForeignPage() {
        let json = Data(#"{"tag_name": "v1.2.0", "html_url": "https://example.com/thumbs-out.zip"}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(LatestRelease.self, from: json) }
    }
}

@Suite("Self-update")
struct SelfUpdateTests {
    let validSHA = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    let zipURL = URL(string: "https://github.com/mj0lken/thumbs-out/releases/download/v1.2.0/thumbs-out-1.2.0-arm64.zip")!
    let checksumURL = URL(string: "https://github.com/mj0lken/thumbs-out/releases/download/v1.2.0/thumbs-out-1.2.0-arm64.zip.sha256")!

    @Test("decodes release with arm64 zip, GitHub digest, and companion .sha256 asset")
    func decodesAssets() throws {
        let json = Data("""
        {
          "tag_name": "v1.2.0",
          "html_url": "https://github.com/mj0lken/thumbs-out/releases/tag/v1.2.0",
          "assets": [
            {
              "name": "thumbs-out-1.2.0-arm64.zip",
              "browser_download_url": "\(zipURL.absoluteString)",
              "digest": "sha256:\(validSHA.uppercased())"
            },
            {
              "name": "thumbs-out-1.2.0-arm64.zip.sha256",
              "browser_download_url": "\(checksumURL.absoluteString)"
            }
          ]
        }
        """.utf8)
        let release = try JSONDecoder().decode(LatestRelease.self, from: json)
        #expect(release.asset == LatestRelease.Asset(downloadURL: zipURL, sha256: validSHA, checksumURL: checksumURL))
    }

    @Test("ignores foreign download URLs and path traversal in assets")
    func rejectsUntrustedDownloads() throws {
        let foreign = try #require(URL(string: "https://example.com/mj0lken/thumbs-out/releases/download/v1.2.0/thumbs-out-1.2.0-arm64.zip"))
        let otherRepo = try #require(URL(string: "https://github.com/evil/thumbs-out/releases/download/v1.2.0/thumbs-out-1.2.0-arm64.zip"))
        let traversal = try #require(URL(string: "https://github.com/mj0lken/thumbs-out/releases/download/v1.2.0/../../other/repo/thumbs-out-1.2.0-arm64.zip"))
        let encodedTraversal = try #require(URL(string: "https://github.com/mj0lken/thumbs-out/releases/download/v1.2.0/%2e%2e/thumbs-out-1.2.0-arm64.zip"))
        let insecure = try #require(URL(string: "http://github.com/mj0lken/thumbs-out/releases/download/v1.2.0/thumbs-out-1.2.0-arm64.zip"))

        for bad in [foreign, otherRepo, traversal, encodedTraversal, insecure] {
            #expect(!LatestRelease.isTrustedDownload(bad))
            let picked = LatestRelease.pickAsset(from: [
                LatestRelease.RawAsset(name: "thumbs-out-1.2.0-arm64.zip", browserDownloadURL: bad, digest: "sha256:\(validSHA)")
            ])
            #expect(picked == nil)
        }
        #expect(LatestRelease.isTrustedDownload(zipURL))
    }

    @Test("ignores malformed digest values while keeping a valid companion checksum URL",
          arguments: ["", "md5:\(String(repeating: "a", count: 64))", "sha256:short", "sha256:\(String(repeating: "z", count: 64))"])
    func ignoresBadDigestKeepsChecksumURL(badDigest: String) {
        let picked = LatestRelease.pickAsset(from: [
            LatestRelease.RawAsset(name: "thumbs-out-1.2.0-arm64.zip", browserDownloadURL: zipURL, digest: badDigest),
            LatestRelease.RawAsset(name: "thumbs-out-1.2.0-arm64.zip.sha256", browserDownloadURL: checksumURL),
        ])
        #expect(picked == LatestRelease.Asset(downloadURL: zipURL, sha256: nil, checksumURL: checksumURL))
    }

    @Test("parses valid .sha256 checksum files")
    func parsesChecksumFile() {
        #expect(UpdateCheck.parseChecksumFile("\(validSHA)  thumbs-out-1.2.0-arm64.zip\n") == validSHA)
        #expect(UpdateCheck.parseChecksumFile("  \(validSHA.uppercased()) *thumbs-out-1.2.0-arm64.zip\r\n") == validSHA)
        #expect(UpdateCheck.parseChecksumFile(validSHA) == validSHA)
    }

    @Test("rejects malformed .sha256 checksum files",
          arguments: ["", "   \n", "not-a-hash  thumbs-out.zip", "\(String(repeating: "a", count: 63))  file.zip", "\(String(repeating: "a", count: 65))  file.zip", "\(String(repeating: "g", count: 64))  file.zip"])
    func rejectsMalformedChecksumFile(text: String) {
        #expect(UpdateCheck.parseChecksumFile(text) == nil)
    }

    @Test("evaluates self-update eligibility across install configurations")
    func canSelfUpdateTruthTable() {
        let bundleID = "com.mj0lken.thumbs-out"
        let appPath = "/Applications/thumbs-out.app"

        #expect(UpdateCheck.canSelfUpdate(
            bundlePath: appPath, bundleIdentifier: bundleID,
            expectedBundleID: bundleID, isParentWritable: true, isBundleWritable: true
        ))
        // Non-.app bundles (e.g. `swift run` debug binaries).
        #expect(!UpdateCheck.canSelfUpdate(
            bundlePath: "/Users/dev/thumbs-out/.build/debug", bundleIdentifier: bundleID,
            expectedBundleID: bundleID, isParentWritable: true, isBundleWritable: true
        ))
        // Mismatched or missing bundle identifier.
        #expect(!UpdateCheck.canSelfUpdate(
            bundlePath: appPath, bundleIdentifier: "com.example.other",
            expectedBundleID: bundleID, isParentWritable: true, isBundleWritable: true
        ))
        #expect(!UpdateCheck.canSelfUpdate(
            bundlePath: appPath, bundleIdentifier: nil,
            expectedBundleID: bundleID, isParentWritable: true, isBundleWritable: true
        ))
        // AppTranslocation paths are read-only mounts.
        #expect(!UpdateCheck.canSelfUpdate(
            bundlePath: "/private/var/folders/xx/AppTranslocation/UUID/d/thumbs-out.app",
            bundleIdentifier: bundleID, expectedBundleID: bundleID, isParentWritable: true, isBundleWritable: true
        ))
        // Non-writable parent directory or bundle.
        #expect(!UpdateCheck.canSelfUpdate(
            bundlePath: appPath, bundleIdentifier: bundleID,
            expectedBundleID: bundleID, isParentWritable: false, isBundleWritable: true
        ))
        #expect(!UpdateCheck.canSelfUpdate(
            bundlePath: appPath, bundleIdentifier: bundleID,
            expectedBundleID: bundleID, isParentWritable: true, isBundleWritable: false
        ))
    }

    @Test("detects Homebrew installs by bundle location rather than leftover Caskroom dirs")
    func detectsHomebrewInstall() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("thumbs-out-brew-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }

        let appsDir = root.appendingPathComponent("Applications", isDirectory: true)
        let caskroom = root.appendingPathComponent("Caskroom/thumbs-out", isDirectory: true)
        let localBuild = root.appendingPathComponent("build", isDirectory: true)
        try fm.createDirectory(at: appsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: caskroom.appendingPathComponent(".metadata"), withIntermediateDirectories: true)
        try fm.createDirectory(at: localBuild, withIntermediateDirectories: true)

        let installedApp = appsDir.appendingPathComponent("thumbs-out.app", isDirectory: true)
        let caskroomApp = caskroom.appendingPathComponent("1.3.0/thumbs-out.app", isDirectory: true)
        let localApp = localBuild.appendingPathComponent("thumbs-out.app", isDirectory: true)

        // Installed in Applications with Caskroom .metadata present -> Homebrew.
        #expect(UpdateCheck.detectHomebrewInstall(
            bundleURL: installedApp,
            caskroomPaths: [caskroom.path],
            applicationsDirs: [appsDir.path]
        ))
        // Launched directly from inside Caskroom -> Homebrew.
        #expect(UpdateCheck.detectHomebrewInstall(
            bundleURL: caskroomApp,
            caskroomPaths: [caskroom.path],
            applicationsDirs: [appsDir.path]
        ))
        // Local build copy is NOT Homebrew even when Caskroom exists on disk.
        #expect(!UpdateCheck.detectHomebrewInstall(
            bundleURL: localApp,
            caskroomPaths: [caskroom.path],
            applicationsDirs: [appsDir.path]
        ))
        // Without a Caskroom directory, /Applications install is NOT Homebrew.
        #expect(!UpdateCheck.detectHomebrewInstall(
            bundleURL: installedApp,
            caskroomPaths: [root.appendingPathComponent("Caskroom/missing").path],
            applicationsDirs: [appsDir.path]
        ))
    }

    @Test("computes SHA-256 of a file matching the NIST vector for \"abc\"")
    func sha256Vector() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("thumbs-out-sha-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try Data("abc".utf8).write(to: tempURL)
        let digest = try UpdateCheck.sha256(of: tempURL)
        #expect(digest == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test("install script ignores HUP, waits on PID, guards rollback on backup existence, and uses ditto and open")
    func installScriptSanity() {
        let script = UpdateCheck.installScript()
        #expect(script.hasPrefix("#!/usr/bin/env bash"))
        #expect(script.contains("trap '' HUP"))
        #expect(script.contains(#"kill -0 "$PID""#))
        #expect(script.contains(#"if [[ -e "$BACKUP" ]]; then"#))
        #expect(script.contains(#"/usr/bin/ditto "$NEW_APP" "$TARGET_APP""#))
        #expect(script.contains(#"/usr/bin/open "$TARGET_APP""#))
    }
}
