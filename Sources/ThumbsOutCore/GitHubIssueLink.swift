import Foundation

/// A link to GitHub's "new issue" page with the report filled in. Nothing is sent by opening it:
/// the user reads the issue in their browser and decides whether to submit it.
public enum GitHubIssueLink {
    public static let repository = "mj0lken/thumbs-out"
    /// GitHub answers links longer than about 8 KB with "414 URI Too Long".
    public static let maxLength = 7_500
    static let labels = ["bug"]

    public enum Fit: Sendable, Equatable {
        case complete
        /// The oldest log lines were left out so the link stays short enough.
        case trimmedLog(omitted: Int)
        /// Too long for any link: the body asks the user to paste the report from the clipboard.
        case needsPaste
    }

    /// Only unreserved characters pass through. In particular `+`, which URLComponents leaves alone
    /// but GitHub reads as a space, and `&`, `=` and `#`, which would cut the body short.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    public static func url(title: String, body: String) -> URL {
        let query = [("title", title), ("body", body), ("labels", labels.joined(separator: ","))]
            .map { name, value in "\(name)=\(value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "")" }
            .joined(separator: "&")
        // Every part is either a constant or fully percent-encoded, so this always parses.
        return URL(string: "https://github.com/\(repository)/issues/new?\(query)")!
    }

    /// The most complete link that fits: the oldest lines go first, from the log that matters less
    /// for this problem (the lid and lock events, unless it's a lid problem), then from the other.
    /// If the report alone is still too long, the body asks the user to paste it instead.
    public static func bestFit(for report: IssueReport, redactor: PrivacyRedactor) -> (url: URL, fit: Fit) {
        let clean = report.redacted(by: redactor)
        let logTotal = clean.log.count
        let lidTotal = clean.lidLog.count
        let attempts: [(log: Int, lid: Int)] = report.kind == .lidClosed
            ? stride(from: logTotal, through: 0, by: -1).map { ($0, lidTotal) }
                + stride(from: lidTotal - 1, through: 0, by: -1).map { (0, $0) }
            : stride(from: lidTotal, through: 0, by: -1).map { (logTotal, $0) }
                + stride(from: logTotal - 1, through: 0, by: -1).map { ($0, 0) }
        for kept in attempts {
            let body = clean.renderedMarkdown(logLimit: kept.log, lidLogLimit: kept.lid)
            let link = url(title: report.title, body: body)
            if link.absoluteString.count <= maxLength {
                let omitted = logTotal - kept.log + lidTotal - kept.lid
                return (link, omitted == 0 ? .complete : .trimmedLog(omitted: omitted))
            }
        }
        return (url(title: report.title, body: IssueReport.pastePlaceholder), .needsPaste)
    }
}
