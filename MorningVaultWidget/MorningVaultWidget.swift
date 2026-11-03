import SwiftUI
import WidgetKit

// MorningVault widget: shows the one thing Apple's own widgets can't — today's AI summary
// (plus the next event and the top headline line on the larger size). Weather and calendar
// already have Apple widgets, so they appear here only as small context, never as the point.
//
// Reads the App Group snapshot the app saves; the widget never loads Health, Calendar,
// the network or the model itself. Summary text is marked privacy-sensitive, so on the
// Lock Screen it is hidden until the iPhone is unlocked.

struct SummaryEntry: TimelineEntry {
    let date: Date
    let briefing: SharedBriefing?
}

struct SummaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> SummaryEntry {
        SummaryEntry(date: Date(), briefing: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SummaryEntry) -> Void) {
        completion(SummaryEntry(date: Date(), briefing: context.isPreview ? .sample : SharedBriefingStore.loadToday()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryEntry>) -> Void) {
        let now = Date()
        let entry = SummaryEntry(date: now, briefing: SharedBriefingStore.loadToday())
        // The app pushes reloads whenever it saves; this is just the backstop, plus a refresh
        // right after midnight so yesterday's summary never lingers.
        let nextHour = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now.addingTimeInterval(3600)
        let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 1),
                                                 matchingPolicy: .nextTime) ?? nextHour
        completion(Timeline(entries: [entry], policy: .after(min(nextHour, midnight))))
    }
}

struct SummaryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SummaryEntry

    private var summary: String? { entry.briefing?.summary }
    private let empty = "Open MorningVault for today's summary."

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(summary ?? "MorningVault")
                .privacySensitive()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Today", systemImage: "sparkles")
                    .font(.caption2.weight(.semibold))
                Text(summary ?? empty)
                    .font(.caption)
                    .lineLimit(3)
                    .privacySensitive()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemMedium:
            VStack(alignment: .leading, spacing: 6) {
                header
                Text(summary ?? empty)
                    .font(.subheadline)
                    .lineLimit(4)
                    .privacySensitive()
                Spacer(minLength: 0)
                footer
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                header
                Text(summary ?? empty)
                    .font(.footnote)
                    .lineLimit(6)
                    .minimumScaleFactor(0.85)
                    .privacySensitive()
                Spacer(minLength: 0)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
            Text("Today")
            Spacer()
            if let w = entry.briefing?.weatherLine {
                Text(w).foregroundStyle(.secondary)
            }
        }
        .font(.caption.weight(.semibold))
    }

    @ViewBuilder
    private var footer: some View {
        if let title = entry.briefing?.firstEventTitle, let start = entry.briefing?.firstEventStart, start > entry.date {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                Text(start, style: .time)
                Text(title).lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .privacySensitive()
        } else if let h = entry.briefing?.headlines.first {
            HStack(spacing: 4) {
                Image(systemName: "newspaper")
                Text(h.gist ?? h.title).lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct MorningVaultSummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MorningVaultSummary", provider: SummaryProvider()) { entry in
            SummaryWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Morning Summary")
        .description("Today's summary from MorningVault, written on your iPhone.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct MorningVaultWidgetBundle: WidgetBundle {
    var body: some Widget {
        MorningVaultSummaryWidget()
    }
}

extension SharedBriefing {
    static let sample = SharedBriefing(
        day: SharedBriefing.today(),
        summary: "Light morning: one meeting at 10, mild and dry. Markets opened flat.",
        firstEventTitle: "Team sync",
        firstEventStart: Date().addingTimeInterval(3600),
        weatherLine: "18° Clear",
        headlines: [.init(title: "Sample headline", gist: "What happened and why it matters.", source: nil)],
        updatedAt: Date()
    )
}
