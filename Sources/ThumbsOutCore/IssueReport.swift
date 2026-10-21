/// The quick answers to "what went wrong?", so a report needs one click rather than a description.
public enum ProblemKind: String, CaseIterable, Sendable {
    case didNotKeepAwake, wontLetSleep, agentNotDetected, lidClosed, quitUnexpectedly, other

    public var title: String {
        switch self {
        case .didNotKeepAwake: "Mac didn't stay awake"
        case .wontLetSleep: "Mac won't sleep"
        case .agentNotDetected: "Agent not detected"
        case .lidClosed: "Lid-closed mode"
        case .quitUnexpectedly: "Quit unexpectedly"
        case .other: "Something else"
        }
    }

    /// What's most useful to add for this kind of problem.
    public var prompt: String {
        switch self {
        case .didNotKeepAwake: "Which agent was working, and roughly when did the Mac fall asleep?"
        case .wontLetSleep: "What did the menu say while the Mac stayed awake?"
        case .agentNotDetected: "Which agent, and how do you run it: app, terminal or IDE extension?"
        case .lidClosed: "What happened when you closed the lid, or while setting it up?"
        case .quitUnexpectedly: "What were you doing when it quit? Crash reports help too."
        case .other: "What did you see, and what did you expect?"
        }
    }

    /// "Something else" says nothing an issue title needs.
    var titlePrefix: String? { self == .other ? nil : title }
}

/// A problem report for a GitHub issue: what the user says happened, plus what thumbs-out knows
/// about itself on this Mac.
///
/// Collected values go through a `PrivacyRedactor` whenever the report is shown or rendered, so a
/// home folder path or the account name can't end up in a public issue. The user's own words are
/// left as written.
public struct IssueReport: Sendable, Equatable {
    public struct Fact: Sendable, Equatable {
        public let label: String
        public let value: String

        public init(_ label: String, _ value: String) {
            self.label = label
            self.value = value
        }
    }

    public struct Section: Sendable, Equatable {
        public let title: String
        public let facts: [Fact]

        public init(_ title: String, _ facts: [Fact]) {
            self.title = title
            self.facts = facts
        }
    }

    public static let defaultTitle = "Problem report"
    public static let maxTitleLength = 80
    /// Issue body for a report too long for a link: the full report goes through the clipboard.
    public static let pastePlaceholder =
        "<!-- thumbs-out copied the report to your clipboard because it was too long for a link. Paste it here with ⌘V. -->\n"

    static let summaryPlaceholder = "<!-- What did you see, and what did you expect? Steps to reproduce and screenshots help. -->"
    static let footer = "<sub>Added by thumbs-out › Report a Bug: only its own version, settings, setup, detections "
        + "and log. The home folder shows as ~ and the user name as &lt;user&gt;.</sub>"

    public var kind: ProblemKind?
    public var summary: String
    public var sections: [Section]
    /// thumbs-out's own log lines, oldest first.
    public var log: [String]

    public init(kind: ProblemKind? = nil, summary: String = "", sections: [Section], log: [String] = []) {
        self.kind = kind
        self.summary = summary
        self.sections = sections
        self.log = log
    }

    /// The picked problem and the summary's first line, shortened to fit an issue title.
    public var title: String {
        let firstLine = summary.split(whereSeparator: \.isNewline).first?.trimmingCharacters(in: .whitespaces) ?? ""
        let parts = [kind?.titlePrefix, firstLine.isEmpty ? nil : firstLine].compactMap { $0 }
        guard !parts.isEmpty else { return Self.defaultTitle }
        let title = parts.joined(separator: ": ")
        guard title.count > Self.maxTitleLength else { return title }
        return title.prefix(Self.maxTitleLength - 1) + "…"
    }

    /// A copy with every collected value redacted and flattened onto one line. What the user picked
    /// and typed is kept.
    public func redacted(by redactor: PrivacyRedactor) -> IssueReport {
        IssueReport(
            kind: kind,
            summary: summary,
            sections: sections.map { section in
                Section(section.title, section.facts.map { Fact($0.label, Self.oneLine(redactor.redact($0.value))) })
            },
            log: log.map(redactor.redact)
        )
    }

    /// The issue body. `logLimit` keeps only the newest log lines, for links that must stay short.
    public func markdown(redactor: PrivacyRedactor, logLimit: Int? = nil) -> String {
        let clean = redacted(by: redactor)
        let blocks = [clean.summaryBlock] + clean.sections.map(Self.block) + [clean.logBlock(limit: logLimit), Self.footer]
        return blocks.compactMap { $0 }.joined(separator: "\n\n") + "\n"
    }

    private var summaryBlock: String {
        let text = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let problem = kind.map { "**Problem:** \($0.title)\n\n" } ?? ""
        return "### What happened\n\n" + problem + (text.isEmpty ? Self.summaryPlaceholder : text)
    }

    private static func block(_ section: Section) -> String {
        "### \(section.title)\n\n" + section.facts.map { "- **\($0.label):** \(htmlEscaped($0.value))" }.joined(separator: "\n")
    }

    /// GitHub drops anything that looks like an HTML tag, which would swallow `<user>`.
    private static func htmlEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func logBlock(limit: Int?) -> String? {
        guard !log.isEmpty else { return nil }
        let kept = log.suffix(max(0, limit ?? log.count))
        let omitted = log.count - kept.count
        var parts = ["### Log (this run)"]
        if omitted > 0 {
            parts.append("_\(omitted) earlier \(omitted == 1 ? "line" : "lines") left out to keep the link short._")
        }
        if !kept.isEmpty {
            // A line can't close the fence early and turn the rest of the log into markdown.
            let lines = kept.map { $0.replacingOccurrences(of: "```", with: "'''") }
            parts.append("```text\n" + lines.joined(separator: "\n") + "\n```")
        }
        return parts.joined(separator: "\n\n")
    }

    private static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
