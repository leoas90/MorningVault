import Foundation

/// Writes finished meetings as Markdown into the shared MorningVault app group.
///
/// The app group only exists on a properly provisioned build, so every failure is
/// swallowed on purpose: the meeting still lives in the kit's own store.
public enum AppGroupMarkdownWriter {
    /// The app group MorningVault and this kit share.
    public static let groupIdentifier = "group.com.morningvault.app"

    /// Folder inside the app group that holds the meeting files.
    public static let meetingsFolderName = "Meetings"

    /// Returns the shared container, or `nil` when the app group is not available.
    public static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
    }

    /// Writes `markdown` to `Meetings/<fileName>` inside the app group.
    ///
    /// - Returns: `true` when the file was written, `false` when it was skipped.
    @discardableResult
    public static func write(_ markdown: String, fileName: String) -> Bool {
        guard let container = containerURL() else { return false }
        let folder = container.appendingPathComponent(meetingsFolderName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(fileName)
            try markdown.write(to: destination, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }
}
