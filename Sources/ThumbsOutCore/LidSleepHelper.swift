import Foundation

/// Commands and files for lid-closed mode.
///
/// Closing the lid ignores power assertions; only the root-only `SleepDisabled` switch
/// (`pmset -a disablesleep 1`) prevents it. A one-time admin prompt installs a sudoers rule that
/// allows exactly two commands, so the app can then flip that switch without a password.
public enum LidSleepHelper {
    public static let sudoersPath = "/etc/sudoers.d/thumbs-out"
    public static let pmsetPath = "/usr/bin/pmset"
    public static let sudoPath = "/usr/bin/sudo"

    public enum SetupError: Error, Equatable {
        case invalidUserName(String)
    }

    public static func pmsetArguments(disableSleep: Bool) -> [String] {
        ["-a", "disablesleep", disableSleep ? "1" : "0"]
    }

    private static func pmsetCommand(disableSleep: Bool) -> String {
        ([pmsetPath] + pmsetArguments(disableSleep: disableSleep)).joined(separator: " ")
    }

    /// macOS short names; anything else could smuggle sudoers syntax into the rule.
    public static func isValidUserName(_ user: String) -> Bool {
        guard let first = user.unicodeScalars.first, first != "-", first != "." else { return false }
        return user.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (scalar.properties.isAlphabetic || ("0"..."9").contains(scalar) || "._-".unicodeScalars.contains(scalar))
        }
    }

    public static func sudoersContent(user: String) throws -> String {
        guard isValidUserName(user) else { throw SetupError.invalidUserName(user) }
        return """
        # Installed by thumbs-out so it can keep the Mac awake with the lid closed.
        # Remove from the app's settings, or: sudo pmset -a disablesleep 0 && sudo rm \(sudoersPath)
        \(user) ALL=(root) NOPASSWD: \(pmsetCommand(disableSleep: false)), \(pmsetCommand(disableSleep: true))

        """
    }

    /// Runs as root. The rule is written from inside the script into a root-only staging file
    /// (sudo ignores names containing a dot), so nothing running as the user can swap its contents
    /// while the password dialog is open. visudo validates it before it goes live, since a broken
    /// sudoers file can lock the user out of sudo.
    public static func installScript(user: String) throws -> String {
        let lines = try sudoersContent(user: user)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .dropLast() // trailing newline; printf adds one per line
            .map { shellQuote(String($0)) }
            .joined(separator: " ")
        return "umask 077; t=$(/usr/bin/mktemp /private/etc/sudoers.d/.thumbs-out.XXXXXX) || exit 1; "
            + "/usr/bin/printf '%s\\n' \(lines) > \"$t\" && /usr/sbin/visudo -cf \"$t\" && "
            + "/usr/sbin/chown root:wheel \"$t\" && /bin/chmod 0440 \"$t\" && "
            + "/bin/mv -f \"$t\" \(sudoersPath) || { /bin/rm -f \"$t\"; exit 1; }"
    }

    public static func uninstallScript() -> String {
        "\(pmsetCommand(disableSleep: false)); /bin/rm -f \(sudoersPath)"
    }

    /// Dead-man switch: once this exact app process is gone (checked by path, so a reused PID
    /// doesn't fool it), turn lid sleep back on, retrying for a few minutes.
    public static func watchdogScript(appPID: Int32, executablePath: String) -> String {
        "while [ \"$(/bin/ps -o comm= -p \(appPID))\" = \(shellQuote(executablePath)) ]; do /bin/sleep 5; done; "
            + "n=0; until \(sudoPath) -n \(pmsetCommand(disableSleep: false)); do "
            + "n=$((n+1)); [ \"$n\" -ge 20 ] && exit 1; /bin/sleep 15; done"
    }

    public static func administratorAppleScript(shell: String, prompt: String) -> String {
        "do shell script \(appleScriptString(shell)) with prompt \(appleScriptString(prompt)) with administrator privileges"
    }

    private static func appleScriptString(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
