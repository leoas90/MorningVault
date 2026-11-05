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

    /// URL of `Meetings/<fileName>` inside the app group, or `nil` without an app group.
    public static func fileURL(fileName: String) -> URL? {
        containerURL()?
            .appendingPathComponent(meetingsFolderName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    /// Removes `Meetings/<fileName>`. Missing files and a missing app group are fine.
    @discardableResult
    public static func delete(fileName: String) -> Bool {
        guard let url = fileURL(fileName: fileName), FileManager.default.fileExists(atPath: url.path) else { return false }
        return (try? FileManager.default.removeItem(at: url)) != nil
    }

    /// Renames `Meetings/<fileName>` to `Meetings/<newFileName>`, replacing any file in the way.
    @discardableResult
    public static func move(fileName: String, to newFileName: String) -> Bool {
        guard fileName != newFileName,
              let source = fileURL(fileName: fileName),
              let destination = fileURL(fileName: newFileName),
              FileManager.default.fileExists(atPath: source.path)
        else { return false }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: source, to: destination)
            return true
        } catch {
            return false
        }
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
