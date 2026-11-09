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

    /// Nil when the Day summary section is off in Settings (the snapshot drops it too).
    private var summary: String? { BriefSectionPrefs.isEnabled("summary") ? entry.briefing?.summary : nil }
    private let empty = "Open MorningVault for today's summary."

    // Composition per size (labels never below 12 pt):
    // small  – temperature + condition, the next event;
    // medium – adds the summary line;
    // large  – adds the greeting and the headline lines.
    // The snapshot carries no market quotes, so no market row is shown here.
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
        case .systemSmall:
            VStack(alignment: .leading, spacing: 6) {
                weatherLine(size: 28)
                Spacer(minLength: 0)
                nextEvent(lines: 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .systemMedium:
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    greetingLine
                    Spacer(minLength: 8)
                    weatherLine(size: 20)
                }
                Text(summary ?? empty)
                    .font(.system(size: 13))
                    .lineSpacing(1)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .privacySensitive()
                nextEvent(lines: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        default:
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    greetingLine
                    Spacer(minLength: 8)
                    weatherLine(size: 24)
                }
                Text(summary ?? empty)
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .privacySensitive()
                nextEvent(lines: 2)
                if let headlines = entry.briefing?.headlines, !headlines.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("HEADLINES")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ForEach(Array(headlines.prefix(2).enumerated()), id: \.offset) { _, h in
                            Text(h.gist ?? h.title)
                                .font(.system(size: 13))
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// Same greeting as the Brief header ("Good morning, Sam"), written by the app.
    private var greeting: String {
        let g = entry.briefing?.greeting?.trimmingCharacters(in: .whitespaces) ?? ""
        return g.isEmpty ? "Today" : g
    }

    private var greetingLine: some View {
        Text(greeting)
            .font(.system(size: 15, weight: .semibold, design: .serif))
            .lineLimit(1)
            .privacySensitive()
    }

    /// "64°" large with the condition under it, from the same snapshot the app shows.
    @ViewBuilder
    private func weatherLine(size: CGFloat) -> some View {
        if let c = entry.briefing?.weatherTempC, let cond = entry.briefing?.weatherCondition {
            VStack(alignment: .trailing, spacing: 0) {
                Text(UnitsPreference.current.formatTemperatureShort(celsius: c))
                    .font(.system(size: size, weight: .medium, design: .serif).monospacedDigit())
                Text(cond)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else if let w = entry.briefing?.displayWeatherLine {
            Text(w).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func nextEvent(lines: Int) -> some View {
        if BriefSectionPrefs.isEnabled("next"), let title = entry.briefing?.firstEventTitle, let start = entry.briefing?.firstEventStart, start > entry.date {
            VStack(alignment: .leading, spacing: 2) {
                Text("NEXT")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(start, style: .time)
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(lines)
                }
            }
            .privacySensitive()
        } else if let h = entry.briefing?.headlines.first {
            HStack(spacing: 4) {
                Image(systemName: "newspaper")
                Text(h.gist ?? h.title).lineLimit(lines)
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
        }
    }
}

struct MorningVaultSummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MorningVaultSummary", provider: SummaryProvider()) { entry in
            SummaryWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "morningvault://briefing"))
        }
        .configurationDisplayName("Morning Summary")
        .description("Today's summary from MorningVault, written on your iPhone.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct MorningVaultWidgetBundle: WidgetBundle {
    var body: some Widget {
        MorningVaultSummaryWidget()
        MorningVaultMeetingsWidget()
        TodayWidget()
        RecordingLiveActivityWidget()
    }
}

extension SharedBriefing {
    /// Same day as the app's previews: 64°F clear, standup at nine, the same summary.
    static let sample = SharedBriefing(
        day: SharedBriefing.today(),
        summary: "A mild morning with three meetings, the first at nine. Markets opened lower, so the standup is the only thing that needs your attention early.",
        firstEventTitle: "Standup",
        firstEventStart: Calendar.current.nextDate(after: Date(), matching: DateComponents(hour: 9, minute: 0), matchingPolicy: .nextTime) ?? Date().addingTimeInterval(3600),
        weatherLine: "64°F, Clear",
        weatherTempC: 18,
        weatherCondition: "Clear",
        headlines: [.init(title: "Fed holds rates steady as inflation cools", gist: nil, source: nil),
                    .init(title: "Apple previews on-device models for iOS 27", gist: nil, source: nil)],
        updatedAt: Date(),
        greeting: "Good morning, Sam"
    )
}

#Preview("Widget · small", as: .systemSmall) {
    MorningVaultSummaryWidget()
} timeline: {
    SummaryEntry(date: Date(), briefing: .sample)
}

#Preview("Widget · medium", as: .systemMedium) {
    MorningVaultSummaryWidget()
} timeline: {
    SummaryEntry(date: Date(), briefing: .sample)
}

#Preview("Widget · large", as: .systemLarge) {
    MorningVaultSummaryWidget()
} timeline: {
    SummaryEntry(date: Date(), briefing: .sample)
}
