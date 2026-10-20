import Testing
@testable import ThumbsOutCore

@Suite("Local model activity")
struct RuntimeActivityTests {
    let ollamaPath = "/Applications/Ollama.app/Contents/Resources/ollama"

    func snapshot(serverCPU: Double, runnerCPU: Double) -> [ProcessRecord] {
        [
            ProcessRecord(pid: 1, ppid: 0, path: "/sbin/launchd", arguments: []),
            ProcessRecord(pid: 50, ppid: 1, path: ollamaPath, arguments: [ollamaPath, "serve"], cpuTime: serverCPU),
            ProcessRecord(pid: 51, ppid: 50, path: ollamaPath, arguments: [ollamaPath, "runner"], cpuTime: runnerCPU),
        ]
    }

    @Test("a runtime using a lot of CPU since the last sample is generating")
    func busy() {
        let previous = RuntimeActivityDetector.sample(snapshot(serverCPU: 1, runnerCPU: 10), uptime: 100)
        let busy = RuntimeActivityDetector().busyRuntimes(
            in: snapshot(serverCPU: 1.1, runnerCPU: 14), uptime: 105, previous: previous, watching: [.ollama]
        )
        #expect(busy == [DetectedCommand(agent: .ollama, pid: 50, summary: "Generating · 82% CPU")])
    }

    @Test("an idle runtime with a model loaded is not generating")
    func idle() {
        let previous = RuntimeActivityDetector.sample(snapshot(serverCPU: 1, runnerCPU: 10), uptime: 100)
        let busy = RuntimeActivityDetector().busyRuntimes(
            in: snapshot(serverCPU: 1.01, runnerCPU: 10.05), uptime: 105, previous: previous, watching: [.ollama]
        )
        #expect(busy.isEmpty)
    }

    @Test("needs a previous sample and is skipped when not watched")
    func needsSampleAndWatch() {
        let current = snapshot(serverCPU: 1, runnerCPU: 50)
        #expect(RuntimeActivityDetector().busyRuntimes(in: current, uptime: 5, previous: nil, watching: [.ollama]).isEmpty)
        let previous = RuntimeActivityDetector.sample(snapshot(serverCPU: 0, runnerCPU: 0), uptime: 0)
        #expect(RuntimeActivityDetector().busyRuntimes(in: current, uptime: 5, previous: previous, watching: []).isEmpty)
    }

    @Test("counts the full CPU time of a runner that started since the last sample")
    func newRunner() {
        let before = [
            ProcessRecord(pid: 1, ppid: 0, path: "/sbin/launchd", arguments: []),
            ProcessRecord(pid: 50, ppid: 1, path: ollamaPath, arguments: [ollamaPath, "serve"], cpuTime: 1),
        ]
        let previous = RuntimeActivityDetector.sample(before, uptime: 100)
        let busy = RuntimeActivityDetector().busyRuntimes(
            in: snapshot(serverCPU: 1, runnerCPU: 4.5), uptime: 105, previous: previous, watching: [.ollama]
        )
        #expect(busy.map(\.agent) == [.ollama])
    }

    @Test("ignores samples taken too close together to be meaningful")
    func tinyInterval() {
        let previous = RuntimeActivityDetector.sample(snapshot(serverCPU: 1, runnerCPU: 10), uptime: 100)
        let busy = RuntimeActivityDetector().busyRuntimes(
            in: snapshot(serverCPU: 1, runnerCPU: 10.01), uptime: 100.05, previous: previous, watching: [.ollama]
        )
        #expect(busy.isEmpty)
    }

    @Test("converts Mach ticks to seconds, as Apple Silicon reports CPU time in ticks")
    func machTicks() {
        // Apple Silicon timebase is 125/3 (one tick = 41.67 ns); Intel's is 1/1 (nanoseconds).
        #expect(MachTime.seconds(ticks: 24_000_000, numer: 125, denom: 3) == 1.0)
        #expect(MachTime.seconds(ticks: 1_000_000_000, numer: 1, denom: 1) == 1.0)
        #expect(MachTime.seconds(ticks: 5, numer: 1, denom: 0) == 0)
    }

    @Test("under Rosetta the reported 1/1 timebase is wrong for kernel CPU times; use Apple Silicon's")
    func rosettaTimebase() {
        #expect(MachTime.cpuTimebase(reportedNumer: 1, reportedDenom: 1, isTranslated: true) == (125, 3))
        #expect(MachTime.cpuTimebase(reportedNumer: 1, reportedDenom: 1, isTranslated: false) == (1, 1))
        #expect(MachTime.cpuTimebase(reportedNumer: 125, reportedDenom: 3, isTranslated: false) == (125, 3))
    }
}
