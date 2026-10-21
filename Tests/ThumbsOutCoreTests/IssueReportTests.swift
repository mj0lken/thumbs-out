import Foundation
import Testing
@testable import ThumbsOutCore

@Suite("Privacy redactor")
struct PrivacyRedactorTests {
    let redactor = PrivacyRedactor(homeDirectory: "/Users/malcolm", userName: "malcolm")

    @Test("home folder becomes ~")
    func homeFolder() {
        #expect(redactor.redact("/Users/malcolm/.local/bin/claude") == "~/.local/bin/claude")
        #expect(redactor.redact("found at /Users/malcolm") == "found at ~")
    }

    @Test("user name becomes <user>, wherever it appears as a word")
    func userName() {
        #expect(redactor.redact("sudo: malcolm is not in the sudoers file") == "sudo: <user> is not in the sudoers file")
        #expect(redactor.redact("/Volumes/Malcolm/thumbs-out.app") == "/Volumes/<user>/thumbs-out.app")
    }

    @Test("a short user name is left alone inside longer words and paths")
    func wholeWordsOnly() {
        let short = PrivacyRedactor(homeDirectory: "/Users/mal", userName: "mal")
        #expect(short.redact("malformed reply") == "malformed reply")
        #expect(short.redact("/Users/malcolm/x") == "/Users/malcolm/x")
        #expect(short.redact("/Users/mal/x") == "~/x")
    }

    @Test("an empty home folder or user name redacts nothing")
    func empty() {
        let none = PrivacyRedactor(homeDirectory: "", userName: "")
        #expect(none.redact("/Users/malcolm/x") == "/Users/malcolm/x")
    }

    @Test("regex characters in names are matched literally")
    func literal() {
        let odd = PrivacyRedactor(homeDirectory: "/Users/a.b", userName: "a.b")
        #expect(odd.redact("/Users/a.b/x and axb") == "~/x and axb")
    }

    @Test("the home folder is found inside longer paths, like the Data volume's")
    func homeInsidePath() {
        #expect(redactor.redact("/System/Volumes/Data/Users/malcolm/x") == "/System/Volumes/Data~/x")
    }

    @Test("full name and host name are hidden too")
    func fullAndHostName() {
        let named = PrivacyRedactor(
            homeDirectory: "/Users/malcolm", userName: "malcolm", fullName: "Malcolm Horal", hostName: "Malcolms-MBP.local"
        )
        #expect(named.redact("Malcolm Horal on Malcolms-MBP.local and Malcolms-MBP") == "<user> on <host> and <host>")
    }

    @Test("install paths are shown only under standard install folders", arguments: [
        ("/Applications/Cursor.app", "/Applications/Cursor.app"),
        ("/Users/malcolm/Applications/Claude.app", "~/Applications/Claude.app"),
        ("/Users/malcolm/.local/bin/claude", "~/.local/bin/claude"),
        ("/opt/homebrew/bin/gemini", "/opt/homebrew/bin/gemini"),
        ("/usr/local/bin/ollama", "/usr/local/bin/ollama"),
        ("/Users/malcolm/Clients/Acme/Cursor.app", PrivacyRedactor.elsewhere),
        ("/Volumes/Malcolm's Disk/Cursor.app", PrivacyRedactor.elsewhere),
    ])
    func installLocation(path: String, expected: String) {
        #expect(redactor.installLocation(path) == expected)
    }
}

@Suite("Issue report")
struct IssueReportTests {
    let redactor = PrivacyRedactor(homeDirectory: "/Users/malcolm", userName: "malcolm")

    func report(summary: String = "", log: [String] = []) -> IssueReport {
        IssueReport(
            summary: summary,
            sections: [
                .init("thumbs-out", [.init("Version", "1.1.0 (2)"), .init("Location", "/Users/malcolm/Applications")]),
                .init("Setup", [.init("Last error", "sudo: malcolm\nis not allowed")]),
            ],
            log: log
        )
    }

    @Test("sections render as lists with bold labels, values redacted")
    func sections() {
        let body = report().markdown(redactor: redactor)
        #expect(body.contains("### thumbs-out\n\n- **Version:** 1.1.0 (2)\n- **Location:** ~/Applications"))
        #expect(!body.contains("malcolm"))
    }

    @Test("multi-line values are flattened onto their list item, with <user> escaped so GitHub shows it")
    func oneLine() {
        #expect(report().markdown(redactor: redactor).contains("- **Last error:** sudo: &lt;user&gt; is not allowed"))
    }

    @Test("what the user typed is kept as written")
    func summaryVerbatim() {
        let body = report(summary: "  Claude in /Users/malcolm stopped counting  ").markdown(redactor: redactor)
        #expect(body.hasPrefix("### What happened\n\nClaude in /Users/malcolm stopped counting\n\n"))
    }

    @Test("an empty summary leaves a hidden prompt for the user to fill in on GitHub")
    func placeholder() {
        #expect(report().markdown(redactor: redactor).hasPrefix("### What happened\n\n<!--"))
    }

    @Test("log lines go in a fence they can't break out of")
    func logFence() {
        let body = report(log: ["/Users/malcolm ok", "```oops"]).markdown(redactor: redactor)
        #expect(body.contains("```text\n~ ok\n'''oops\n```"))
    }

    @Test("a log limit keeps the newest lines and says how many were left out")
    func logLimit() {
        let body = report(log: ["one", "two", "three"]).markdown(redactor: redactor, logLimit: 1)
        #expect(body.contains("2 earlier lines left out"))
        #expect(body.contains("```text\nthree\n```"))
        #expect(!body.contains("two"))
    }

    @Test("a log limit of zero drops the fence entirely")
    func logLimitZero() {
        let body = report(log: ["one"]).markdown(redactor: redactor, logLimit: 0)
        #expect(body.contains("1 earlier line left out"))
        #expect(!body.contains("```"))
    }

    @Test("no log, no log section")
    func noLog() {
        #expect(!report().markdown(redactor: redactor).contains("### Log"))
    }

    @Test("the body ends by saying what was collected")
    func footer() {
        #expect(report().markdown(redactor: redactor).contains("only its own version, settings, setup, detections and log"))
    }

    @Test("redacted copies the report with every collected value cleaned, and nothing else changed")
    func redacted() {
        let clean = report(summary: "malcolm here", log: ["at /Users/malcolm"]).redacted(by: redactor)
        #expect(clean.summary == "malcolm here")
        #expect(clean.sections[0].facts[1].value == "~/Applications")
        #expect(clean.sections[1].facts[0].value == "sudo: <user> is not allowed")
        #expect(clean.log == ["at ~"])
    }

    @Test("title is the summary's first line", arguments: [
        ("Lid sleep stays off\nafter quitting", "Lid sleep stays off"),
        ("   ", IssueReport.defaultTitle),
        ("", IssueReport.defaultTitle),
    ])
    func title(summary: String, expected: String) {
        #expect(report(summary: summary).title == expected)
    }

    @Test("a picked problem names the issue, alone or in front of the summary", arguments: [
        (ProblemKind.didNotKeepAwake, "", "Mac didn't stay awake"),
        (ProblemKind.quitUnexpectedly, "After closing the lid\nmore", "Quit unexpectedly: After closing the lid"),
        (ProblemKind.other, "", IssueReport.defaultTitle),
        (ProblemKind.other, "Menu icon is blank", "Menu icon is blank"),
    ])
    func titleWithKind(kind: ProblemKind, summary: String, expected: String) {
        var report = report(summary: summary)
        report.kind = kind
        #expect(report.title == expected)
    }

    @Test("a picked problem is stated at the top of the body")
    func kindInBody() {
        var report = report(summary: "Claude was running tests")
        report.kind = .didNotKeepAwake
        #expect(report.markdown(redactor: redactor)
            .hasPrefix("### What happened\n\n**Problem:** Mac didn't stay awake\n\nClaude was running tests\n\n"))
    }

    @Test("every problem kind asks its own question")
    func prompts() {
        let prompts = ProblemKind.allCases.map(\.prompt)
        #expect(Set(prompts).count == prompts.count)
        #expect(prompts.allSatisfy { $0.hasSuffix("?") || $0.hasSuffix(".") })
    }

    @Test("long titles are shortened")
    func longTitle() {
        let title = report(summary: String(repeating: "a", count: 200)).title
        #expect(title.count == IssueReport.maxTitleLength)
        #expect(title.hasSuffix("…"))
    }
}

@Suite("Command program names")
struct CommandProgramTests {
    @Test("only the program is kept, never its arguments", arguments: [
        ("swift test --parallel", "swift"),
        ("/usr/bin/git push origin main", "git"),
        ("./scripts/build-app.sh --install", "build-app.sh"),
        ("API_KEY=secret TOKEN=x npm run deploy", "npm"),
    ])
    func program(summary: String, expected: String) {
        #expect(CommandSummary.program(of: summary) == expected)
    }

    @Test("nothing to name, rather than a fragment of a quoted value or path", arguments: [
        "", "   ", "FOO=bar",
        "PASSWORD='hunter two' make deploy",
        #"API_KEY="abc def" npm run x"#,
        #""/Users/malcolm/My Project/run.sh""#,
        "TOKEN=$(cat key) curl x",
    ])
    func none(summary: String) {
        #expect(CommandSummary.program(of: summary) == nil)
    }
}

@Suite("GitHub issue link")
struct GitHubIssueLinkTests {
    let redactor = PrivacyRedactor(homeDirectory: "/Users/me", userName: "me")

    private func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    @Test("opens the new-issue page of the thumbs-out repository, labelled as a bug")
    func destination() {
        let url = GitHubIssueLink.url(title: "Hi", body: "There")
        #expect(url.absoluteString.hasPrefix("https://github.com/mj0lken/thumbs-out/issues/new?"))
        #expect(query(url) == ["title": "Hi", "body": "There", "labels": "bug"])
    }

    @Test("every reserved character survives the round trip, including + which GitHub reads as a space")
    func encoding() {
        let body = "C++ & a=b #1 100%\nüñí 👍 ?x/y"
        let url = GitHubIssueLink.url(title: "a+b", body: body)
        #expect(!url.absoluteString.contains("+"))
        #expect(query(url)["body"] == body)
        #expect(query(url)["title"] == "a+b")
    }

    private func report(logLines: Int, factCount: Int = 3) -> IssueReport {
        IssueReport(
            summary: "Something broke",
            sections: [.init("Facts", (0..<factCount).map { .init("Fact \($0)", String(repeating: "v", count: 60)) })],
            log: (0..<logLines).map { "2026-10-20 12:00:\($0) error [lid] pmset disablesleep failed: line \($0)" }
        )
    }

    @Test("a short report fits whole")
    func complete() {
        let (url, fit) = GitHubIssueLink.bestFit(for: report(logLines: 3), redactor: redactor)
        #expect(fit == .complete)
        #expect(query(url)["body"]?.contains("line 2") == true)
    }

    @Test("a long log is trimmed from the oldest end until the link fits")
    func trimmed() {
        let (url, fit) = GitHubIssueLink.bestFit(for: report(logLines: 400), redactor: redactor)
        guard case .trimmedLog(let omitted) = fit else {
            Issue.record("expected a trimmed log, got \(fit)")
            return
        }
        #expect(omitted > 0 && omitted < 400)
        #expect(url.absoluteString.count <= GitHubIssueLink.maxLength)
        #expect(query(url)["body"]?.contains("line 399") == true)
        #expect(query(url)["body"]?.contains("line 0\n") == false)
    }

    @Test("a report too long for any link asks the user to paste it instead")
    func needsPaste() {
        let (url, fit) = GitHubIssueLink.bestFit(for: report(logLines: 0, factCount: 400), redactor: redactor)
        #expect(fit == .needsPaste)
        #expect(url.absoluteString.count <= GitHubIssueLink.maxLength)
        #expect(query(url)["body"] == IssueReport.pastePlaceholder)
        #expect(query(url)["title"] == "Something broke")
    }
}
