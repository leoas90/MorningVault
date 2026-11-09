import AppIntents
import Foundation

// MARK: - Rotating Brief widget: tap to advance
//
// The rotating widget's tap button runs this in place (no app launch). It saves the page the
// widget should show next in the App Group and asks WidgetKit for a fresh timeline, whose
// first slot shows page `offset`. Compiled into the app and the widget extension (Shared).

/// Moves the rotating Brief widget to its next page.
struct AdvanceBriefPageIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Brief Page"
    static let description = IntentDescription("Shows the next page on the rotating Brief widget.")
    static let openAppWhenRun = false
    static let isDiscoverable = false

    /// The page index to show next; -1 bumps the saved offset by one.
    @Parameter(title: "Page", default: -1)
    var nextIndex: Int

    init() {}

    init(nextIndex: Int) {
        self.nextIndex = nextIndex
    }

    func perform() async throws -> some IntentResult {
        let offset = nextIndex >= 0 ? nextIndex : RotatingBriefOffsetStore.load() + 1
        RotatingBriefOffsetStore.save(offset)
        RotatingBriefWidgetReloader.reload()
        return .result()
    }
}
