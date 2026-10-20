import Testing
@testable import ThumbsOutCore

@Suite("Process records")
struct ProcessRecordTests {
    @Test("finds the script an interpreter runs", arguments: [
        (["/opt/homebrew/bin/node", "/opt/homebrew/bin/gemini"], "gemini"),
        (["/usr/bin/python3", "/Users/me/.local/bin/aider", "--model", "x"], "aider"),
        (["node", "--import", "./loader.mjs", "/opt/homebrew/bin/gemini"], "gemini"),
        (["python3", "-W", "ignore", "/usr/local/bin/aider"], "aider"),
        (["python3", "-m", "aider"], "aider"),
        (["node", "-e", "console.log(1)"], nil),
        (["python3", "-c", "print(1)"], nil),
    ])
    func scriptNames(arguments: [String], expected: String?) {
        let record = ProcessRecord(pid: 1, ppid: 0, path: arguments[0], arguments: arguments)
        #expect(record.scriptName == expected)
    }

    @Test("recognises framework Pythons whose executable is named Python")
    func frameworkPython() {
        let path = "/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python"
        let record = ProcessRecord(pid: 1, ppid: 0, path: path, arguments: ["python3", "/opt/homebrew/bin/aider"])
        #expect(record.scriptName == "aider")
        #expect(Agent.agent(for: record) == .aider)
    }
}
