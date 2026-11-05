import AppIntents
import Foundation
import MeetingNotesKit

// App actions for Siri, Shortcuts and Spotlight.
//
// These deliberately do NOT re-implement things iOS already does: Siri AI (iOS 27) already
// answers "when is my first meeting" or "will it rain" from Calendar and Weather, and
// "Hey Siri, good morning" already reads weather and the calendar. What iOS cannot know is
// MorningVault's own output, so that is all these expose: the AI day summary and the
// headline gists from the user's chosen feeds. Siri AI can then use them in its answers
// ("anything in my briefing about the markets?").
//
// They read the App Group snapshot the app saves (SharedBriefingStore), so they answer
// instantly and never touch HealthKit, the network or the model.

struct GetMorningSummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Morning Summary"
    static let description = IntentDescription(
        "Today's MorningVault summary, written on device from your briefing."
    )
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let b = SharedBriefingStore.loadToday(), let summary = b.summary, !summary.isEmpty else {
            let msg = "There's no MorningVault summary for today yet. Open MorningVault to make one."
            return .result(value: msg, dialog: IntentDialog(stringLiteral: msg))
        }
        return .result(value: summary, dialog: IntentDialog(stringLiteral: summary))
    }
}

struct GetHeadlinesIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Briefing Headlines"
    static let description = IntentDescription(
        "The top stories from your MorningVault news sources, one line each."
    )
    static let openAppWhenRun = false

    @Parameter(title: "Number of stories", default: 5, inclusiveRange: (1, 10))
    var count: Int

    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog {
        let items = (SharedBriefingStore.loadToday()?.headlines ?? []).prefix(count)
        guard !items.isEmpty else {
            let msg = "No headlines yet today. Open MorningVault to load your news."
            return .result(value: [], dialog: IntentDialog(stringLiteral: msg))
        }
        let lines = items.map { h in
            if let gist = h.gist, !gist.isEmpty { return "\(h.title): \(gist)" }
            return h.title
        }
        return .result(value: Array(lines), dialog: IntentDialog(stringLiteral: lines.joined(separator: "\n")))
    }
}

// MARK: - Meetings

/// "Start a meeting in MorningVault": opens the app on the Meetings tab and starts recording
/// (the same route the widget and the Brief's Record button use).
struct StartMeetingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a Meeting"
    static let description = IntentDescription(
        "Opens MorningVault and starts recording a new meeting. Audio and transcript stay on device."
    )
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        MeetingsRouter.shared.requestRecording()
        return .result()
    }
}

/// "What are my action items": open items from meetings in the last two days, read from the
/// on-device store. Nothing leaves the phone.
struct OpenActionItemsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Open Action Items"
    static let description = IntentDescription(
        "Action items still open from your meetings in the last two days."
    )
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog {
        let since = Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date()
        let items: [String]
        do {
            items = try MeetingDigest.openActionItems(since: since)
        } catch {
            let msg = "Your meeting notes could not be read right now."
            return .result(value: [], dialog: IntentDialog(stringLiteral: msg))
        }
        guard !items.isEmpty else {
            let msg = "No open action items from your meetings in the last two days."
            return .result(value: [], dialog: IntentDialog(stringLiteral: msg))
        }
        let spoken: String
        if items.count == 1 {
            spoken = "One open action item: \(items[0])."
        } else {
            let listed = items.prefix(5).enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
            let more = items.count > 5 ? "\nAnd \(items.count - 5) more." : ""
            spoken = "\(items.count) open action items:\n\(listed)\(more)"
        }
        return .result(value: items, dialog: IntentDialog(stringLiteral: spoken))
    }
}

struct MorningVaultShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetMorningSummaryIntent(),
            phrases: [
                "Get my \(.applicationName) summary",
                "What's in my \(.applicationName)",
            ],
            shortTitle: "Morning Summary",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: GetHeadlinesIntent(),
            phrases: [
                "Get my \(.applicationName) headlines",
            ],
            shortTitle: "Headlines",
            systemImageName: "newspaper"
        )
        // No device-name words in phrases or descriptions (App Review error 90626).
        AppShortcut(
            intent: StartMeetingIntent(),
            phrases: [
                "Start a meeting in \(.applicationName)",
                "Record a meeting in \(.applicationName)",
                "New \(.applicationName) meeting",
            ],
            shortTitle: "Start a Meeting",
            systemImageName: "record.circle"
        )
        AppShortcut(
            intent: OpenActionItemsIntent(),
            phrases: [
                "What are my action items in \(.applicationName)",
                "Get my \(.applicationName) action items",
                "Open action items from \(.applicationName)",
            ],
            shortTitle: "Action Items",
            systemImageName: "checklist"
        )
    }
}
