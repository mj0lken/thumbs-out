import Foundation
import ThumbsOutCore

/// Folder listings for the transcript scanner: names and modification times, never file contents.
enum TranscriptFolders {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path

    private static let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]

    /// Empty when the folder doesn't exist, which is the usual case for agents that aren't installed.
    static func list(_ path: String) -> [FileEntry] {
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)
        else { return [] }
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let modified = values.contentModificationDate
            else { return nil }
            return FileEntry(name: url.lastPathComponent, isDirectory: values.isDirectory ?? false, modified: modified)
        }
    }
}
