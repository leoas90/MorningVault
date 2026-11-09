import Foundation

// MARK: - Health client

/// One dietary water sample as read from Health.
struct WaterHealthSample: Equatable, Sendable {
    var id: UUID
    var ts: Date
    var ml: Int
}

/// The slice of HealthKit the water store needs. The app passes a HealthKit-backed client;
/// tests pass a fake; the widget extension passes nothing and stays local.
protocol WaterHealthClient: Sendable {
    /// False on devices without Health (iPad, simulator without data).
    var isAvailable: Bool { get }
    /// Shows the Health permission sheet for writing water. True when sharing is authorized.
    func requestShareAuthorization() async -> Bool
    /// True when the app may write water samples.
    func canWrite() async -> Bool
    /// Saves one sample and returns its UUID.
    func save(ml: Int, date: Date) async throws -> UUID
    /// Deletes a sample the app wrote.
    func delete(healthID: UUID) async throws
    /// Every water sample on the given day, or nil when Health cannot be read.
    func samples(on day: Date) async -> [WaterHealthSample]?
}

// MARK: - Store

/// Today's water on this device. Health is the store of truth when it is available: entries
/// logged here are written to Health and mirrored; entries from other sources (Watch, another
/// app) are merged in on every load. Without Health the mirror stands alone.
///
/// Settings come from `WaterSettings`; today's entries live in the App Group snapshot
/// `water_today_v1`, republished after every write so the widget, the reminders and Siri
/// read the same numbers. Nothing here runs on the main actor.
actor WaterStore {
    static let shared = WaterStore()

    private var health: WaterHealthClient?
    private let defaults: UserDefaults
    private let snapshotDefaults: UserDefaults?
    private let calendar: Calendar
    private let reloadsWidget: Bool
    private var snapshot: WaterTodaySnapshot

    /// `settingsSuite` / `snapshotSuite`: UserDefaults suite names for tests; nil means the
    /// standard defaults and the App Group.
    init(health: WaterHealthClient? = nil,
         settingsSuite: String? = nil,
         snapshotSuite: String? = nil,
         calendar: Calendar = .current,
         reloadsWidget: Bool = true,
         now: Date = Date()) {
        self.health = health
        let defaults = settingsSuite.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        let snapshotDefaults = snapshotSuite.flatMap { UserDefaults(suiteName: $0) }
        self.defaults = defaults
        self.snapshotDefaults = snapshotDefaults
        self.calendar = calendar
        self.reloadsWidget = reloadsWidget
        let settings = WaterSettings.tracker(defaults: defaults)
        let day = ChecklistDay.key(for: now, calendar: calendar)
        if let saved = WaterSnapshotStore.load(from: snapshotDefaults), saved.day == day {
            self.snapshot = saved
        } else {
            self.snapshot = WaterTodaySnapshot(day: day, goalML: settings.goalML, loggedML: 0, entries: [], quietToday: false, updatedAt: now)
        }
    }

    /// The app wires HealthKit in at launch; the widget never does.
    func configure(health: WaterHealthClient?) {
        self.health = health
    }

    var hasHealth: Bool { health?.isAvailable ?? false }

    // MARK: Read

    /// The tracker for `now`: saved settings plus today's entries.
    func tracker(now: Date = Date()) -> WaterTracker {
        rollDay(now: now)
        var t = WaterSettings.tracker(defaults: defaults)
        t.entries = snapshot.entries
        t.quietToday = snapshot.quietToday
        return t
    }

    func current(now: Date = Date()) -> WaterTodaySnapshot {
        rollDay(now: now)
        return snapshot
    }

    /// Rolls the day, pushes pending entries to Health, merges Health's samples for today and
    /// republishes. The Brief, the tracker screen and the app's foreground path call this.
    @discardableResult
    func load(now: Date = Date()) async -> WaterTracker {
        rollDay(now: now)
        await syncPending()
        await mergeFromHealth(now: now)
        publish(now: now)
        return tracker(now: now)
    }

    // MARK: Write

    /// Logs an amount: written to Health when possible, mirrored either way.
    @discardableResult
    func log(ml: Int, at date: Date = Date()) async -> WaterEntry {
        rollDay(now: date)
        var entry = WaterEntry(ts: date, ml: WaterTracker.clampAmount(ml), source: .app)
        if let health, health.isAvailable, await health.canWrite() {
            entry.healthID = try? await health.save(ml: entry.ml, date: date)
        }
        snapshot.entries.append(entry)
        snapshot.entries.sort { $0.ts < $1.ts }
        publish(now: date)
        return entry
    }

    /// Removes the most recent entry logged in the app (not another Health source), deleting
    /// its Health sample too.
    @discardableResult
    func undoLast(now: Date = Date()) async -> WaterEntry? {
        rollDay(now: now)
        guard let last = snapshot.entries.filter({ $0.source == .app }).max(by: { $0.ts < $1.ts }) else { return nil }
        snapshot.entries.removeAll { $0.id == last.id }
        if let id = last.healthID, let health, health.isAvailable {
            try? await health.delete(healthID: id)
        }
        publish(now: now)
        return last
    }

    func setQuietToday(_ quiet: Bool, now: Date = Date()) {
        rollDay(now: now)
        snapshot.quietToday = quiet
        if quiet { snapshot.nextSlot = nil }
        publish(now: now)
    }

    /// Snooze: no reminder before `now + minutes`.
    func snooze(minutes: Int, now: Date = Date()) {
        rollDay(now: now)
        snapshot.snoozedUntil = now.addingTimeInterval(TimeInterval(minutes * 60))
        publish(now: now)
    }

    /// The scheduler records the first pending slot so the widget and Siri can say it.
    func setNextSlot(_ date: Date?, now: Date = Date()) {
        rollDay(now: now)
        guard snapshot.nextSlot != date else { return }
        snapshot.nextSlot = date
        publish(now: now)
    }

    /// Settings changed in the app: republish with the new goal.
    func settingsChanged(now: Date = Date()) {
        rollDay(now: now)
        publish(now: now)
    }

    /// Shows the Health sheet for writing water. Called when the tracker is turned on, never
    /// before.
    func requestHealthShare() async -> Bool {
        guard let health, health.isAvailable else { return false }
        return await health.requestShareAuthorization()
    }

    // MARK: Health sync

    /// Pushes app entries that never reached Health (offline, or logged from the widget).
    func syncPending() async {
        guard let health, health.isAvailable, await health.canWrite() else { return }
        for index in snapshot.entries.indices where snapshot.entries[index].source == .app && snapshot.entries[index].healthID == nil {
            snapshot.entries[index].healthID = try? await health.save(ml: snapshot.entries[index].ml, date: snapshot.entries[index].ts)
        }
    }

    /// Health wins: samples present in Health replace the mirror; app entries deleted in
    /// Health disappear; app entries not yet in Health stay.
    func mergeFromHealth(now: Date) async {
        guard let health, health.isAvailable, let samples = await health.samples(on: now) else { return }
        let local = snapshot.entries
        var merged: [WaterEntry] = []
        for sample in samples {
            if let ours = local.first(where: { $0.healthID == sample.id }) {
                var entry = ours
                entry.ml = sample.ml
                entry.ts = sample.ts
                merged.append(entry)
            } else {
                merged.append(WaterEntry(id: sample.id, ts: sample.ts, ml: sample.ml, source: .health, healthID: sample.id))
            }
        }
        merged += local.filter { $0.healthID == nil && $0.source == .app }
        snapshot.entries = merged.sorted { $0.ts < $1.ts }
    }

    // MARK: Internals

    /// Starts a fresh snapshot on a new day, and picks up writes made by another process
    /// (the widget's button, Siri) since this store last published.
    private func rollDay(now: Date) {
        let day = ChecklistDay.key(for: now, calendar: calendar)
        if snapshot.day != day {
            snapshot = WaterTodaySnapshot(day: day, goalML: WaterSettings.tracker(defaults: defaults).goalML, loggedML: 0, entries: [],
                                          quietToday: false, updatedAt: now)
        }
        if let saved = WaterSnapshotStore.load(from: snapshotDefaults), saved.day == day, saved.updatedAt > snapshot.updatedAt {
            let known = Set(snapshot.entries.map(\.id))
            snapshot.entries += saved.entries.filter { !known.contains($0.id) }
            snapshot.entries.sort { $0.ts < $1.ts }
            snapshot.quietToday = saved.quietToday
            snapshot.snoozedUntil = saved.snoozedUntil
            snapshot.updatedAt = saved.updatedAt
        }
    }

    private func publish(now: Date) {
        let settings = WaterSettings.tracker(defaults: defaults)
        snapshot.goalML = settings.goalML
        snapshot.loggedML = snapshot.entries.reduce(0) { $0 + $1.ml }
        snapshot.updatedAt = now
        WaterSnapshotStore.save(snapshot, to: snapshotDefaults)
        if reloadsWidget {
            WaterWidgetReloader.reload()
            RotatingBriefWidgetReloader.reload()
        }
    }
}
