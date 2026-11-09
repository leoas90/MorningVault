import SwiftUI

/// The Today block of the Brief: the household checklist as hairline rows. Tap checks (hourly:
/// the current slot), long press skips or edits. Rendered by `BriefingSectionCard` for the
/// `today` section; the eyebrow and "3 of 6" live in the card header.
struct TodaySectionView: View {
    @ObservedObject var model: ChecklistViewModel
    @State private var editing: ChecklistItem?
    @State private var addingNew = false
    @State private var notesFor: ChecklistItem?

    var body: some View {
        Group {
            if !model.hasLoaded {
                SkeletonLine(width: 180, height: 14)
            } else if model.scheduledToday.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .task { await model.load(); await model.briefOpened() }
        .onReceive(NotificationCenter.default.publisher(for: .checklistChangedExternally)) { _ in Task { await model.reloadAfterExternalChange() } }
        .onReceive(NotificationCenter.default.publisher(for: .appBecameActive)) { _ in Task { await model.load(); await model.briefOpened() } }
        .sheet(item: $editing) { item in ChecklistItemEditor(model: model, item: item) }
        .sheet(isPresented: $addingNew) { ChecklistItemEditor(model: model) }
        .alert(notesFor?.title ?? "", isPresented: Binding(get: { notesFor != nil }, set: { if !$0 { notesFor = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notesFor?.notes ?? "")
        }
    }

    // MARK: Lists

    private var grouped: Bool { model.ledger.memberTagsInUse(on: model.now, calendar: model.calendar) > 1 }

    @ViewBuilder
    private var list: some View {
        let items = model.scheduledToday
        let progress = model.progressToday
        VStack(alignment: .leading, spacing: 0) {
            if progress.total > 0, progress.done >= progress.total {
                allDone
                Hairline()
            }
            if grouped {
                ForEach(groups(items), id: \.key) { group in
                    Eyebrow(text: group.label)
                        .padding(.top, 12)
                        .padding(.bottom, 2)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(group.items) { item in
                        row(item)
                        Hairline()
                    }
                }
            } else {
                ForEach(items) { item in
                    row(item)
                    Hairline()
                }
            }
            quickAdd
            suggested
        }
    }

    // MARK: Suggested

    @ViewBuilder
    private var suggested: some View {
        if model.suggestionsLocked {
            Hairline()
            HStack(spacing: 8) {
                Image(systemName: "lock")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.inkSecondary)
                Text("Calendar suggestions are part of Pro")
                    .font(.secondaryText)
                    .foregroundStyle(Color.inkSecondary)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 40)
            .accessibilityElement(children: .combine)
        } else if !model.suggestions.isEmpty {
            Hairline()
            Text(suggestedHeader)
                .font(.metaText)
                .foregroundStyle(Color.inkSecondary)
                .padding(.top, 10)
                .padding(.bottom, 2)
            ForEach(model.suggestions) { suggestion in
                SuggestionRow(
                    suggestion: suggestion,
                    memberName: model.member(suggestion.forMember)?.name,
                    onAdd: { Task { await model.addSuggestion(suggestion) } },
                    onNotToday: { model.dismissSuggestion(suggestion) },
                    onNever: { Task { await model.neverSuggest(suggestion) } })
                Hairline()
            }
        }
    }

    private var suggestedHeader: String {
        if let day = model.suggestionsDay, !model.calendar.isDate(day, inSameDayAs: model.now) {
            return "Suggested from tomorrow's calendar"
        }
        return "Suggested from today's calendar"
    }

    private struct MemberGroup {
        let key: String
        let label: String
        let items: [ChecklistItem]
    }

    private func groups(_ items: [ChecklistItem]) -> [MemberGroup] {
        var order: [String] = []
        var buckets: [String: [ChecklistItem]] = [:]
        for item in items {
            let key = item.forMember?.uuidString ?? "household"
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(item)
        }
        return order.map { key in
            let label = key == "household" ? "Household" : (model.member(UUID(uuidString: key))?.name ?? "Household")
            return MemberGroup(key: key, label: label, items: buckets[key] ?? [])
        }
    }

    private var allDone: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.appAccentColor)
            Text("All done")
                .font(.bodyText)
                .foregroundStyle(Color.inkPrimary)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Add the things you do every morning")
                .font(.bodyText)
                .foregroundStyle(Color.inkPrimary)
            quickAdd
        }
    }

    /// "+ Add an item" text row; the accent glyph is the one call to action in the block.
    private var quickAdd: some View {
        Button { addingNew = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appAccentColor)
                    .frame(width: 16)
                Text("Add an item")
                    .font(.secondaryText)
                    .foregroundStyle(Color.inkPrimary)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(!model.canAddItem)
        .opacity(model.canAddItem ? 1 : 0.4)
        .accessibilityLabel("Add an item")
    }

    // MARK: Row

    private func row(_ item: ChecklistItem) -> some View {
        TodayRow(
            item: item,
            isDone: model.isDone(item),
            isSkipped: model.isSkipped(item),
            memberInitial: grouped ? model.member(item.forMember)?.initial : nil,
            hourly: hourlyStatus(item),
            marks: model.recentMarks(item),
            timerEndsAt: model.timerEndsAt(item),
            onToggle: { Task { await model.toggle(item) } },
            onStartTimer: item.kind.isTimer ? { Task { await model.startTimer(item) } } : nil,
            onStopTimer: item.kind.isTimer ? { Task { await model.stopTimer(item) } } : nil,
            onFinishTimer: item.kind.isTimer ? { Task { await model.finishTimer(item) } } : nil,
            onSkip: { Task { await model.skipToday(item) } },
            onUnskip: { Task { await model.unskipToday(item) } },
            onEdit: { editing = item },
            onNotes: item.notes.isEmpty ? nil : { notesFor = item }
        )
    }

    private func hourlyStatus(_ item: ChecklistItem) -> TodayRow.HourlyStatus? {
        guard item.recurrence.isHourly else { return nil }
        let total = item.slotCount(on: model.now, calendar: model.calendar)
        let done = model.ledger.doneSlots(for: item, on: model.now, calendar: model.calendar).count
        let next = model.ledger.nextSlot(for: item, at: model.now, calendar: model.calendar)
        return TodayRow.HourlyStatus(done: min(done, total), total: total, next: next)
    }
}

/// One proposal: "+ Pack soccer bag (Riley, practice 4:00 PM)" with Add / Not today; long
/// press for Never for this. Nothing is added silently.
struct SuggestionRow: View {
    let suggestion: Suggestion
    let memberName: String?
    let onAdd: () -> Void
    let onNotToday: () -> Void
    let onNever: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.inkSecondary)
                .frame(width: 16)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                    .font(.bodyText)
                    .foregroundStyle(Color.inkPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(suggestion.caption(memberName: memberName))
                    .font(.metaText)
                    .foregroundStyle(Color.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            // Actions sit on the title line, so the stack is top-aligned with a fixed 16 pt gap.
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Button("Add", action: onAdd)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appAccentColor)
                    .buttonStyle(.plain)
                Button("Not today", action: onNotToday)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.inkSecondary)
                    .buttonStyle(.plain)
            }
            .fixedSize()
            .padding(.top, 2)
        }
        .padding(.vertical, 8)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) { onNever() } label: { Label("Never for this", systemImage: "hand.raised") }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggested: \(suggestion.title), \(suggestion.caption(memberName: memberName))")
    }
}

/// One 44 pt hairline row: circle, title, right-hand status, streak dots.
struct TodayRow: View {
    struct HourlyStatus {
        let done: Int
        let total: Int
        let next: Date?
    }

    let item: ChecklistItem
    let isDone: Bool
    let isSkipped: Bool
    /// Shown only when more than one member tag is in use today.
    let memberInitial: String?
    let hourly: HourlyStatus?
    let marks: [ChecklistLedger.DayMark]
    /// Running timer's end; nil when idle or not a timer item.
    var timerEndsAt: Date? = nil
    let onToggle: () -> Void
    var onStartTimer: (() -> Void)? = nil
    var onStopTimer: (() -> Void)? = nil
    var onFinishTimer: (() -> Void)? = nil
    let onSkip: () -> Void
    let onUnskip: () -> Void
    let onEdit: () -> Void
    var onNotes: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: tap) {
            HStack(spacing: 12) {
                circle
                Text(item.title)
                    .font(.bodyText)
                    .foregroundStyle(isDone || isSkipped ? Color.inkSecondary : Color.inkPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                trailing
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(isDone ? "Double tap to undo" : "Double tap to mark done")
        .contextMenu {
            if item.kind.isTimer, !isDone, !isSkipped {
                if timerEndsAt != nil, let onStopTimer {
                    Button { onStopTimer() } label: { Label("Stop timer", systemImage: "stop") }
                } else if let onStartTimer {
                    Button { onStartTimer() } label: { Label("Start timer", systemImage: "play") }
                }
            }
            if isSkipped {
                Button { onUnskip() } label: { Label("Undo skip", systemImage: "arrow.uturn.backward") }
            } else if !isDone {
                Button { onSkip() } label: { Label("Skip today", systemImage: "forward") }
            }
            if let onNotes {
                Button { onNotes() } label: { Label("Notes", systemImage: "text.alignleft") }
            }
            Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
        }
    }

    // MARK: Trailing columns

    /// Fixed slots, right to left: streak dots, member chip, status text, play glyph. Every row
    /// reserves every slot so the columns line up down the list.
    private enum Slot {
        static let play: CGFloat = 20
        static let status: CGFloat = 64
        static let chip: CGFloat = 20
        static let dots: CGFloat = 7 * 4 + 6 * 3
        static let gap: CGFloat = 8
    }

    private var trailing: some View {
        HStack(spacing: Slot.gap) {
            playSlot
                .frame(width: Slot.play, height: 28)
            statusSlot
                .frame(width: Slot.status, alignment: .trailing)
            Group {
                if let memberInitial {
                    MemberInitialChip(initial: memberInitial, size: Slot.chip)
                } else {
                    Color.clear
                }
            }
            .frame(width: Slot.chip, height: Slot.chip)
            streakDots
                .frame(width: Slot.dots, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var playSlot: some View {
        if case .timer(let minutes) = item.kind, !isDone, !isSkipped, timerEndsAt == nil, let onStartTimer {
            Button(action: onStartTimer) {
                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.appAccentColor)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start \(minutes) minute timer")
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var statusSlot: some View {
        if isSkipped {
            statusText("Skipped")
        } else if let hourly {
            statusText(hourlyText(hourly))
        } else if let timerEndsAt, !isDone {
            countdown(until: timerEndsAt)
        } else if case .timer(let minutes) = item.kind {
            statusText("\(minutes) min")
        } else {
            Color.clear
        }
    }

    private func statusText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium).monospacedDigit())
            .foregroundStyle(Color.inkSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// Live "12:34" countdown, one tick a second. Tapping the row while it runs checks the item.
    private func countdown(until end: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(end.timeIntervalSince(context.date).rounded(.up)))
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.system(size: 11, weight: .semibold))
                Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Color.appAccentColor)
            .accessibilityLabel("\(remaining / 60) minutes \(remaining % 60) seconds left")
        }
    }

    /// 16 pt circle: hairline ring when undone, accent fill with a white check when done, hollow
    /// dash when skipped.
    private var circle: some View {
        ZStack {
            Circle()
                .strokeBorder(isDone ? Color.appAccentColor : Color.inkSecondary.opacity(0.6), lineWidth: 1.5)
            Circle()
                .fill(Color.appAccentColor)
                .scaleEffect(isDone ? 1 : (reduceMotion ? 1 : 0.4))
                .opacity(isDone ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .opacity(isDone ? 1 : 0)
            if isSkipped, !isDone {
                Rectangle().fill(Color.inkSecondary).frame(width: 6, height: 1.5)
            }
        }
        .frame(width: 16, height: 16)
        .animation(.easeOut(duration: 0.2), value: isDone)
    }

    /// Last seven scheduled days, oldest left, 4 pt dots: done = ink fill, missed = hairline
    /// ring, skipped = secondary ring.
    private var streakDots: some View {
        HStack(spacing: 3) {
            ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                switch mark {
                case .done: Circle().fill(Color.inkPrimary).frame(width: 4, height: 4)
                case .missed: Circle().strokeBorder(Color.hairline, lineWidth: 1).frame(width: 4, height: 4)
                case .skipped: Circle().strokeBorder(Color.inkSecondary, lineWidth: 1).frame(width: 4, height: 4)
                }
            }
        }
        .accessibilityLabel(streakLabel)
    }

    private var streakLabel: String {
        let done = marks.filter { $0 == .done }.count
        return "\(done) of \(marks.count) days done"
    }

    /// "2/6 · 12:00": compact so it never reads like the header's "2 of 6".
    private func hourlyText(_ s: HourlyStatus) -> String {
        if let next = s.next, s.done < s.total {
            let time = next.formatted(Date.FormatStyle().hour(.defaultDigits(amPM: .omitted)).minute())
            return "\(s.done)/\(s.total) · \(time)"
        }
        return "\(s.done)/\(s.total)"
    }

    private var accessibilityText: String {
        var parts = [item.title]
        if isSkipped { parts.append("skipped today") } else if isDone { parts.append("done") } else { parts.append("not done") }
        if let hourly { parts.append("\(hourly.done) of \(hourly.total)") }
        return parts.joined(separator: ", ")
    }

    private func tap() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        // A running timer ends early on tap and the item checks itself.
        if timerEndsAt != nil, !isDone, let onFinishTimer {
            onFinishTimer()
        } else {
            onToggle()
        }
    }
}

#Preview("Today") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    return ScrollView {
        VStack(spacing: 28) {
            BriefingSectionCard(section: BriefingSection(id: "today", title: "Today", icon: "checklist", content: "", sentiment: nil),
                                checklist: ChecklistViewModel.preview())
            BriefingSectionCard(section: BriefingSection(id: "today", title: "Today", icon: "checklist", content: "", sentiment: nil),
                                checklist: ChecklistViewModel.previewEmpty())
        }
        .padding(20)
    }
    .background(Color.backgroundColor)
}

#Preview("Today, suggestions") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    let model = ChecklistViewModel.preview()
    model.setPreviewSuggestions(Suggestion.sample)
    let locked = ChecklistViewModel.preview()
    locked.setPreviewSuggestions([], locked: true)
    return ScrollView {
        VStack(spacing: 28) {
            BriefingSectionCard(section: BriefingSection(id: "today", title: "Today", icon: "checklist", content: "", sentiment: nil),
                                checklist: model)
            BriefingSectionCard(section: BriefingSection(id: "today", title: "Today", icon: "checklist", content: "", sentiment: nil),
                                checklist: locked)
        }
        .padding(20)
    }
    .background(Color.backgroundColor)
}

#Preview("Today, timer running") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    let model = ChecklistViewModel.preview()
    return ScrollView {
        BriefingSectionCard(section: BriefingSection(id: "today", title: "Today", icon: "checklist", content: "", sentiment: nil),
                            checklist: model)
            .padding(20)
    }
    .background(Color.backgroundColor)
    .task { await model.startTimer(ChecklistItem.sample[2]) }
}

#Preview("Today, dark, all done") {
    ThemeStore.shared.themeRaw = AppTheme.dark.rawValue
    let model = ChecklistViewModel.preview()
    return ScrollView {
        BriefingSectionCard(section: BriefingSection(id: "today", title: "Today", icon: "checklist", content: "", sentiment: nil),
                            checklist: model)
            .padding(20)
    }
    .background(Color.backgroundColor)
    .preferredColorScheme(.dark)
    .task {
        for item in model.scheduledToday where !model.isDone(item) {
            if item.recurrence.isHourly {
                let done = model.ledger.doneSlots(for: item, on: model.now, calendar: model.calendar)
                for slot in 0..<item.slotCount(on: model.now, calendar: model.calendar) where !done.contains(slot) {
                    await model.toggle(item, slotIndex: slot)
                }
            } else {
                await model.toggle(item)
            }
        }
    }
}
