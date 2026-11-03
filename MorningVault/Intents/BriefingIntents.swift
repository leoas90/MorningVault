import AppIntents
import Foundation

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
        "Today's MorningVault summary, written on your iPhone from your briefing."
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
    }
}
