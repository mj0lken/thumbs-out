import Foundation

/// Turns a process's arguments into a short, human-readable command for the menu.
public enum CommandSummary {
    public static let defaultMaxLength = 60

    public static func summarize(_ arguments: [String], maxLength: Int = defaultMaxLength) -> String {
        guard let first = arguments.first else { return "" }
        let record = ProcessRecord(pid: 0, ppid: 0, path: "", arguments: arguments)

        let raw: String
        if ActivityDetector.isShell(record), let script = shellScript(arguments) {
            raw = unwrapEval(script) ?? script
        } else {
            let executable = first.split(separator: "/").last.map(String.init) ?? first
            raw = ([executable] + arguments.dropFirst()).joined(separator: " ")
        }
        return truncate(collapseWhitespace(raw), to: maxLength)
    }

    /// The program a summarized command runs (`git` for `/usr/bin/git push`), for problem reports,
    /// which must not carry arguments or `KEY=value` assignments: those can hold paths and secrets.
    /// Anything quoted or expanded can't be split on spaces safely, so it gives `nil` rather than a
    /// fragment that may be half a password.
    public static func program(of summary: String) -> String? {
        for token in summary.split(whereSeparator: \.isWhitespace) {
            if isPlainAssignment(token) { continue }
            guard token.unicodeScalars.allSatisfy(programCharacters.contains) else { return nil }
            return token.split(separator: "/").last.map(String.init)
        }
        return nil
    }

    private static let programCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._+-/"
    )

    /// `NODE_ENV=production`: a name, then a value with no quotes, `$` or spaces hiding in it.
    private static func isPlainAssignment(_ token: Substring) -> Bool {
        guard let equals = token.firstIndex(of: "="), equals != token.startIndex else { return false }
        let name = token[..<equals].unicodeScalars
        let value = token[token.index(after: equals)...].unicodeScalars
        return name.allSatisfy { programCharacters.contains($0) && $0 != "/" }
            && value.allSatisfy { programCharacters.contains($0) || ":,@%=".unicodeScalars.contains($0) }
    }

    /// The script passed to `sh -c` and friends: the first non-flag argument after the `c` flag.
    static func shellScript(_ arguments: [String]) -> String? {
        guard let flagIndex = arguments.dropFirst().firstIndex(where: ActivityDetector.isCommandFlag) else {
            return nil
        }
        return arguments[(flagIndex + 1)...].first { !$0.hasPrefix("-") }
    }

    /// Claude Code runs commands as `… && eval '<command>' < /dev/null && pwd -P >| …`.
    /// Extracts `<command>`, undoing the `'"'"'` escaping of embedded single quotes.
    static func unwrapEval(_ script: String) -> String? {
        let marker = "eval '"
        let escapedQuote = "'\"'\"'"
        guard let start = script.range(of: marker)?.upperBound else { return nil }

        var result = ""
        var index = start
        while index < script.endIndex {
            if script[index...].hasPrefix(escapedQuote) {
                result.append("'")
                index = script.index(index, offsetBy: escapedQuote.count)
            } else if script[index] == "'" {
                return result
            } else {
                result.append(script[index])
                index = script.index(after: index)
            }
        }
        return nil
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func truncate(_ text: String, to maxLength: Int) -> String {
        guard text.count > maxLength, maxLength > 1 else { return text }
        return text.prefix(maxLength - 1) + "…"
    }
}
