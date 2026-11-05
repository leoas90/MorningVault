import SwiftUI
import WidgetKit

// Meetings widget: the next calendar meeting with a Record shortcut, the last meeting and
// what is still open. Reads only the `MeetingsSnapshot` the Meetings package writes to the
// App Group; no SwiftData, EventKit, audio or model code runs here. Titles and action
// items are privacy-sensitive, so the Lock Screen blurs them until the iPhone is unlocked.

struct MeetingsEntry: TimelineEntry {
    let date: Date
    let snapshot: MeetingsSnapshot

    var next: MeetingsSnapshot.NextMeeting? { snapshot.upcomingMeeting(at: date) }
}

struct MeetingsProvider: TimelineProvider {
    func placeholder(in context: Context) -> MeetingsEntry {
        MeetingsEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (MeetingsEntry) -> Void) {
        let snapshot = context.isPreview ? MeetingsSnapshot.sample : (MeetingsSnapshotStore.load() ?? MeetingsSnapshot())
        completion(MeetingsEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MeetingsEntry>) -> Void) {
        let now = Date()
        let snapshot = MeetingsSnapshotStore.load() ?? MeetingsSnapshot()
        var entries = [MeetingsEntry(date: now, snapshot: snapshot)]
        // The countdown text updates on its own; the layout only has to change when the
        // meeting starts (countdown becomes "now") and when it ends (it drops off).
        if let next = snapshot.upcomingMeeting(at: now) {
            for date in [next.start, next.end] where date > now {
                entries.append(MeetingsEntry(date: date, snapshot: snapshot))
            }
        }
        let nextHour = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: entries, policy: .after(nextHour)))
    }
}

// MARK: - Views

struct MeetingsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MeetingsEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        case .accessoryInline:
            Text(inlineText).privacySensitive()
                .widgetURL(primaryURL)
        case .systemMedium:
            medium
        default:
            small
        }
    }

    /// Where a tap on the whole widget goes (small sizes have a single target).
    private var primaryURL: URL {
        if entry.snapshot.isRecording { return MeetingsDeepLink.meetings.url }
        if let next = entry.next { return MeetingsDeepLink.record(calendarEventID: next.calendarEventID).url }
        return MeetingsDeepLink.meetings.url
    }

    // MARK: Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if entry.snapshot.isRecording {
                recordingLine
                Spacer(minLength: 0)
            } else if let next = entry.next {
                Text(next.title)
                    .font(.headline)
                    .lineLimit(2)
                    .privacySensitive()
                countdown(for: next)
                Spacer(minLength: 0)
                recordBadge
            } else {
                Text("No more meetings today")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 0)
                lastMeetingLine
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(primaryURL)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                header
                if entry.snapshot.isRecording {
                    recordingLine
                    Spacer(minLength: 0)
                    Link(destination: MeetingsDeepLink.meetings.url) {
                        Label("Open", systemImage: "waveform")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.fill.secondary, in: Capsule())
                    }
                } else if let next = entry.next {
                    Text(next.title)
                        .font(.headline)
                        .lineLimit(2)
                        .privacySensitive()
                    countdown(for: next)
                    if !next.attendeeNames.isEmpty {
                        Text(next.attendeeNames.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .privacySensitive()
                    }
                    Spacer(minLength: 0)
                    Link(destination: MeetingsDeepLink.record(calendarEventID: next.calendarEventID).url) {
                        recordBadge
                    }
                } else {
                    Text("No more meetings today")
                        .font(.subheadline.weight(.semibold))
                    lastMeetingLine
                    Spacer(minLength: 0)
                    Link(destination: MeetingsDeepLink.record(calendarEventID: nil).url) {
                        recordBadge
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Image(systemName: "checklist")
                    Text(openItemsTitle)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                if entry.snapshot.openItems.isEmpty {
                    Text("Nothing open")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(entry.snapshot.openItems.enumerated()), id: \.offset) { _, item in
                        Link(destination: MeetingsDeepLink.open(meetingID: item.meetingID).url) {
                            HStack(alignment: .top, spacing: 5) {
                                Image(systemName: "circle")
                                    .font(.caption2)
                                    .padding(.top, 2)
                                Text(item.text)
                                    .font(.caption)
                                    .lineLimit(2)
                            }
                        }
                        .privacySensitive()
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .widgetURL(primaryURL)
    }

    // MARK: Lock Screen

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: entry.snapshot.isRecording ? "waveform" : "record.circle")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                Text(entry.snapshot.isRecording ? "Rec" : "Record")
                    .font(.system(size: 9, weight: .semibold))
            }
        }
        .widgetURL(entry.snapshot.isRecording ? MeetingsDeepLink.meetings.url : MeetingsDeepLink.record(calendarEventID: entry.next?.calendarEventID).url)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if entry.snapshot.isRecording {
                Label("Recording", systemImage: "waveform")
                    .font(.caption.weight(.semibold))
                Text("Tap to open the meeting")
                    .font(.caption2)
            } else if let next = entry.next {
                Label("Next", systemImage: "record.circle")
                    .font(.caption2.weight(.semibold))
                Text(next.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .privacySensitive()
                countdown(for: next)
            } else {
                Label("Meetings", systemImage: "waveform")
                    .font(.caption2.weight(.semibold))
                Text(openItemsTitle)
                    .font(.caption)
                if let last = entry.snapshot.lastMeeting {
                    Text(last.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .privacySensitive()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(primaryURL)
    }

    private var inlineText: String {
        if entry.snapshot.isRecording { return "Recording a meeting" }
        if let next = entry.next { return "Next: \(next.title)" }
        return openItemsTitle
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 4) {
            Image(systemName: "waveform")
            Text("Meetings")
            Spacer()
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private var recordingLine: some View {
        HStack(spacing: 6) {
            Circle().fill(.red).frame(width: 8, height: 8)
            Text("Recording")
                .font(.headline)
        }
    }

    private var recordBadge: some View {
        Label("Record", systemImage: "record.circle")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(.white)
            .background(.red, in: Capsule())
    }

    @ViewBuilder
    private func countdown(for next: MeetingsSnapshot.NextMeeting) -> some View {
        if next.start > entry.date {
            HStack(spacing: 3) {
                Text("in")
                Text(next.start, style: .relative)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 3) {
                Text("Now · until")
                Text(next.end, style: .time)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var lastMeetingLine: some View {
        if let last = entry.snapshot.lastMeeting {
            VStack(alignment: .leading, spacing: 1) {
                Text(last.title)
                    .font(.caption)
                    .lineLimit(1)
                    .privacySensitive()
                Text(last.openItemCount == 0 ? "Nothing open" : "\(last.openItemCount) open item\(last.openItemCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Tap to record")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var openItemsTitle: String {
        let count = entry.snapshot.openItemCount
        switch count {
        case 0: return "No open items"
        case 1: return "1 open item"
        default: return "\(count) open items"
        }
    }
}

struct MorningVaultMeetingsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: MeetingsSnapshotStore.widgetKind, provider: MeetingsProvider()) { entry in
            MeetingsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Meetings")
        .description("Your next meeting with a Record shortcut, and what is still open.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

extension MeetingsSnapshot {
    static let sample: MeetingsSnapshot = {
        let id = UUID()
        return MeetingsSnapshot(
            nextMeeting: .init(title: "Design review", start: Date().addingTimeInterval(25 * 60),
                               end: Date().addingTimeInterval(85 * 60), calendarEventID: nil, attendeeNames: ["Ana", "Ben"]),
            lastMeeting: .init(id: id, title: "Weekly sync", date: Date().addingTimeInterval(-86_400), openItemCount: 2),
            openItemCount: 2,
            openItems: [.init(text: "Send the revised deck", meetingID: id), .init(text: "Book the offsite room", meetingID: id)],
            isRecording: false
        )
    }()
}
