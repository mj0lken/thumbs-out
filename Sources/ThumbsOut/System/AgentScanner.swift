import AppKit
import ThumbsOutCore

/// Finds installed agents: known install paths, plus Launch Services for apps installed elsewhere.
enum AgentScanner {
    /// File-system checks only; safe to run off the main actor.
    static func scanFiles() -> [AgentInstallation] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.path
        let nodeVersions = (try? fileManager.contentsOfDirectory(atPath: "\(home)/.nvm/versions/node")) ?? []
        return AgentDiscovery.installations(home: home, nodeVersions: nodeVersions) {
            fileManager.fileExists(atPath: $0)
        }
    }

    /// NSWorkspace isn't documented as thread-safe, so this stays on the main actor.
    @MainActor
    static func appsFromLaunchServices(excluding known: Set<String>) -> [AgentInstallation] {
        Agent.allCases.flatMap { agent in
            agent.bundleIdentifiers
                .flatMap { NSWorkspace.shared.urlsForApplications(withBundleIdentifier: $0) }
                .map(\.path)
                .filter { !known.contains($0) && AgentDiscovery.isUserFacingApp(path: $0) }
                .map { path in
                    AgentInstallation(
                        agent: agent, kind: .app, name: ProcessDisplayName.from(path: path) + " app", path: path
                    )
                }
        }
    }
}
