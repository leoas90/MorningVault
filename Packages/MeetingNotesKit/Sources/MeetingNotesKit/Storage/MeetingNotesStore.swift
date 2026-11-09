import Foundation
import SwiftData
import Synchronization

/// Owns the on-disk locations used by the kit and builds the SwiftData container.
///
/// Path getters never touch the disk; `ensure…` functions create folders on
/// purpose, so looking at a meeting does not leave empty folders behind.
public enum MeetingNotesStore {
    /// The SwiftData schema used by the kit (the current `VersionedSchema`).
    public static let schema = Schema(versionedSchema: MeetingNotesSchemaV1.self)

    /// Folder that holds recordings, one sub-folder per meeting.
    public static var meetingsFolder: URL {
        applicationSupport.appendingPathComponent("Meetings", isDirectory: true)
    }

    /// Folder that holds the short clips of voice enrollment, one sub-folder
    /// per enrollment session. Kept apart from `meetingsFolder` so a clip left
    /// behind by a crash can never be mistaken for a meeting.
    public static var enrollmentFolder: URL {
        applicationSupport.appendingPathComponent("Enrollment", isDirectory: true)
    }

    /// Folder that holds the SwiftData store.
    public static var storeFolder: URL {
        applicationSupport.appendingPathComponent("Store", isDirectory: true)
    }

    /// Root of everything the kit writes to disk.
    public static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("VaultNotes", isDirectory: true)
    }

    /// Where the recording for `meetingID` lives. Pure: nothing is created.
    public static func audioFolder(for meetingID: UUID) -> URL {
        meetingsFolder.appendingPathComponent(meetingID.uuidString, isDirectory: true)
    }

    /// URL of the `.m4a` recording for `meetingID`. Pure: nothing is created.
    public static func audioURL(for meetingID: UUID, fileName: String = "recording.m4a") -> URL {
        audioFolder(for: meetingID).appendingPathComponent(fileName)
    }

    /// Where the clip of enrollment session `sessionID` lives. Pure.
    public static func enrollmentFolder(for sessionID: UUID) -> URL {
        enrollmentFolder.appendingPathComponent(sessionID.uuidString, isDirectory: true)
    }

    /// URL of the `.m4a` clip for enrollment session `sessionID`. Pure.
    public static func enrollmentAudioURL(for sessionID: UUID, fileName: String = "recording.m4a") -> URL {
        enrollmentFolder(for: sessionID).appendingPathComponent(fileName)
    }

    /// Creates the recording folder of `meetingID` and returns it.
    @discardableResult
    public static func ensureAudioFolder(for meetingID: UUID) throws -> URL {
        let folder = audioFolder(for: meetingID)
        try ensureFolder(folder)
        return folder
    }

    /// Creates the folder of enrollment session `sessionID` and returns it.
    @discardableResult
    public static func ensureEnrollmentFolder(for sessionID: UUID) throws -> URL {
        let folder = enrollmentFolder(for: sessionID)
        try ensureFolder(folder)
        return folder
    }

    /// Creates `folder` (and its parents) when it is not there yet.
    public static func ensureFolder(_ folder: URL) throws {
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }

    // MARK: - Container

    /// Builds the container that stores meetings.
    ///
    /// - Parameter inMemory: keep everything in RAM, used by previews and tests.
    public static func modelContainer(inMemory: Bool = false) throws -> ModelContainer {
        if inMemory {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return try ModelContainer(
                for: schema,
                migrationPlan: MeetingNotesMigrationPlan.self,
                configurations: [configuration]
            )
        }
        try ensureFolder(storeFolder)
        return try modelContainer(at: storeFolder.appendingPathComponent("MeetingNotes.store"))
    }

    /// Opens (or creates) the store file at `url` with the kit's migration plan.
    static func modelContainer(at url: URL) throws -> ModelContainer {
        // .none: the app now has a CloudKit entitlement, and SwiftData would otherwise try to
        // mirror this store to iCloud, which fails on the unique id (SwiftDataError 1).
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(
            for: schema,
            migrationPlan: MeetingNotesMigrationPlan.self,
            configurations: [configuration]
        )
    }

    private static let sharedContainerCache = Mutex<ModelContainer?>(nil)

    /// The one on-disk container the app should use everywhere.
    ///
    /// Created on first use and kept; a failure is thrown every time so the
    /// caller can show it, and the next call tries again.
    public static func sharedContainer() throws -> ModelContainer {
        if let cached = sharedContainerCache.withLock({ $0 }) {
            return cached
        }
        let container = try modelContainer()
        return sharedContainerCache.withLock { cache in
            if let existing = cache { return existing }
            cache = container
            return container
        }
    }

    // MARK: - Orphan sweep

    private static let sweepDone = Mutex(false)

    /// Removes recording folders that belong to no `Meeting` row and leftover
    /// enrollment clips. Runs once per launch, off the main actor, and never
    /// throws: a sweep that cannot run just waits for the next launch.
    ///
    /// - Parameter activeRecordingIDs: recordings that are running right now;
    ///   their folders have no row yet and must stay.
    public static func sweepOrphanedAudioOnce(container: ModelContainer, activeRecordingIDs: Set<UUID> = []) {
        let first = sweepDone.withLock { done -> Bool in
            if done { return false }
            done = true
            return true
        }
        guard first else { return }
        Task.detached(priority: .utility) {
            let context = ModelContext(container)
            let known: Set<UUID>
            do {
                var descriptor = FetchDescriptor<Meeting>()
                descriptor.propertiesToFetch = [\.id]
                known = Set(try context.fetch(descriptor).map(\.id))
            } catch {
                return
            }
            sweepOrphanedAudio(knownMeetingIDs: known.union(activeRecordingIDs))
        }
    }

    /// Deletes every folder under `meetingsFolder` whose name is not in
    /// `knownMeetingIDs`, and everything under `enrollmentFolder`.
    ///
    /// Folders whose name is not a UUID are left alone. Returns the folders removed.
    @discardableResult
    static func sweepOrphanedAudio(
        knownMeetingIDs: Set<UUID>,
        meetingsFolder: URL = meetingsFolder,
        enrollmentFolder: URL = enrollmentFolder
    ) -> [URL] {
        let fileManager = FileManager.default
        var removed: [URL] = []

        if let entries = try? fileManager.contentsOfDirectory(
            at: meetingsFolder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for entry in entries {
                guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                guard let id = UUID(uuidString: entry.lastPathComponent) else { continue }
                guard !knownMeetingIDs.contains(id) else { continue }
                if (try? fileManager.removeItem(at: entry)) != nil {
                    removed.append(entry)
                }
            }
        }

        if let entries = try? fileManager.contentsOfDirectory(
            at: enrollmentFolder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for entry in entries where (try? fileManager.removeItem(at: entry)) != nil {
                removed.append(entry)
            }
        }
        return removed
    }
}
