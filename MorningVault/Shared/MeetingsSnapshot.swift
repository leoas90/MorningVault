import Foundation

// Compiled into three modules: the app, the widget extension (project.yml adds
// MorningVault/Shared to both) and MeetingNotesKit (a symlink under
// Packages/MeetingNotesKit/Sources/MeetingNotesKit/Shared). It stays Foundation-only
// so the widget never links SwiftData, EventKit or FluidAudio. One file, one wire format.

/// What the Meetings widget shows: the next calendar meeting, the last recorded one,
/// what is still open, and whether a recording is running. Written by the Meetings
/// package into the App Group; read by the widget. No transcript, no notes.
struct MeetingsSnapshot: Codable, Equatable, Sendable {
    struct NextMeeting: Codable, Equatable, Sendable {
        var title: String
        var start: Date
        var end: Date
        var calendarEventID: String?
        var attendeeNames: [String]

        init(title: String, start: Date, end: Date, calendarEventID: String? = nil, attendeeNames: [String] = []) {
            self.title = title
            self.start = start
            self.end = end
            self.calendarEventID = calendarEventID
            self.attendeeNames = attendeeNames
        }
    }

    struct LastMeeting: Codable, Equatable, Sendable {
        var id: UUID
        var title: String
        var date: Date
        var openItemCount: Int

        init(id: UUID, title: String, date: Date, openItemCount: Int = 0) {
            self.id = id
            self.title = title
            self.date = date
            self.openItemCount = openItemCount
        }
    }

    struct OpenItem: Codable, Equatable, Sendable {
        var text: String
        var meetingID: UUID

        init(text: String, meetingID: UUID) {
            self.text = text
            self.meetingID = meetingID
        }
    }

    static let currentVersion = 1

    var version: Int
    var nextMeeting: NextMeeting?
    var lastMeeting: LastMeeting?
    /// All open action items across meetings.
    var openItemCount: Int
    /// The first few open items, newest meeting first. At most `maxOpenItems`.
    var openItems: [OpenItem]
    var isRecording: Bool
    var updatedAt: Date

    static let maxOpenItems = 3

    init(
        version: Int = MeetingsSnapshot.currentVersion,
        nextMeeting: NextMeeting? = nil,
        lastMeeting: LastMeeting? = nil,
        openItemCount: Int = 0,
        openItems: [OpenItem] = [],
        isRecording: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.version = version
        self.nextMeeting = nextMeeting
        self.lastMeeting = lastMeeting
        self.openItemCount = openItemCount
        self.openItems = Array(openItems.prefix(Self.maxOpenItems))
        self.isRecording = isRecording
        self.updatedAt = updatedAt
    }

    static let empty = MeetingsSnapshot(updatedAt: Date(timeIntervalSince1970: 0))

    /// The next meeting, only while it has not ended at `now`.
    func upcomingMeeting(at now: Date = Date()) -> NextMeeting? {
        guard let next = nextMeeting, next.end > now else { return nil }
        return next
    }

    static func encode(_ snapshot: MeetingsSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }

    static func decode(_ data: Data) throws -> MeetingsSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MeetingsSnapshot.self, from: data)
    }
}

/// Reads and writes `MeetingsSnapshot` in the App Group UserDefaults and asks WidgetKit
/// to redraw the Meetings widget after every write.
enum MeetingsSnapshotStore {
    static let appGroup = "group.com.morningvault.app"
    static let key = "meetings_snapshot_v1"
    /// `kind` of the Meetings widget; the app reloads only this timeline.
    static let widgetKind = "MorningVaultMeetings"

    /// The App Group suite; `.standard` only where the group is not provisioned.
    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static func load(from defaults: UserDefaults = sharedDefaults) -> MeetingsSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? MeetingsSnapshot.decode(data)
    }

    static func save(_ snapshot: MeetingsSnapshot, to defaults: UserDefaults = sharedDefaults) {
        var copy = snapshot
        copy.version = MeetingsSnapshot.currentVersion
        copy.updatedAt = Date()
        guard let data = try? MeetingsSnapshot.encode(copy) else { return }
        defaults.set(data, forKey: key)
        reloadWidget()
    }

    /// Read-modify-write so callers that only know part of the picture (a saved meeting,
    /// a toggled action item) keep the rest.
    static func update(in defaults: UserDefaults = sharedDefaults, _ change: (inout MeetingsSnapshot) -> Void) {
        var snapshot = load(from: defaults) ?? MeetingsSnapshot()
        change(&snapshot)
        save(snapshot, to: defaults)
    }

    static func clear(in defaults: UserDefaults = sharedDefaults) {
        defaults.removeObject(forKey: key)
        reloadWidget()
    }

    static func reloadWidget() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        #endif
    }
}

#if canImport(WidgetKit)
import WidgetKit
#endif
