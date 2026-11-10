import AppIntents
import Foundation

// MARK: - Water intents
//
// "Log water in MorningVault" and "How much water have I had in MorningVault". Compiled into
// the app and the widget extension (Shared), so the Water widget's button can run
// `LogWaterIntent` in place. Writes go through the `WaterStore` actor; in the widget process
// there is no Health client, so the entry waits in the mirror until the app syncs it.

/// Logs an amount of water for now. With no amount it logs the first of the user's cups.
struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Water"
    static let description = IntentDescription("Adds water to today's total. Saved to Health when the app has access.")
    static let openAppWhenRun = false

    /// Optional: nothing given means the primary cup.
    @Parameter(title: "Amount (mL)", inclusiveRange: (50, 2000))
    var ml: Int?

    init() {}

    init(ml: Int?) {
        self.ml = ml
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$ml) mL of water")
    }

    /// The amount this run logs: the given one, else the primary cup.
    static func amount(ml: Int?, cup: WaterCup) -> Int {
        WaterTracker.clampAmount(ml ?? cup.ml)
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard WaterSettings.isEnabled() else {
            return .result(dialog: "The water tracker is off. Turn it on under Settings, Trackers in MorningVault.")
        }
        let store = WaterStore.shared
        await store.log(ml: Self.amount(ml: ml, cup: WaterSettings.primaryCup()))
        let snapshot = await store.current()
        WaterWidgetReloader.reload()
        await MainActor.run { NotificationCenter.default.post(name: .waterChangedExternally, object: nil) }
        let units = UnitsPreference.current
        let dialog: IntentDialog = snapshot.isGoalMet
            ? "Logged. Goal met, \(units.formatVolume(ml: snapshot.loggedML))."
            : "Logged. \(units.formatVolume(ml: snapshot.loggedML)) so far, \(units.formatVolume(ml: snapshot.remainingML)) to go."
        return .result(dialog: dialog)
    }
}

/// "Seven hundred fifty millilitres so far, one litre to go." from the App Group snapshot.
struct GetWaterProgressIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Water Progress"
    static let description = IntentDescription("How much water you have logged today and how much is left.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let text = Self.spokenProgress(snapshot: WaterSnapshotStore.load(), enabled: WaterSettings.isEnabled())
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }

    /// Pure so it can be tested.
    static func spokenProgress(snapshot: WaterTodaySnapshot?, now: Date = Date(), units: UnitsPreference = .current, enabled: Bool = true) -> String {
        guard enabled else { return "The water tracker is off. Turn it on under Settings, Trackers in MorningVault." }
        guard let snapshot, snapshot.isToday(now) else {
            return "Nothing logged yet today. Your goal is \(units.spokenVolume(ml: WaterSettings.tracker().goalML))."
        }
        if snapshot.loggedML == 0 {
            return "Nothing logged yet today. Your goal is \(units.spokenVolume(ml: snapshot.goalML))."
        }
        if snapshot.isGoalMet {
            return "Goal met: \(units.spokenVolume(ml: snapshot.loggedML)) today."
        }
        return "\(units.spokenVolume(ml: snapshot.loggedML).capitalizedFirst) so far, \(units.spokenVolume(ml: snapshot.remainingML)) to go."
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
