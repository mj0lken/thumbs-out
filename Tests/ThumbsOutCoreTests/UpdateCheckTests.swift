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

    @Test("then once a day")
    func daily() {
        #expect(!UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-3600), now: now))
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

    @Test("only trusts release pages on github.com")
    func rejectsForeignPage() {
        let json = Data(#"{"tag_name": "v1.2.0", "html_url": "https://example.com/thumbs-out.zip"}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(LatestRelease.self, from: json) }
    }
}
