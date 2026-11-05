import Foundation
import SwiftData

/// Owns the on-disk locations used by the kit and builds the SwiftData container.
public enum MeetingNotesStore {
    /// The SwiftData schema used by the kit.
    public static let schema = Schema([
        Meeting.self,
        TranscriptSegment.self,
        ActionItemRecord.self
    ])

    /// Folder that holds recordings, one sub-folder per meeting.
    public static var meetingsFolder: URL {
        applicationSupport.appendingPathComponent("Meetings", isDirectory: true)
    }

    /// Folder that holds the SwiftData store.
    public static var storeFolder: URL {
        applicationSupport.appendingPathComponent("Store", isDirectory: true)
    }

    /// Root of everything the kit writes to disk.
    public static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let folder = base.appendingPathComponent("VaultNotes", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    /// Where a recording for `meetingID` lives.
    public static func audioFolder(for meetingID: UUID) -> URL {
        let folder = meetingsFolder.appendingPathComponent(meetingID.uuidString, isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    /// URL of the `.m4a` recording for `meetingID`.
    public static func audioURL(for meetingID: UUID, fileName: String = "recording.m4a") -> URL {
        audioFolder(for: meetingID).appendingPathComponent(fileName)
    }

    /// Builds the container that stores meetings.
    ///
    /// - Parameter inMemory: keep everything in RAM, used by previews and tests.
    public static func modelContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            let url = storeFolder.appendingPathComponent("MeetingNotes.store")
            if !FileManager.default.fileExists(atPath: storeFolder.path) {
                try? FileManager.default.createDirectory(at: storeFolder, withIntermediateDirectories: true)
            }
            configuration = ModelConfiguration(schema: schema, url: url)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
