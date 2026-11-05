import AppIntents
import Foundation

// Compiled into the app and the widget extension (not the package). The widget only
// needs the type so the Live Activity's Stop button can reference it; `perform()` runs
// in the app's process, in the background if need be, which is where the recorder lives.

/// Stops the running meeting recording from the Live Activity or Dynamic Island.
struct StopRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop recording"
    static let description = IntentDescription("Stops the meeting MorningVault is recording and saves it.")
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        let action = await RecordingStopBridge.stopAction
        await action?()
        return .result()
    }
}

/// How the intent reaches the recorder without this file importing MeetingNotesKit:
/// the app sets `stopAction` at launch; the widget never does.
@MainActor
enum RecordingStopBridge {
    static var stopAction: (@MainActor () async -> Void)?
}
