import Foundation
import SwiftUI

/// The water tracker's face for the views: reads the `WaterStore` actor, publishes the
/// tracker, and re-reads after every write. With no store (previews) the mutations are
/// applied to the in-memory tracker instead. Every write also rebuilds the reminders.
@MainActor
final class WaterViewModel: ObservableObject {
    static let shared = WaterViewModel(store: .shared)

    @Published private(set) var tracker: WaterTracker
    @Published private(set) var hasLoaded = false
    @Published private(set) var lastLogged: WaterEntry?

    private let store: WaterStore?
    private let fixedNow: Date?
    let calendar: Calendar

    var now: Date { fixedNow ?? Date() }
    var units: UnitsPreference { UnitsPreference.current }

    init(store: WaterStore?, tracker: WaterTracker = WaterTracker(), now: Date? = nil, calendar: Calendar = .current) {
        self.store = store
        self.tracker = tracker
        self.fixedNow = now
        self.calendar = calendar
        if store == nil { hasLoaded = true }
    }

    /// Preview: 750 of 2,000 mL at 11:00, three entries.
    static func preview(now: Date = BriefingViewModel.previewNow) -> WaterViewModel {
        let start = Calendar.current.startOfDay(for: now)
        let entries = [
            WaterEntry(ts: start.addingTimeInterval(7.5 * 3600), ml: 250),
            WaterEntry(ts: start.addingTimeInterval(9 * 3600), ml: 300, source: .health, healthID: UUID()),
            WaterEntry(ts: start.addingTimeInterval(10.25 * 3600), ml: 200),
        ]
        return WaterViewModel(store: nil, tracker: WaterTracker(entries: entries), now: start.addingTimeInterval(11 * 3600))
    }

    static func previewEmpty(now: Date = BriefingViewModel.previewNow) -> WaterViewModel {
        WaterViewModel(store: nil, tracker: WaterTracker(), now: now)
    }

    static func previewDone(now: Date = BriefingViewModel.previewNow) -> WaterViewModel {
        let start = Calendar.current.startOfDay(for: now)
        return WaterViewModel(store: nil, tracker: WaterTracker(entries: [WaterEntry(ts: start.addingTimeInterval(8 * 3600), ml: 2000)]),
                              now: start.addingTimeInterval(18 * 3600))
    }

    // MARK: Derived

    var logged: Int { tracker.logged(at: now, calendar: calendar) }
    var remaining: Int { tracker.remaining(at: now, calendar: calendar) }
    var progress: Double { tracker.progress(at: now, calendar: calendar) }
    var isGoalMet: Bool { logged >= tracker.goalML }
    var tier: WaterTier { tracker.tier(at: now, calendar: calendar) }
    var isBehind: Bool { tracker.deficit(at: now, calendar: calendar) > 0 && !isGoalMet }
    var todayEntries: [WaterEntry] { tracker.entries(on: now, calendar: calendar) }
    var canUndo: Bool { tracker.lastAppEntry.map { calendar.isDate($0.ts, inSameDayAs: now) } ?? false }

    /// "500 of 2,000 mL" in the user's unit.
    var summaryLine: String {
        "\(units.formatVolumeNumber(ml: logged)) of \(units.formatVolume(ml: tracker.goalML))"
    }

    /// "1,500 to go" or "Goal met".
    var remainingLine: String {
        isGoalMet ? "Goal met" : "\(units.formatVolumeNumber(ml: remaining)) to go"
    }

    // MARK: Load

    func load() async {
        guard let store else { return }
        tracker = await store.load(now: now)
        hasLoaded = true
        await WaterReminderScheduler.reschedule(store: store, now: now)
    }

    /// A notification action or an intent wrote from outside the UI.
    func reloadAfterExternalChange() async {
        guard let store else { return }
        tracker = await store.tracker(now: now)
    }

    // MARK: Write

    func log(ml: Int) async {
        let amount = WaterTracker.clampAmount(ml)
        guard let store else {
            let entry = WaterEntry(ts: now, ml: amount)
            tracker.entries.append(entry)
            lastLogged = entry
            return
        }
        lastLogged = await store.log(ml: amount, at: now)
        tracker = await store.tracker(now: now)
        await WaterReminderScheduler.reschedule(store: store, now: now)
    }

    func undoLast() async {
        guard let store else {
            if let last = tracker.lastAppEntry { tracker.entries.removeAll { $0.id == last.id } }
            lastLogged = nil
            return
        }
        await store.undoLast(now: now)
        lastLogged = nil
        tracker = await store.tracker(now: now)
        await WaterReminderScheduler.reschedule(store: store, now: now)
    }

    func setQuietToday(_ quiet: Bool) async {
        guard let store else { tracker.quietToday = quiet; return }
        await store.setQuietToday(quiet, now: now)
        tracker = await store.tracker(now: now)
        await WaterReminderScheduler.reschedule(store: store, now: now)
    }

    /// Settings changed (goal, window, quick amounts, urgent flag): re-read and reschedule.
    func settingsChanged() async {
        WaterSettings.mirrorToAppGroup()
        guard let store else { return }
        await store.settingsChanged(now: now)
        tracker = await store.tracker(now: now)
        await WaterReminderScheduler.reschedule(store: store, now: now)
    }

    /// The tracker was just turned on: ask Health for write access, then load.
    func trackerEnabled() async {
        WaterSettings.mirrorToAppGroup()
        guard let store else { return }
        _ = await store.requestHealthShare()
        await load()
    }

    /// The tracker was turned off: cancel pending reminders.
    func trackerDisabled() async {
        WaterSettings.mirrorToAppGroup()
        guard let store else { return }
        await WaterReminderScheduler.reschedule(store: store, now: now)
        WaterWidgetReloader.reload()
    }
}
