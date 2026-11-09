import Foundation
import SwiftUI

/// Main-actor face of `ChecklistStore` for the Brief's Today section, the editor and the
/// members screen. Holds the members and the ledger (items + 90 days of completions and
/// skips) and re-reads them after every write. With no store (previews) the mutations are
/// applied to the in-memory ledger instead.
@MainActor
final class ChecklistViewModel: ObservableObject {
    static let shared = ChecklistViewModel(store: .shared)

    @Published private(set) var members: [HouseholdMember]
    @Published private(set) var ledger: ChecklistLedger
    @Published private(set) var hasLoaded = false
    @Published var lastError: String?

    let calendar: Calendar
    /// Fixed in previews; `Date()` in the app.
    private let fixedNow: Date?
    private let store: ChecklistStore?

    var now: Date { fixedNow ?? Date() }

    init(store: ChecklistStore?, members: [HouseholdMember] = [], ledger: ChecklistLedger = ChecklistLedger(),
         now: Date? = nil, calendar: Calendar = .current) {
        self.store = store
        self.members = members
        self.ledger = ledger
        self.fixedNow = now
        self.calendar = calendar
        if store == nil { hasLoaded = true }
    }

    /// Preview model: the fictional household, six items, two done, one hourly.
    static func preview(now: Date = BriefingViewModel.previewNow) -> ChecklistViewModel {
        ChecklistViewModel(store: nil, members: HouseholdMember.sample, ledger: ChecklistLedger.sample(now: now), now: now)
    }

    static func previewEmpty(now: Date = BriefingViewModel.previewNow) -> ChecklistViewModel {
        ChecklistViewModel(store: nil, members: [HouseholdMember.sampleMe], ledger: ChecklistLedger(), now: now)
    }

    // MARK: Derived

    var activeItems: [ChecklistItem] {
        ledger.items.filter { !$0.isArchived }.sorted { $0.order < $1.order }
    }

    var scheduledToday: [ChecklistItem] { ledger.scheduled(on: now, calendar: calendar) }

    var progressToday: (done: Int, total: Int) { ledger.progress(on: now, calendar: calendar) }

    func member(_ id: UUID?) -> HouseholdMember? {
        guard let id else { return nil }
        return members.first { $0.id == id }
    }

    var me: HouseholdMember? { members.first { $0.role == .me } }

    /// The member this phone belongs to (local setting); falls back to the "Me" role.
    var phoneMember: HouseholdMember? {
        if let id = HouseholdPhoneSettings.meMemberID, let m = members.first(where: { $0.id == id }) { return m }
        return me
    }

    /// "This is me" on this phone. Local only; reminders for other members stop firing here.
    func setPhoneMember(_ member: HouseholdMember?) async {
        HouseholdPhoneSettings.meMemberID = member?.id
        objectWillChange.send()
        guard store != nil else { return }
        await TrackerNotificationService.rescheduleReminders()
    }

    /// The Brief is on screen: remember it (Gentle reminders due in the next ten minutes are
    /// dropped) and refresh the pending reminders.
    func briefOpened() async {
        guard store != nil else { return }
        HouseholdPhoneSettings.markBriefOpened(at: now)
        await TrackerNotificationService.rescheduleReminders()
    }

    func isDone(_ item: ChecklistItem) -> Bool { ledger.isDone(item, on: now, calendar: calendar) }
    func isSkipped(_ item: ChecklistItem) -> Bool { ledger.isSkipped(item, on: now, calendar: calendar) }
    func streak(_ item: ChecklistItem) -> Int { ledger.streak(for: item, asOf: now, calendar: calendar) }
    func recentMarks(_ item: ChecklistItem) -> [ChecklistLedger.DayMark] { ledger.recentMarks(for: item, asOf: now, calendar: calendar) }

    // MARK: Loading

    func load() async {
        guard let store else { return }
        do {
            // "Me" comes from the greeting name, once, only when the household is empty.
            try await store.ensureMe(named: UserDefaults.standard.string(forKey: "user_name"))
            let ledger = try await store.ledger(asOf: now)
            let members = try await store.members()
            self.ledger = ledger
            self.members = members
            hasLoaded = true
            await reconcileTimers()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Checking

    /// Toggles the item for today. Hourly items toggle the current slot (the latest one that
    /// has started); before the first slot nothing happens.
    func toggle(_ item: ChecklistItem) async {
        var slot = 0
        if item.recurrence.isHourly {
            guard let current = item.recurrence.currentSlotIndex(at: now, calendar: calendar) else { return }
            // If the current slot is already checked, check the next unchecked one instead.
            let done = ledger.doneSlots(for: item, on: now, calendar: calendar)
            slot = done.contains(current) ? ((0..<item.slotCount(on: now, calendar: calendar)).first { !done.contains($0) } ?? current) : current
        }
        await toggle(item, slotIndex: slot)
    }

    func toggle(_ item: ChecklistItem, slotIndex: Int) async {
        let day = ChecklistDay.key(for: now, calendar: calendar)
        guard let store else {
            if let index = ledger.completions.firstIndex(where: { $0.itemID == item.id && $0.day == day && $0.slotIndex == slotIndex }) {
                ledger.completions.remove(at: index)
            } else {
                ledger.completions.append(Completion(itemID: item.id, day: day, slotIndex: slotIndex, byMember: me?.id, at: now))
                ledger.skips.removeAll { $0.itemID == item.id && $0.day == day }
            }
            return
        }
        await run { try await store.toggle(itemID: item.id, on: self.now, slotIndex: slotIndex, byMember: self.me?.id, at: self.now) }
    }

    func skipToday(_ item: ChecklistItem) async {
        let day = ChecklistDay.key(for: now, calendar: calendar)
        guard let store else {
            if !ledger.skips.contains(where: { $0.itemID == item.id && $0.day == day }) {
                ledger.skips.append(Skip(itemID: item.id, day: day))
            }
            return
        }
        await run { try await store.skip(itemID: item.id, on: self.now) }
    }

    func unskipToday(_ item: ChecklistItem) async {
        let day = ChecklistDay.key(for: now, calendar: calendar)
        guard let store else {
            ledger.skips.removeAll { $0.itemID == item.id && $0.day == day }
            return
        }
        await run { try await store.unskip(itemID: item.id, on: self.now) }
    }

    // MARK: Timers

    /// Sleeping tasks that finish a running timer when it ends while the app is open.
    private var timerTasks: [UUID: Task<Void, Never>] = [:]

    func isTimerRunning(_ item: ChecklistItem) -> Bool {
        ledger.items.first { $0.id == item.id }?.isTimerRunning ?? false
    }

    func timerEndsAt(_ item: ChecklistItem) -> Date? {
        ledger.items.first { $0.id == item.id }?.timerEndsAt
    }

    /// Starts the countdown, persists the start, schedules the end notification.
    func startTimer(_ item: ChecklistItem) async {
        guard item.kind.isTimer, !isDone(item) else { return }
        let start = now
        if let store {
            await run { try await store.startTimer(itemID: item.id, at: start) }
        } else if let index = ledger.items.firstIndex(where: { $0.id == item.id }) {
            ledger.items[index].timerStartedAt = start
        }
        guard let running = ledger.items.first(where: { $0.id == item.id }), let end = running.timerEndsAt else { return }
        if store != nil {
            await TrackerNotificationService.scheduleTimerDone(item: running, endsAt: end, day: ChecklistDay.key(for: start, calendar: calendar))
        }
        armTimerTask(for: item.id, endsAt: end)
    }

    /// Stops without checking.
    func stopTimer(_ item: ChecklistItem) async {
        timerTasks[item.id]?.cancel()
        timerTasks[item.id] = nil
        TrackerNotificationService.cancelTimerDone(itemID: item.id)
        if let store {
            await run { try await store.cancelTimer(itemID: item.id) }
        } else if let index = ledger.items.firstIndex(where: { $0.id == item.id }) {
            ledger.items[index].timerStartedAt = nil
        }
    }

    /// Timer ended, or the user tapped the running row: check the item and clear the start.
    func finishTimer(_ item: ChecklistItem) async {
        timerTasks[item.id]?.cancel()
        timerTasks[item.id] = nil
        TrackerNotificationService.cancelTimerDone(itemID: item.id)
        let day = ChecklistDay.key(for: now, calendar: calendar)
        guard let store else {
            if let index = ledger.items.firstIndex(where: { $0.id == item.id }) { ledger.items[index].timerStartedAt = nil }
            if !ledger.completions.contains(where: { $0.itemID == item.id && $0.day == day && $0.slotIndex == 0 }) {
                ledger.completions.append(Completion(itemID: item.id, day: day, byMember: me?.id, at: now))
            }
            return
        }
        await run { try await store.finishTimer(itemID: item.id, on: self.now, byMember: self.me?.id, at: self.now) }
    }

    /// After a load: timers that ended while the app was away check their item; the rest get
    /// a fresh sleeping task.
    private func reconcileTimers() async {
        for item in ledger.items where item.isTimerRunning {
            guard let end = item.timerEndsAt else { continue }
            if end <= now {
                await finishTimer(item)
            } else if timerTasks[item.id] == nil {
                armTimerTask(for: item.id, endsAt: end)
            }
        }
    }

    private func armTimerTask(for id: UUID, endsAt: Date) {
        timerTasks[id]?.cancel()
        let seconds = max(0, endsAt.timeIntervalSince(now))
        timerTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            if let item = self.ledger.items.first(where: { $0.id == id }), item.isTimerRunning {
                await self.finishTimer(item)
            }
        }
    }

    // MARK: Items

    var canAddItem: Bool { ledger.canAddItem }

    /// Saves (insert or update). Returns false and sets `lastError` when the store refuses.
    @discardableResult
    func save(_ item: ChecklistItem) async -> Bool {
        guard let store else {
            if let index = ledger.items.firstIndex(where: { $0.id == item.id }) {
                ledger.items[index] = item
            } else {
                guard ledger.canAddItem else { lastError = ChecklistStore.StoreError.itemCapReached.localizedDescription; return false }
                ledger.items.append(item)
            }
            return true
        }
        return await run { try await store.saveItem(item) }
    }

    func archive(_ item: ChecklistItem) async {
        guard let store else {
            if let index = ledger.items.firstIndex(where: { $0.id == item.id }) { ledger.items[index].archivedAt = now }
            return
        }
        await run { try await store.archiveItem(id: item.id, at: self.now) }
    }

    func move(from source: IndexSet, to destination: Int) async {
        var items = activeItems
        items.move(fromOffsets: source, toOffset: destination)
        let ids = items.map(\.id)
        guard let store else {
            for (index, id) in ids.enumerated() {
                if let i = ledger.items.firstIndex(where: { $0.id == id }) { ledger.items[i].order = index }
            }
            return
        }
        await run { try await store.reorderItems(ids) }
    }

    /// Next free `order` for a new item.
    var nextOrder: Int { (activeItems.map(\.order).max() ?? -1) + 1 }

    // MARK: Members

    @discardableResult
    func saveMember(_ member: HouseholdMember) async -> Bool {
        guard let store else {
            if let index = members.firstIndex(where: { $0.id == member.id }) { members[index] = member } else { members.append(member) }
            return true
        }
        return await run { try await store.saveMember(member) }
    }

    func deleteMember(_ member: HouseholdMember) async {
        guard let store else {
            members.removeAll { $0.id == member.id }
            for i in ledger.items.indices where ledger.items[i].forMember == member.id { ledger.items[i].forMember = nil }
            return
        }
        await run { try await store.deleteMember(id: member.id) }
    }

    // MARK: Plumbing

    /// Runs a store write, then reloads. Errors land in `lastError`.
    @discardableResult
    private func run(_ work: @Sendable () async throws -> Void) async -> Bool {
        do {
            try await work()
            await load()
            await TrackerNotificationService.rescheduleReminders(store: store ?? .shared)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}
