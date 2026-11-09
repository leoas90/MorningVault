import AppIntents
import SwiftUI
import WidgetKit

// Water widget: the progress ring and the amount to go, with a button that runs
// `LogWaterIntent(ml: 250)` in place (no app launch). Reads `water_today_v1`, written by the
// store after every change; the store asks for a reload of this kind.

struct WaterEntryTimeline: TimelineEntry {
    let date: Date
    let snapshot: WaterTodaySnapshot?
}

struct WaterProvider: TimelineProvider {
    func placeholder(in context: Context) -> WaterEntryTimeline {
        WaterEntryTimeline(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (WaterEntryTimeline) -> Void) {
        completion(WaterEntryTimeline(date: Date(), snapshot: context.isPreview ? .sample : Self.current()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WaterEntryTimeline>) -> Void) {
        let now = Date()
        let entry = WaterEntryTimeline(date: now, snapshot: Self.current())
        let nextHour = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now.addingTimeInterval(3600)
        let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime) ?? nextHour
        completion(Timeline(entries: [entry], policy: .after(min(nextHour, midnight))))
    }

    /// Today's snapshot, or nil when the tracker is off or the snapshot is from another day.
    static func current() -> WaterTodaySnapshot? {
        guard WaterSettings.isEnabled(), let snapshot = WaterSnapshotStore.load(), snapshot.isToday() else {
            // Tracker on but nothing logged today yet: show the goal with zero.
            if WaterSettings.isEnabled() {
                let goal = WaterSettings.tracker().goalML
                return WaterTodaySnapshot(day: ChecklistDay.key(for: Date()), goalML: goal, loggedML: 0, entries: [], quietToday: false)
            }
            return nil
        }
        return snapshot
    }
}

struct WaterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WaterEntryTimeline

    private var snapshot: WaterTodaySnapshot? { entry.snapshot }
    private var units: UnitsPreference { UnitsPreference.current }

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
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
                    Text("WATER")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    if let s = snapshot {
                        Text(s.isGoalMet ? "Done" : units.formatVolumeNumber(ml: s.remainingML))
                            .font(.system(size: 17, weight: .semibold).monospacedDigit())
                        Text(s.isGoalMet ? "Goal met" : "\(units.volumeUnitLabel) to go")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            if let s = snapshot {
                HStack(spacing: 8) {
                    Button(intent: LogWaterIntent(ml: 250)) {
                        Label("Log \(units.formatVolume(ml: 250))", systemImage: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                    .accessibilityLabel("Log \(units.formatVolume(ml: 250)) of water")
                }
                .accessibilityValue("\(units.formatVolume(ml: s.loggedML)) of \(units.formatVolume(ml: s.goalML))")
            } else {
                Text("Open MorningVault to turn on the water tracker.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func ring(size: CGFloat, lineWidth: CGFloat) -> some View {
        let fraction = snapshot?.progress ?? 0
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
            } else {
                Image(systemName: "drop")
                    .font(.system(size: size * 0.3, weight: .medium))
                    .foregroundStyle(.tint)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(snapshot.map { "\(units.formatVolume(ml: $0.loggedML)) of \(units.formatVolume(ml: $0.goalML))" } ?? "Water")
    }

    // MARK: Lock Screen

    private var circular: some View {
        Gauge(value: snapshot?.progress ?? 0) {
            Image(systemName: "drop")
        } currentValueLabel: {
            if let s = snapshot {
                Text(s.isGoalMet ? "Done" : units.formatVolumeNumber(ml: s.remainingML))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .minimumScaleFactor(0.6)
            } else {
                Image(systemName: "drop")
            }
        }
        .gaugeStyle(.accessoryCircular)
        .accessibilityLabel(snapshot.map { "\(units.formatVolume(ml: $0.remainingML)) of water to go" } ?? "Water")
    }
}

struct WaterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WaterWidgetReloader.widgetKind, provider: WaterProvider()) { entry in
            WaterWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "morningvault://water"))
        }
        .configurationDisplayName("Water")
        .description("How much water is left today, and a button to log a glass.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

extension WaterTodaySnapshot {
    /// Preview and placeholder data: 750 of 2,000 mL.
    static let sample: WaterTodaySnapshot = {
        let start = Calendar.current.startOfDay(for: Date())
        return WaterTodaySnapshot(day: ChecklistDay.key(for: Date()), goalML: 2000, loggedML: 750,
                                  entries: [WaterEntry(ts: start.addingTimeInterval(8 * 3600), ml: 250),
                                            WaterEntry(ts: start.addingTimeInterval(10 * 3600), ml: 500)],
                                  quietToday: false)
    }()
}

#Preview("Water small", as: .systemSmall) {
    WaterWidget()
} timeline: {
    WaterEntryTimeline(date: .now, snapshot: .sample)
    WaterEntryTimeline(date: .now, snapshot: WaterTodaySnapshot(day: ChecklistDay.key(for: Date()), goalML: 2000, loggedML: 2000, entries: [], quietToday: false))
    WaterEntryTimeline(date: .now, snapshot: nil)
}

#Preview("Water circular", as: .accessoryCircular) {
    WaterWidget()
} timeline: {
    WaterEntryTimeline(date: .now, snapshot: .sample)
}
