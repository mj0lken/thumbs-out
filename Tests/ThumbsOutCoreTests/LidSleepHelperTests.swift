import Testing
@testable import ThumbsOutCore

@Suite("Lid sleep helper")
struct LidSleepHelperTests {
    @Test("sudoers rule only allows toggling disablesleep for one user")
    func sudoersRule() throws {
        let rule = try LidSleepHelper.sudoersContent(user: "malcolm")
        let grant = rule.split(separator: "\n").filter { !$0.hasPrefix("#") }
        #expect(grant == [
            "malcolm ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1",
        ])
        #expect(rule.hasSuffix("\n"))
    }

    @Test("rejects user names that could inject sudoers syntax", arguments: [
        "", "root ALL=(ALL) ALL", "me,you", "a\nb", "%admin", "../x", "-flag",
    ])
    func rejectsBadUsers(user: String) {
        #expect(throws: LidSleepHelper.SetupError.self) { try LidSleepHelper.sudoersContent(user: user) }
    }

    @Test("accepts ordinary macOS short names", arguments: ["malcolm", "john.doe", "dev_01", "a-b"])
    func acceptsUsers(user: String) {
        #expect(LidSleepHelper.isValidUserName(user))
    }

    @Test("pmset arguments match the sudoers rule exactly")
    func pmsetArguments() {
        #expect(LidSleepHelper.pmsetArguments(disableSleep: true) == ["-a", "disablesleep", "1"])
        #expect(LidSleepHelper.pmsetArguments(disableSleep: false) == ["-a", "disablesleep", "0"])
    }

    @Test("install script writes the rule as root in a root-only staging file, never from a user-writable path")
    func installScript() throws {
        let script = try LidSleepHelper.installScript(user: "malcolm")
        #expect(script.hasPrefix("umask 077; t=$(/usr/bin/mktemp /private/etc/sudoers.d/.thumbs-out.XXXXXX) || exit 1; "))
        #expect(script.contains("'malcolm ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1'"))
        #expect(script.contains(#"/usr/sbin/visudo -cf "$t""#))
        #expect(script.contains(#"/bin/mv -f "$t" /etc/sudoers.d/thumbs-out"#))
        #expect(script.hasSuffix(#"|| { /bin/rm -f "$t"; exit 1; }"#))
        #expect(!script.contains("/tmp"))
    }

    @Test("install script refuses unsafe user names")
    func installScriptRejectsBadUser() {
        #expect(throws: LidSleepHelper.SetupError.self) { try LidSleepHelper.installScript(user: "me ALL") }
    }

    @Test("uninstall script re-enables sleep and removes the rule")
    func uninstallScript() {
        #expect(LidSleepHelper.uninstallScript()
            == "/usr/bin/pmset -a disablesleep 0; /bin/rm -f /etc/sudoers.d/thumbs-out")
    }

    @Test("sudoers file name has no dot, which sudo would silently skip")
    func fileName() {
        #expect(!LidSleepHelper.sudoersPath.split(separator: "/").last!.contains("."))
    }

    @Test("AppleScript wrapper escapes quotes and backslashes")
    func appleScript() {
        let wrapped = LidSleepHelper.administratorAppleScript(shell: #"echo "hi" \ there"#, prompt: "Say \"hi\"")
        #expect(wrapped == #"do shell script "echo \"hi\" \\ there" with prompt "Say \"hi\"" with administrator privileges"#)
    }

    @Test("watchdog waits for this exact app process, then retries re-enabling sleep")
    func watchdog() {
        let script = LidSleepHelper.watchdogScript(appPID: 4242, executablePath: "/Applications/thumbs out.app/ThumbsOut")
        #expect(script.hasPrefix(#"while [ "$(/bin/ps -o comm= -p 4242)" = '/Applications/thumbs out.app/ThumbsOut' ]; do /bin/sleep 5; done; "#))
        #expect(script.contains("until /usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0"))
        #expect(script.contains("-ge 20 ] && exit 1"))
    }

    @Test("sudoers comment explains how to remove the rule without stranding lid sleep")
    func removalHint() throws {
        let rule = try LidSleepHelper.sudoersContent(user: "malcolm")
        #expect(rule.contains("sudo pmset -a disablesleep 0 && sudo rm /etc/sudoers.d/thumbs-out"))
    }
}
