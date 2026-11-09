import AppIntents
import Foundation

// MARK: - Household checklist intents
//
// "Mark piano done in MorningVault" and "What is left today in MorningVault". Compiled into
// the app and the widget extension (Shared), so the Today widget's check button can run
// `MarkDoneIntent` in place. Writes go through the `ChecklistStore` actor, off the main
// actor; reads come from the App Group snapshot so Siri answers instantly.

/// One active checklist item, as Siri and Shortcuts see it.
struct ChecklistItemEntity: AppEntity, Identifiable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Checklist item")
    static let defaultQuery = ChecklistItemQuery()

    var id: UUID
    var title: String
    var icon: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: title), image: .init(systemName: icon))
    }

    init(id: UUID, title: String, icon: String) {
        self.id = id
        self.title = title
        self.icon = icon
    }

    init(item: ChecklistItem) {
        self.init(id: item.id, title: item.title, icon: item.icon)
    }
}

/// Active items (not archived), today's open ones first when Siri asks for suggestions.
struct ChecklistItemQuery: EntityQuery, EntityStringQuery, Sendable {
    func entities(for identifiers: [UUID]) async throws -> [ChecklistItemEntity] {
        let items = try await ChecklistStore.shared.items()
        let wanted = Set(identifiers)
        return items.filter { wanted.contains($0.id) }.map(ChecklistItemEntity.init(item:))
    }

    func entities(matching string: String) async throws -> [ChecklistItemEntity] {
        let needle = string.trimmingCharacters(in: .whitespaces).lowercased()
        let items = try await ChecklistStore.shared.items()
        return items.filter { needle.isEmpty || $0.title.lowercased().contains(needle) }.map(ChecklistItemEntity.init(item:))
    }

    func suggestedEntities() async throws -> [ChecklistItemEntity] {
        let now = Date()
        let ledger = try await ChecklistStore.shared.ledger(asOf: now)
        let today = ledger.scheduled(on: now)
        let open = today.filter { !ledger.isDone($0, on: now) && !ledger.isSkipped($0, on: now) }
        let rest = ledger.items.filter { !$0.isArchived && !today.contains($0) }.sorted { $0.order < $1.order }
        return (open + rest).map(ChecklistItemEntity.init(item:))
    }
}

/// Checks one item for today. Hourly items check the current slot. Never undoes a check.
struct MarkDoneIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark Checklist Item Done"
    static let description = IntentDescription("Checks one item on your household checklist for today.")
    static let openAppWhenRun = false

    @Parameter(title: "Item")
    var item: ChecklistItemEntity

    init() {}

    init(item: ChecklistItemEntity) {
        self.item = item
    }

    init(itemID: UUID, title: String, icon: String = "star") {
        self.item = ChecklistItemEntity(id: itemID, title: title, icon: icon)
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$item) done")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date()
        let store = ChecklistStore.shared
        guard let found = try await store.items().first(where: { $0.id == item.id }) else {
            return .result(dialog: "That item is no longer on the list.")
        }
        var slot = 0
        if found.recurrence.isHourly {
            let ledger = try await store.ledger(asOf: now)
            let done = ledger.doneSlots(for: found, on: now)
            let current = found.recurrence.currentSlotIndex(at: now, calendar: .current) ?? 0
            slot = (current..<found.slotCount(on: now)).first { !done.contains($0) } ?? current
        }
        let checked = try await store.markDone(itemID: item.id, on: now, slotIndex: slot, byMember: HouseholdPhoneMember.id, at: now)
        ChecklistWidgetReloader.reload()
        await MainActor.run { NotificationCenter.default.post(name: .checklistChangedExternally, object: nil) }
        let dialog: IntentDialog = checked ? "\(found.title) done." : "\(found.title) was already done."
        return .result(dialog: dialog)
    }
}

/// "Three of six done. Left: walk, piano, time with kids." from the App Group snapshot.
struct GetTodayProgressIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Checklist Progress"
    static let description = IntentDescription("How much of today's household checklist is done, and what is left.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let text = Self.spokenProgress(snapshot: ChecklistSnapshotStore.load())
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }

    /// Pure so it can be tested. Titles are lowercased in the "Left" list, up to five.
    static func spokenProgress(snapshot: ChecklistTodaySnapshot?, now: Date = Date()) -> String {
        guard let snapshot, snapshot.day == ChecklistTodaySnapshot.dayKey(now) else {
            return "Nothing on the household checklist today yet. Open MorningVault to set it up."
        }
        guard snapshot.total > 0 else { return "Nothing on the household checklist today." }
        if snapshot.done >= snapshot.total {
            return "All \(numberWord(snapshot.total)) done today."
        }
        let left = snapshot.items.filter { !$0.isDone }.map { $0.title.lowercased() }
        let listed = left.prefix(5).joined(separator: ", ")
        let more = left.count > 5 ? ", and \(left.count - 5) more" : ""
        return "\(numberWord(snapshot.done).capitalized) of \(numberWord(snapshot.total)) done. Left: \(listed)\(more)."
    }

    static func numberWord(_ n: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"]
        return n >= 0 && n < words.count ? words[n] : String(n)
    }
}

/// The member this phone belongs to (`household_me_member_id`), for completions made from
/// Siri or the widget. Mirrors `HouseholdPhoneSettings.meMemberID` without pulling the app's
/// scheduler into the widget target.
enum HouseholdPhoneMember {
    nonisolated static var id: UUID? {
        UserDefaults.standard.string(forKey: "household_me_member_id").flatMap(UUID.init(uuidString:))
    }
}

/// Asks WidgetKit to refresh the Today widget after a checklist write.
enum ChecklistWidgetReloader {
    static let widgetKind = "TodayWidget"

    nonisolated static func reload() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        #endif
    }
}

#if canImport(WidgetKit)
import WidgetKit
#endif

extension Notification.Name {
    /// A notification action or an intent wrote to the checklist store from outside the UI.
    static let checklistChangedExternally = Notification.Name("checklistChangedExternally")
}
