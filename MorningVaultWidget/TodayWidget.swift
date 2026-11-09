import AppIntents
import SwiftUI
import WidgetKit

// Today widget: the household checklist's progress and the next open item, with a check
// button that runs `MarkDoneIntent` in place (no app launch). Reads `checklist_today_v1`,
// written by the store after every change; the store asks for a reload of this kind.
// Titles are privacy-sensitive (meds, kids' names): hidden on a locked Lock Screen.

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: ChecklistTodaySnapshot?
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(TodayEntry(date: Date(), snapshot: context.isPreview ? .sample : Self.current()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        let entry = TodayEntry(date: now, snapshot: Self.current())
        // The store pushes reloads on every write; refresh after midnight so yesterday's list
        // never lingers, and hourly as a backstop.
        let nextHour = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now.addingTimeInterval(3600)
        let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime) ?? nextHour
        completion(Timeline(entries: [entry], policy: .after(min(nextHour, midnight))))
    }

    /// Today's snapshot, or nil when the household checklist is off or the snapshot is stale.
    static func current() -> ChecklistTodaySnapshot? {
        guard BriefSectionPrefs.isHouseholdEnabled, let snapshot = ChecklistSnapshotStore.load(), snapshot.isToday else { return nil }
        return snapshot
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    private var snapshot: ChecklistTodaySnapshot? { entry.snapshot }
    private var undone: [ChecklistTodaySnapshot.Item] { snapshot?.items.filter { !$0.isDone } ?? [] }

    var body: some View {
        switch family {
        case .accessoryInline:
            inline
        case .accessoryRectangular:
            rectangular
        default:
            small
        }
    }

    // MARK: Small

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                ring(size: 44, lineWidth: 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text("TODAY")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    if let s = snapshot {
                        Text("\(s.done) of \(s.total)")
                            .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    }
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            if let s = snapshot {
                if s.total == 0 {
                    Text("Nothing scheduled today.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else if let next = undone.first {
                    HStack(spacing: 8) {
                        Button(intent: MarkDoneIntent(itemID: next.id, title: next.title)) {
                            Image(systemName: "circle")
                                .font(.system(size: 20, weight: .regular))
                                .foregroundStyle(.tint)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Mark \(next.title) done")
                        Text(next.title)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(2)
                            .privacySensitive()
                    }
                } else {
                    Label("All done", systemImage: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                }
            } else {
                Text("Open MorningVault to set up the household checklist.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Done / total as an arc. Hairline track, tinted progress; a full ring when everything is done.
    private func ring(size: CGFloat, lineWidth: CGFloat) -> some View {
        let fraction: Double = {
            guard let s = snapshot, s.total > 0 else { return 0 }
            return min(1, Double(s.done) / Double(s.total))
        }()
        return ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if fraction >= 1 {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.32, weight: .bold))
                    .foregroundStyle(.tint)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(snapshot.map { "\($0.done) of \($0.total) done" } ?? "Checklist")
    }

    // MARK: Lock Screen

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("Today", systemImage: "checklist")
                .font(.caption2.weight(.semibold))
            if let s = snapshot {
                Text(Self.summaryLine(s))
                    .font(.caption)
                    .lineLimit(2)
                    .privacySensitive()
            } else {
                Text("Household checklist is off.")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        Text(snapshot.map(Self.summaryLine) ?? "MorningVault")
            .privacySensitive()
    }

    /// "3 of 6 · Walk, Piano"; "All done" when complete; "Nothing today" when empty.
    static func summaryLine(_ s: ChecklistTodaySnapshot) -> String {
        guard s.total > 0 else { return "Nothing today" }
        if s.done >= s.total { return "\(s.done) of \(s.total) · All done" }
        let next = s.nextUndoneTitles.prefix(2).joined(separator: ", ")
        return next.isEmpty ? "\(s.done) of \(s.total)" : "\(s.done) of \(s.total) · \(next)"
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ChecklistWidgetReloader.widgetKind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "morningvault://briefing"))
        }
        .configurationDisplayName("Today")
        .description("Your household checklist: what is done, and the next thing to check off.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

extension ChecklistTodaySnapshot {
    /// Preview and placeholder data: the fictional household, two of six done.
    static let sample: ChecklistTodaySnapshot = {
        let titles = ["Pack lunches", "Kids' meds", "Walk", "Stretch", "Water the plants", "Read 10 min"]
        let items = titles.enumerated().map { index, title in
            ChecklistTodaySnapshot.Item(id: UUID(), title: title, forInitial: nil, isDone: index < 2, nextSlot: nil)
        }
        return ChecklistTodaySnapshot(day: ChecklistTodaySnapshot.dayKey(Date()), done: 2, total: 6,
                                      nextUndoneTitles: ["Walk", "Stretch", "Water the plants"], items: items, updatedAt: Date())
    }()
}

#Preview("Today small", as: .systemSmall) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, snapshot: .sample)
    TodayEntry(date: .now, snapshot: ChecklistTodaySnapshot(day: ChecklistTodaySnapshot.dayKey(Date()), done: 3, total: 3,
                                                           nextUndoneTitles: [], items: [], updatedAt: .now))
    TodayEntry(date: .now, snapshot: nil)
}

#Preview("Today rectangular", as: .accessoryRectangular) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, snapshot: .sample)
}

#Preview("Today inline", as: .accessoryInline) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, snapshot: .sample)
}
