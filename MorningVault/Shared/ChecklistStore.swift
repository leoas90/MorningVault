import CoreData
import Foundation

// MARK: - Managed objects
//
// Flat entities keyed by UUID, no relationships: every attribute optional or defaulted, which
// is what NSPersistentCloudKitContainer needs when the mirror lands (next release). Codegen
// is off in the model; these classes are the schema's Swift face.

@objc(CDHousehold)
final class CDHousehold: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var createdAt: Date?
}

@objc(CDMember)
final class CDMember: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var householdID: UUID?
    @NSManaged var name: String?
    @NSManaged var role: String?
    @NSManaged var order: Int32
    @NSManaged var createdAt: Date?
}

@objc(CDItem)
final class CDItem: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var householdID: UUID?
    @NSManaged var title: String?
    @NSManaged var icon: String?
    @NSManaged var forMemberID: UUID?
    @NSManaged var kindData: Data?
    @NSManaged var recurrenceData: Data?
    @NSManaged var reminderData: Data?
    @NSManaged var notes: String?
    @NSManaged var order: Int32
    @NSManaged var createdAt: Date?
    @NSManaged var archivedAt: Date?
    @NSManaged var expiresAt: Date?
    @NSManaged var sourceEventID: String?
    @NSManaged var sourceRuleID: String?
}

@objc(CDCompletion)
final class CDCompletion: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var itemID: UUID?
    @NSManaged var day: String?
    @NSManaged var slotIndex: Int32
    @NSManaged var byMemberID: UUID?
    @NSManaged var at: Date?
}

@objc(CDSkip)
final class CDSkip: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var itemID: UUID?
    @NSManaged var day: String?
}

@objc(CDSuggestionDecision)
final class CDSuggestionDecision: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var ruleID: String?
    @NSManaged var eventTitle: String?
    @NSManaged var decision: String?
    @NSManaged var decidedAt: Date?
}

// MARK: - Store

/// The household checklist on disk. Local Core Data today; swapping `NSPersistentContainer`
/// for `NSPersistentCloudKitContainer` in `makeContainer` is the whole iCloud step (plus the
/// entitlement). Value types in and out; nothing managed leaves the actor.
///
/// Every write republishes `checklist_today_v1` in the App Group for the widget.
actor ChecklistStore {
    static let shared = ChecklistStore()

    enum StoreError: Error, LocalizedError {
        case modelNotFound
        case itemCapReached
        case invalidTitle

        var errorDescription: String? {
            switch self {
            case .modelNotFound: return "The checklist data model is missing from the app bundle."
            case .itemCapReached: return "Twelve items is the limit. Archive one to add another."
            case .invalidTitle: return "Give the item a title (1 to 40 characters)."
            }
        }
    }

    /// Days of history kept; older completions and skips are trimmed on save.
    static let historyDays = 90
    static let appGroup = "group.com.morningvault.app"
    private static let storeFileName = "Household.sqlite"

    private let container: NSPersistentContainer
    private let calendar: Calendar
    /// False for in-memory test stores: no App Group writes.
    private let publishesSnapshot: Bool

    init(inMemory: Bool = false, calendar: Calendar = .current) {
        self.calendar = calendar
        self.publishesSnapshot = !inMemory
        self.container = ChecklistStore.makeContainer(inMemory: inMemory)
    }

    // MARK: Container

    /// One line to change for iCloud: `NSPersistentCloudKitContainer(name:managedObjectModel:)`.
    private static func makeContainer(inMemory: Bool) -> NSPersistentContainer {
        let model = loadModel()
        let container = NSPersistentContainer(name: "Household", managedObjectModel: model)
        let description: NSPersistentStoreDescription
        if inMemory {
            description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
        } else {
            description = NSPersistentStoreDescription(url: storeURL())
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            // Required by the CloudKit mirror later; harmless now.
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            if let error {
                // A corrupt local store is worse than an empty one: say so in the log, then
                // let the first write recreate it. No user data besides the checklist lives here.
                NSLog("ChecklistStore: failed to load store: \(error.localizedDescription)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }

    /// The App Group container so the widget can open the same file later; falls back to
    /// Application Support (tests, or a build without the group entitlement).
    private static func storeURL() -> URL {
        let base: URL
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            base = group
        } else {
            base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base.appendingPathComponent(storeFileName)
    }

    private static func loadModel() -> NSManagedObjectModel {
        let candidates = [Bundle.main] + Bundle.allBundles + Bundle.allFrameworks
        for bundle in candidates {
            if let url = bundle.url(forResource: "Household", withExtension: "momd"),
               let model = NSManagedObjectModel(contentsOf: url) {
                return model
            }
        }
        // Should not happen in a built app; an empty model makes the failure loud at first write.
        NSLog("ChecklistStore: Household.momd not found")
        return NSManagedObjectModel()
    }

    private func newContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        return context
    }

    // MARK: Members

    func members() async throws -> [HouseholdMember] {
        let context = newContext()
        return try await context.perform {
            let request = NSFetchRequest<CDMember>(entityName: "Member")
            request.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true), NSSortDescriptor(key: "createdAt", ascending: true)]
            return try context.fetch(request).compactMap(Self.member(from:))
        }
    }

    /// Inserts or updates. New members go to the end of the list.
    func saveMember(_ member: HouseholdMember) async throws {
        let context = newContext()
        try await context.perform {
            let request = NSFetchRequest<CDMember>(entityName: "Member")
            request.predicate = NSPredicate(format: "id == %@", member.id as CVarArg)
            request.fetchLimit = 1
            let object = try context.fetch(request).first ?? {
                let countRequest = NSFetchRequest<CDMember>(entityName: "Member")
                let count = (try? context.count(for: countRequest)) ?? 0
                let created = CDMember(context: context)
                created.id = member.id
                created.createdAt = Date()
                created.order = Int32(count)
                return created
            }()
            object.name = member.name
            object.role = member.role.rawValue
            if context.hasChanges { try context.save() }
        }
        await publishSnapshot()
    }

    func deleteMember(id: UUID) async throws {
        let context = newContext()
        try await context.perform {
            let request = NSFetchRequest<CDMember>(entityName: "Member")
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            for object in try context.fetch(request) { context.delete(object) }
            // Items that were for this member go back to the whole household.
            let items = NSFetchRequest<CDItem>(entityName: "Item")
            items.predicate = NSPredicate(format: "forMemberID == %@", id as CVarArg)
            for item in try context.fetch(items) { item.forMemberID = nil }
            if context.hasChanges { try context.save() }
        }
        await publishSnapshot()
    }

    /// Creates the "Me" member from the greeting name when the household is empty. Nothing
    /// else is ever pre-filled.
    @discardableResult
    func ensureMe(named name: String?) async throws -> HouseholdMember? {
        let existing = try await members()
        if let me = existing.first(where: { $0.role == .me }) { return me }
        guard existing.isEmpty, let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let me = HouseholdMember(name: name.trimmingCharacters(in: .whitespaces), role: .me)
        try await saveMember(me)
        return me
    }

    // MARK: Items

    func items(includeArchived: Bool = false) async throws -> [ChecklistItem] {
        let context = newContext()
        return try await context.perform {
            let request = NSFetchRequest<CDItem>(entityName: "Item")
            if !includeArchived { request.predicate = NSPredicate(format: "archivedAt == nil") }
            request.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true), NSSortDescriptor(key: "createdAt", ascending: true)]
            return try context.fetch(request).compactMap(Self.item(from:))
        }
    }

    /// Inserts or updates. Enforces the title rule and the 12 active-item cap on insert.
    func saveItem(_ item: ChecklistItem) async throws {
        guard ChecklistItem.isValidTitle(item.title) else { throw StoreError.invalidTitle }
        let context = newContext()
        try await context.perform {
            let request = NSFetchRequest<CDItem>(entityName: "Item")
            request.predicate = NSPredicate(format: "id == %@", item.id as CVarArg)
            request.fetchLimit = 1
            let object: CDItem
            if let found = try context.fetch(request).first {
                object = found
            } else {
                let active = NSFetchRequest<CDItem>(entityName: "Item")
                active.predicate = NSPredicate(format: "archivedAt == nil")
                if try context.count(for: active) >= ChecklistItem.maxItems, item.archivedAt == nil {
                    throw StoreError.itemCapReached
                }
                object = CDItem(context: context)
                object.id = item.id
                object.createdAt = item.createdAt
            }
            try Self.apply(item, to: object)
            if context.hasChanges { try context.save() }
        }
        await publishSnapshot()
    }

    /// New `order` values in the given sequence (ids not listed keep theirs).
    func reorderItems(_ ids: [UUID]) async throws {
        let context = newContext()
        try await context.perform {
            let request = NSFetchRequest<CDItem>(entityName: "Item")
            request.predicate = NSPredicate(format: "id IN %@", ids)
            let objects = try context.fetch(request)
            for (index, id) in ids.enumerated() {
                objects.first { $0.id == id }?.order = Int32(index)
            }
            if context.hasChanges { try context.save() }
        }
        await publishSnapshot()
    }

    /// Soft delete: the item leaves the list from today on; completions stay.
    func archiveItem(id: UUID, at date: Date = Date()) async throws {
        let context = newContext()
        try await context.perform {
            let request = NSFetchRequest<CDItem>(entityName: "Item")
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            for object in try context.fetch(request) { object.archivedAt = date }
            if context.hasChanges { try context.save() }
        }
        await publishSnapshot()
    }

    // MARK: Completions and skips

    /// Items (all, including archived, so history resolves), plus completions and skips from
    /// the last `historyDays` days.
    func ledger(asOf now: Date = Date()) async throws -> ChecklistLedger {
        let since = Self.cutoffKey(asOf: now, calendar: calendar)
        let context = newContext()
        return try await context.perform {
            let items = NSFetchRequest<CDItem>(entityName: "Item")
            items.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true), NSSortDescriptor(key: "createdAt", ascending: true)]
            let completions = NSFetchRequest<CDCompletion>(entityName: "Completion")
            completions.predicate = NSPredicate(format: "day >= %@", since)
            let skips = NSFetchRequest<CDSkip>(entityName: "Skip")
            skips.predicate = NSPredicate(format: "day >= %@", since)
            return ChecklistLedger(
                items: try context.fetch(items).compactMap(Self.item(from:)),
                completions: try context.fetch(completions).compactMap(Self.completion(from:)),
                skips: try context.fetch(skips).compactMap(Self.skip(from:))
            )
        }
    }

    /// Toggles item + day (+ slot). Checking adds a `Completion`; unchecking deletes the
    /// completions for that key. Returns the new done state for the slot.
    @discardableResult
    func toggle(itemID: UUID, on day: Date, slotIndex: Int = 0, byMember: UUID? = nil, at now: Date = Date()) async throws -> Bool {
        let key = ChecklistDay.key(for: day, calendar: calendar)
        let context = newContext()
        let nowDone: Bool = try await context.perform {
            let request = NSFetchRequest<CDCompletion>(entityName: "Completion")
            request.predicate = NSPredicate(format: "itemID == %@ AND day == %@ AND slotIndex == %d", itemID as CVarArg, key, Int32(slotIndex))
            let existing = try context.fetch(request)
            let result: Bool
            if existing.isEmpty {
                let completion = CDCompletion(context: context)
                completion.id = UUID()
                completion.itemID = itemID
                completion.day = key
                completion.slotIndex = Int32(slotIndex)
                completion.byMemberID = byMember
                completion.at = now
                result = true
            } else {
                for object in existing { context.delete(object) }
                result = false
            }
            // Checking also clears a skip for that day.
            if result {
                let skips = NSFetchRequest<CDSkip>(entityName: "Skip")
                skips.predicate = NSPredicate(format: "itemID == %@ AND day == %@", itemID as CVarArg, key)
                for skip in try context.fetch(skips) { context.delete(skip) }
            }
            if context.hasChanges { try context.save() }
            return result
        }
        try await trim(asOf: now)
        await publishSnapshot(now: now)
        return nowDone
    }

    /// "Not today": pauses the streak. Idempotent.
    func skip(itemID: UUID, on day: Date) async throws {
        let key = ChecklistDay.key(for: day, calendar: calendar)
        let context = newContext()
        try await context.perform {
            let request = NSFetchRequest<CDSkip>(entityName: "Skip")
            request.predicate = NSPredicate(format: "itemID == %@ AND day == %@", itemID as CVarArg, key)
            if try context.count(for: request) == 0 {
                let skip = CDSkip(context: context)
                skip.id = UUID()
                skip.itemID = itemID
                skip.day = key
                try context.save()
            }
        }
        await publishSnapshot()
    }

    func unskip(itemID: UUID, on day: Date) async throws {
        let key = ChecklistDay.key(for: day, calendar: calendar)
        let context = newContext()
        try await context.perform {
            let request = NSFetchRequest<CDSkip>(entityName: "Skip")
            request.predicate = NSPredicate(format: "itemID == %@ AND day == %@", itemID as CVarArg, key)
            for object in try context.fetch(request) { context.delete(object) }
            if context.hasChanges { try context.save() }
        }
        await publishSnapshot()
    }

    /// Drops completions and skips older than `historyDays`.
    func trim(asOf now: Date = Date()) async throws {
        let cutoff = Self.cutoffKey(asOf: now, calendar: calendar)
        let context = newContext()
        try await context.perform {
            let completions = NSFetchRequest<CDCompletion>(entityName: "Completion")
            completions.predicate = NSPredicate(format: "day < %@", cutoff)
            for object in try context.fetch(completions) { context.delete(object) }
            let skips = NSFetchRequest<CDSkip>(entityName: "Skip")
            skips.predicate = NSPredicate(format: "day < %@", cutoff)
            for object in try context.fetch(skips) { context.delete(object) }
            if context.hasChanges { try context.save() }
        }
    }

    private static func cutoffKey(asOf now: Date, calendar: Calendar) -> String {
        let date = calendar.date(byAdding: .day, value: -(historyDays - 1), to: calendar.startOfDay(for: now)) ?? now
        return ChecklistDay.key(for: date, calendar: calendar)
    }

    // MARK: Snapshot

    /// Builds today's snapshot from the store and writes it to the App Group.
    func publishSnapshot(now: Date = Date()) async {
        guard publishesSnapshot else { return }
        guard let snapshot = try? await makeSnapshot(now: now) else { return }
        ChecklistSnapshotStore.save(snapshot)
    }

    /// The derived snapshot (also what the tests check).
    func makeSnapshot(now: Date = Date()) async throws -> ChecklistTodaySnapshot {
        let ledger = try await ledger(asOf: now)
        let members = try await members()
        let initials = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.initial) })
        let scheduled = ledger.scheduled(on: now, calendar: calendar).filter { !ledger.isSkipped($0, on: now, calendar: calendar) }
        let progress = ledger.progress(on: now, calendar: calendar)
        let items = scheduled.map { item in
            ChecklistTodaySnapshot.Item(
                id: item.id,
                title: item.title,
                forInitial: item.forMember.flatMap { initials[$0] },
                isDone: ledger.isDone(item, on: now, calendar: calendar),
                nextSlot: item.recurrence.isHourly ? ledger.nextSlot(for: item, at: now, calendar: calendar) : nil
            )
        }
        return ChecklistTodaySnapshot(
            day: ChecklistDay.key(for: now, calendar: calendar),
            done: progress.done,
            total: progress.total,
            nextUndoneTitles: Array(items.filter { !$0.isDone }.map(\.title).prefix(3)),
            items: items,
            updatedAt: now
        )
    }

    // MARK: Mapping

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private static func member(from object: CDMember) -> HouseholdMember? {
        guard let id = object.id else { return nil }
        return HouseholdMember(id: id, name: object.name ?? "", role: HouseholdMember.Role(rawValue: object.role ?? "") ?? .other)
    }

    private static func item(from object: CDItem) -> ChecklistItem? {
        guard let id = object.id else { return nil }
        let kind = object.kindData.flatMap { try? decoder.decode(ChecklistItem.Kind.self, from: $0) } ?? .check
        let recurrence = object.recurrenceData.flatMap { try? decoder.decode(Recurrence.self, from: $0) } ?? .daily
        let reminder = object.reminderData.flatMap { try? decoder.decode(ReminderRule.self, from: $0) }
        return ChecklistItem(
            id: id,
            title: object.title ?? "",
            icon: object.icon ?? "star",
            forMember: object.forMemberID,
            kind: kind,
            recurrence: recurrence,
            reminder: reminder,
            notes: object.notes ?? "",
            order: Int(object.order),
            createdAt: object.createdAt ?? Date(),
            archivedAt: object.archivedAt,
            expiresAt: object.expiresAt,
            sourceEventID: object.sourceEventID,
            sourceRuleID: object.sourceRuleID
        )
    }

    private static func apply(_ item: ChecklistItem, to object: CDItem) throws {
        object.title = item.title
        object.icon = item.icon
        object.forMemberID = item.forMember
        object.kindData = try encoder.encode(item.kind)
        object.recurrenceData = try encoder.encode(item.recurrence)
        object.reminderData = try item.reminder.map { try encoder.encode($0) }
        object.notes = item.notes
        object.order = Int32(item.order)
        object.archivedAt = item.archivedAt
        object.expiresAt = item.expiresAt
        object.sourceEventID = item.sourceEventID
        object.sourceRuleID = item.sourceRuleID
    }

    private static func completion(from object: CDCompletion) -> Completion? {
        guard let id = object.id, let itemID = object.itemID, let day = object.day else { return nil }
        return Completion(id: id, itemID: itemID, day: day, slotIndex: Int(object.slotIndex), byMember: object.byMemberID, at: object.at ?? Date())
    }

    private static func skip(from object: CDSkip) -> Skip? {
        guard let id = object.id, let itemID = object.itemID, let day = object.day else { return nil }
        return Skip(id: id, itemID: itemID, day: day)
    }
}
