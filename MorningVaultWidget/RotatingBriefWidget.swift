import AppIntents
import SwiftUI
import WidgetKit

// Rotating Brief widget: one section at a time (weather, next event, markets, today's
// checklist, water, headlines), moving to the next page every twelve minutes or on a tap.
// The pages are pre-generated as timeline entries for six hours, so rotation costs no
// refresh budget; the app's stores ask for a reload when their snapshots change.
//
// Text only. Reads the App Group snapshots the app writes; never loads Health, Calendar
// or the network. Page selection lives in `RotatingBriefPages` (Shared) so it is testable.

struct RotatingBriefEntry: TimelineEntry {
    let date: Date
    let page: RotatingBriefPage
    let pageIndex: Int
    let pageCount: Int
    let briefing: SharedBriefing?
    let checklist: ChecklistTodaySnapshot?
    let water: WaterTodaySnapshot?

    /// No page qualified: a single weather page that asks the user to open the app.
    var isFallback: Bool { pageCount == 0 }
}

struct RotatingBriefProvider: TimelineProvider {
    func placeholder(in context: Context) -> RotatingBriefEntry {
        RotatingBriefEntry(date: Date(), page: .weather, pageIndex: 0, pageCount: 5, briefing: .sample, checklist: .sample, water: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (RotatingBriefEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            completion(Self.timeline(family: context.family, now: Date()).entries.first ?? placeholder(in: context))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RotatingBriefEntry>) -> Void) {
        completion(Self.timeline(family: context.family, now: Date()))
    }

    /// Reads the snapshots once, picks the pages, and lays them out over the next six hours.
    static func timeline(family: WidgetFamily, now: Date) -> Timeline<RotatingBriefEntry> {
        let briefing = SharedBriefingStore.loadToday()
        let checklist = TodayProvider.current()
        let water = WaterProvider.current()
        let input = RotatingBriefInput(
            enabled: Set(RotatingBriefInput.sectionIDs.filter { BriefSectionPrefs.isEnabled($0) }),
            hasWeather: briefing?.weatherTempC != nil || briefing?.weatherLine != nil,
            hasUpcomingEvent: briefing?.firstEventTitle != nil && (briefing?.firstEventStart ?? .distantPast) > now,
            marketCount: briefing?.markets?.count ?? 0,
            checklistTotal: checklist?.total ?? 0,
            hasWaterSnapshot: water != nil,
            headlineCount: briefing?.headlines.count ?? 0
        )
        let pages = RotatingBriefPages.select(input, medium: family == .systemMedium)
        let slots = RotatingBriefPages.schedule(pages: pages, offset: RotatingBriefOffsetStore.load(), start: now)
        let entries = slots.map { slot in
            RotatingBriefEntry(date: slot.date, page: slot.page, pageIndex: slot.pageIndex, pageCount: pages.count,
                               briefing: briefing, checklist: checklist, water: water)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

struct RotatingBriefWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RotatingBriefEntry

    private var isMedium: Bool { family == .systemMedium }
    private var units: UnitsPreference { UnitsPreference.current }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Group {
                if entry.isFallback {
                    fallback
                } else {
                    switch entry.page {
                    case .weather: weather
                    case .next: nextEvent
                    case .markets: markets
                    case .today: today
                    case .water: water
                    case .headlines: headlines
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Chrome

    /// Eyebrow names the page; the whole header is the tap-to-advance button.
    private var header: some View {
        Button(intent: AdvanceBriefPageIntent(nextIndex: entry.pageCount > 0 ? (entry.pageIndex + 1) % entry.pageCount : 0)) {
            HStack(spacing: 4) {
                Text(entry.page.eyebrow)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if entry.pageCount > 1 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Next page")
    }

    /// Hairline plus one 4 pt dot per page, bottom right.
    private var footer: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Rectangle().fill(.quaternary).frame(height: 0.5)
            HStack(spacing: 4) {
                ForEach(0..<max(1, entry.pageCount), id: \.self) { i in
                    Circle()
                        .fill(i == entry.pageIndex ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
                        .frame(width: 4, height: 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityHidden(true)
        }
    }

    private var fallback: some View {
        Text("Open MorningVault to fill in today's brief.")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Pages

    private var weather: some View {
        HStack(alignment: .top, spacing: 8) {
            if isMedium {
                Text(greeting)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .lineLimit(2)
                    .privacySensitive()
                Spacer(minLength: 8)
            }
            VStack(alignment: isMedium ? .trailing : .leading, spacing: 0) {
                if let c = entry.briefing?.weatherTempC {
                    Text(units.formatTemperatureShort(celsius: c))
                        .font(.system(size: isMedium ? 24 : 28, weight: .medium, design: .serif).monospacedDigit())
                    Text(entry.briefing?.weatherCondition ?? "")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(entry.briefing?.weatherLine ?? "No weather yet")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var greeting: String {
        let g = entry.briefing?.greeting?.trimmingCharacters(in: .whitespaces) ?? ""
        return g.isEmpty ? "Today" : g
    }

    @ViewBuilder
    private var nextEvent: some View {
        if let title = entry.briefing?.firstEventTitle, let start = entry.briefing?.firstEventStart {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(isMedium ? 1 : 2)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(start, style: .time)
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("in")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(start, style: .relative)
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .privacySensitive()
        } else {
            Text("Nothing else today.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private var markets: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array((entry.briefing?.markets ?? []).prefix(isMedium ? 3 : 2).enumerated()), id: \.offset) { _, m in
                HStack(spacing: 6) {
                    Text(m.symbol)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 4)
                    if isMedium {
                        Text(m.priceText)
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(m.changeText)
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(m.isPositive ? .green : .red)
                }
                .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var today: some View {
        if let s = entry.checklist {
            let undone = s.items.filter { !$0.isDone }
            VStack(alignment: .leading, spacing: 4) {
                Text("\(s.done) of \(s.total)")
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                if let first = undone.first {
                    HStack(spacing: 6) {
                        if isMedium {
                            Button(intent: MarkDoneIntent(itemID: first.id, title: first.title)) {
                                Image(systemName: "circle")
                                    .font(.system(size: 18, weight: .regular))
                                    .foregroundStyle(.tint)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Mark \(first.title) done")
                        }
                        Text(first.title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
                    if undone.count > 1 {
                        Text(undone[1].title)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.leading, isMedium ? 24 : 0)
                    }
                } else {
                    Label("All done", systemImage: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .privacySensitive()
        }
    }

    @ViewBuilder
    private var water: some View {
        if let s = entry.water {
            HStack(alignment: .center, spacing: 10) {
                waterRing(s, size: 40, lineWidth: 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.isGoalMet ? "Done" : units.formatVolumeNumber(ml: s.remainingML))
                        .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    Text(s.isGoalMet ? "Goal met" : "\(units.volumeUnitLabel) to go")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                if isMedium {
                    Spacer(minLength: 8)
                    let cup = WaterSettings.primaryCup()
                    Button(intent: LogWaterIntent(ml: cup.ml)) {
                        Label("Log \(cup.name)", systemImage: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(minHeight: 30)
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                    .accessibilityLabel("Log \(cup.name), \(units.formatVolume(ml: cup.ml)) of water")
                }
            }
            .accessibilityValue("\(units.formatVolume(ml: s.loggedML)) of \(units.formatVolume(ml: s.goalML))")
        }
    }

    private func waterRing(_ s: WaterTodaySnapshot, size: CGFloat, lineWidth: CGFloat) -> some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: s.progress)
                .stroke(.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: s.progress >= 1 ? "checkmark" : "drop")
                .font(.system(size: size * 0.3, weight: .medium))
                .foregroundStyle(.tint)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var headlines: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array((entry.briefing?.headlines ?? []).prefix(2).enumerated()), id: \.offset) { _, h in
                Text(h.gist ?? h.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
            }
        }
    }
}

struct RotatingBriefWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: RotatingBriefWidgetReloader.widgetKind, provider: RotatingBriefProvider()) { entry in
            RotatingBriefWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(entry.page.deepLink)
        }
        .configurationDisplayName("Rotating Brief")
        .description("One section of your brief at a time: weather, next event, markets, today, water and news. Tap to move on.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private extension SharedBriefing {
    static let rotatingSample: SharedBriefing = {
        var b = SharedBriefing.sample
        b.markets = [.init(symbol: "SPY", priceText: "512.30", changeText: "+0.42%", isPositive: true),
                     .init(symbol: "BTC", priceText: "68,210", changeText: "-1.10%", isPositive: false)]
        return b
    }()
}

#Preview("Rotating small", as: .systemSmall) {
    RotatingBriefWidget()
} timeline: {
    RotatingBriefEntry(date: .now, page: .weather, pageIndex: 0, pageCount: 5, briefing: .rotatingSample, checklist: .sample, water: .sample)
    RotatingBriefEntry(date: .now, page: .next, pageIndex: 1, pageCount: 5, briefing: .rotatingSample, checklist: .sample, water: .sample)
    RotatingBriefEntry(date: .now, page: .markets, pageIndex: 2, pageCount: 5, briefing: .rotatingSample, checklist: .sample, water: .sample)
    RotatingBriefEntry(date: .now, page: .today, pageIndex: 3, pageCount: 5, briefing: .rotatingSample, checklist: .sample, water: .sample)
    RotatingBriefEntry(date: .now, page: .water, pageIndex: 4, pageCount: 5, briefing: .rotatingSample, checklist: .sample, water: .sample)
    RotatingBriefEntry(date: .now, page: .weather, pageIndex: 0, pageCount: 0, briefing: nil, checklist: nil, water: nil)
}

#Preview("Rotating medium", as: .systemMedium) {
    RotatingBriefWidget()
} timeline: {
    RotatingBriefEntry(date: .now, page: .weather, pageIndex: 0, pageCount: 6, briefing: .rotatingSample, checklist: .sample, water: .sample)
    RotatingBriefEntry(date: .now, page: .next, pageIndex: 1, pageCount: 6, briefing: .rotatingSample, checklist: .sample, water: .sample)
    RotatingBriefEntry(date: .now, page: .markets, pageIndex: 2, pageCount: 6, briefing: .rotatingSample, checklist: .sample, water: .sample)
    RotatingBriefEntry(date: .now, page: .today, pageIndex: 3, pageCount: 6, briefing: .rotatingSample, checklist: .sample, water: .sample)
    RotatingBriefEntry(date: .now, page: .water, pageIndex: 4, pageCount: 6, briefing: .rotatingSample, checklist: .sample, water: .sample)
    RotatingBriefEntry(date: .now, page: .headlines, pageIndex: 5, pageCount: 6, briefing: .rotatingSample, checklist: .sample, water: .sample)
}
