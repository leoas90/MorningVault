import Combine
import SwiftData
import SwiftUI

/// What a new meeting is started for: a calendar event, nothing, or the recording that is
/// already running (reopening its page).
struct NewMeetingRequest: Identifiable {
    let id = UUID()
    var calendarEventID: String?
    var title: String = ""
    var attendees: [String] = []
    /// Reopen the page of the recording in progress instead of starting a new one.
    var resumesLive = false

    init() {}

    init(event: CalendarEventInfo) {
        calendarEventID = event.id
        title = event.title
        attendees = event.attendeeNames
    }

    static var live: NewMeetingRequest {
        var request = NewMeetingRequest()
        request.resumesLive = true
        return request
    }
}

/// Where the home screen can go.
enum HomeDestination: Hashable {
    case meeting(UUID)
    case openActions
}

/// The first screen: what is coming up (or recording right now), what was recorded,
/// and one button to start a new meeting.
struct HomeScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.meetingsTheme) private var theme
    @Query(sort: \Meeting.startedAt, order: .reverse) private var meetings: [Meeting]
    @Query(filter: #Predicate<ActionItemRecord> { $0.isDone == false }, sort: \ActionItemRecord.createdAt)
    private var openActions: [ActionItemRecord]
    @StateObject private var calendar = CalendarService()
    /// The one recording session of the tab. Owned here so the recorder's page can be
    /// closed and reopened while the meeting keeps recording.
    @StateObject private var liveSession = RecordingSession()
    @ObservedObject private var router = MeetingsRouter.shared
    @AppStorage(MarkdownCopiesSetting.key) private var saveMarkdownCopies = false
    @State private var searchText = ""
    @State private var newMeeting: NewMeetingRequest?
    @State private var showVoiceEnrollment = false
    @State private var now = Date()
    @State private var path: [HomeDestination] = []
    /// A delete that the store refused, shown until dismissed.
    @State private var saveError: UserMessage?

    /// Previews only: events shown instead of the calendar's.
    var previewEvents: [CalendarEventInfo]?
    /// Previews only: a recording shown in the hero instead of the live session's.
    var previewRecording: RecordingHeroState?

    private let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                header
                    .homeRow(top: 8, bottom: 16)

                searchField
                    .homeRow(top: 0, bottom: 20)

                if let saveError {
                    BannerView(saveError, symbol: "exclamationmark.triangle", onDismiss: { self.saveError = nil })
                        .homeRow(top: 0, bottom: 16)
                }

                if !isSearching {
                    hero
                        .homeRow(top: 0, bottom: MeetingsSpace.cardGap)

                    if !openActions.isEmpty {
                        OpenActionsStrip(count: openActions.count) {
                            path.append(.openActions)
                        }
                        .homeRow(top: 0, bottom: 0)
                    }
                }

                if meetings.isEmpty {
                    if !isSearching {
                        Button {
                            showVoiceEnrollment = true
                        } label: {
                            VStack(spacing: 0) {
                                Hairline()
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Teach it your voice")
                                            .font(MeetingsType.rowTitle)
                                            .foregroundStyle(theme.ink)
                                        Text("Half a minute of reading, so your turns are labelled You.")
                                            .font(MeetingsType.meta)
                                            .foregroundStyle(theme.inkSoft)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(theme.inkSoft.opacity(0.7))
                                }
                                .padding(.vertical, 14)
                                Hairline()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .homeRow(top: MeetingsSpace.sectionGap, bottom: 0)
                    } else {
                        EmptyStateView(symbol: "magnifyingglass", title: "No matches",
                                       message: "Nothing in your titles, notes or transcripts matches “\(searchText)”.")
                            .homeRow(top: 8, bottom: 0)
                    }
                } else if filteredMeetings.isEmpty {
                    EmptyStateView(symbol: "magnifyingglass", title: "No matches",
                                   message: "Nothing in your titles, notes or transcripts matches “\(searchText)”.")
                        .homeRow(top: 8, bottom: 0)
                } else {
                    ForEach(groupedMeetings, id: \.group) { bucket in
                        Eyebrow(bucket.group.title)
                            .homeRow(top: MeetingsSpace.sectionGap, bottom: 4)
                        ForEach(bucket.items) { meeting in
                            Button {
                                path.append(.meeting(meeting.id))
                            } label: {
                                MeetingRow(meeting: meeting, group: bucket.group, openCount: openCount(for: meeting))
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens the meeting")
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: MeetingsSpace.margin, bottom: 0, trailing: MeetingsSpace.margin))
                        }
                        .onDelete { offsets in
                            delete(offsets.map { bucket.items[$0] })
                        }
                    }
                }

                Color.clear
                    .frame(height: 24)
                    .homeRow(top: 0, bottom: 0)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .themedPageBackground()
            .hiddenNavigationBar()
            .navigationDestination(for: HomeDestination.self) { destination in
                switch destination {
                case .meeting(let meetingID):
                    if let meeting = meetings.first(where: { $0.id == meetingID }) {
                        MeetingDetailScreen(meeting: meeting)
                    } else {
                        EmptyStateView(symbol: "waveform.slash", title: "Meeting not found",
                                       message: "It may have been deleted.")
                            .padding(MeetingsSpace.margin)
                            .themedPageBackground()
                    }
                case .openActions:
                    OpenActionsScreen()
                }
            }
            .refreshable { await refresh() }
            .sheet(isPresented: $showVoiceEnrollment) {
                VoiceEnrollmentScreen()
            }
            .sheet(item: $newMeeting) { request in
                MeetingScreen(
                    session: liveSession,
                    initialTitle: request.title,
                    initialAttendees: request.attendees,
                    calendarEventID: request.calendarEventID,
                    autoStart: !request.resumesLive,
                    isModal: true
                )
                .meetingsTheme(theme)
            }
            .task {
                sweepOrphanedAudio()
                await refresh()
            }
            .onReceive(minuteTimer) { date in now = date }
            .onReceive(router.$pending) { route in
                // Emits the current route on appear and each new one (before `pending`
                // is set, so the value comes from the closure, and clearing waits a turn).
                guard let route else { return }
                Task { @MainActor in
                    router.clear(route)
                    await perform(route)
                }
            }
            .onChange(of: newMeeting?.id) { _, id in
                if id == nil { MeetingsSnapshotPublisher.publishStoreChanges(context: context) }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Meetings")
                .font(MeetingsType.pageTitle)
                .foregroundStyle(theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Menu {
                Button {
                    showVoiceEnrollment = true
                } label: {
                    Label("Your voice", systemImage: "person.wave.2")
                }
                Toggle(isOn: $saveMarkdownCopies) {
                    Label("Also save Markdown copies", systemImage: "doc.text")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(theme.ink)
                    .frame(width: MeetingsSpace.target, height: MeetingsSpace.target)
                    .contentShape(Circle())
            }
            .accessibilityLabel("More actions")
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.inkSoft)
            TextField("Search titles, notes and transcripts", text: $searchText)
                .font(MeetingsType.secondary)
                .foregroundStyle(theme.ink)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(theme.inkSoft)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(theme.surfaceColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.hairlineColor, lineWidth: 1))
    }

    // MARK: - Hero

    @ViewBuilder
    private var hero: some View {
        if let state = recordingState {
            RecordingHeroCard(
                state: state,
                layout: .home,
                onPause: {
                    if liveSession.phase == .paused { liveSession.resume() } else { liveSession.pause() }
                },
                onStop: {
                    Task { await liveSession.stop(context: context) }
                },
                onOpen: { newMeeting = .live }
            )
        } else if let event = upcomingEvents.first {
            NextMeetingCard(event: event, now: now) {
                newMeeting = NewMeetingRequest(event: event)
            }
        } else {
            QuietHeroCard(isFirstMeeting: meetings.isEmpty) {
                newMeeting = NewMeetingRequest()
            }
        }
    }

    private var recordingState: RecordingHeroState? {
        if let previewRecording { return previewRecording }
        guard liveSession.isRecording else { return nil }
        return RecordingHeroState(session: liveSession)
    }

    // MARK: - Data

    /// Removes recording folders with no meeting row (once per launch, off the
    /// main actor). The running recording, if any, is left alone.
    private func sweepOrphanedAudio() {
        let active = ActiveRecordingRegistry.shared.session?.activeRecordingID
        MeetingNotesStore.sweepOrphanedAudioOnce(
            container: context.container,
            activeRecordingIDs: active.map { [$0] } ?? []
        )
    }

    /// Reloads the calendar and republishes the widget snapshot.
    private func refresh() async {
        now = Date()
        if !ActiveRecordingRegistry.shared.isRecording {
            // A Live Activity left behind by a crash would otherwise stay on the Lock Screen.
            RecordingLiveActivity.endAll()
        }
        guard previewEvents == nil else { return }
        await calendar.loadToday()
        MeetingsSnapshotPublisher.publish(events: calendar.events, now: now, context: context)
    }

    /// Runs a route from a deep link or another tab's Record button.
    private func perform(_ route: MeetingsRoute) async {
        switch route {
        case .home:
            path.removeAll()
        case .record(let eventID, let title, let attendees):
            // One recording at a time: a tap while the recorder is up is ignored.
            guard newMeeting == nil, !ActiveRecordingRegistry.shared.isRecording else { return }
            path.removeAll()
            if let eventID, calendar.event(with: eventID) == nil {
                await calendar.loadToday()
            }
            guard newMeeting == nil else { return }
            var request = NewMeetingRequest()
            if let eventID, let event = calendar.event(with: eventID) {
                request = NewMeetingRequest(event: event)
            } else {
                request.calendarEventID = eventID
                request.title = title
                request.attendees = attendees
            }
            newMeeting = request
        case .open(let meetingID):
            guard meetings.contains(where: { $0.id == meetingID }) else { return }
            path = [.meeting(meetingID)]
        }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Today's events that have not ended yet.
    private var upcomingEvents: [CalendarEventInfo] {
        (previewEvents ?? calendar.events).filter { $0.end > now }
    }

    private var filteredMeetings: [Meeting] {
        meetings.filter { meeting in
            MeetingSearch.matches(query: searchText, fields: [meeting.title, meeting.scratchpad, meeting.transcript])
        }
    }

    private var groupedMeetings: [(group: MeetingDayGroup, items: [Meeting])] {
        MeetingDayGroup.grouped(filteredMeetings, date: \.startedAt, now: now)
    }

    private func openCount(for meeting: Meeting) -> Int {
        openActions.reduce(0) { $0 + ($1.meetingID == meeting.id ? 1 : 0) }
    }

    private func delete(_ items: [Meeting]) {
        for meeting in items {
            MeetingPersistence.delete(meeting, context: context)
        }
        do {
            try context.save()
        } catch {
            saveError = UserMessage.from(error, context: "The meeting could not be deleted.")
        }
        MeetingsSnapshotPublisher.publishStoreChanges(context: context)
    }
}

private extension View {
    /// A plain list row with the page margins and no system chrome.
    func homeRow(top: CGFloat, bottom: CGFloat) -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: top, leading: MeetingsSpace.margin, bottom: bottom, trailing: MeetingsSpace.margin))
    }
}

// MARK: - Hero cards

/// What the recording hero shows, taken from the live session (or a preview).
struct RecordingHeroState: Equatable {
    var elapsed: TimeInterval
    var isPaused: Bool
    var title: String
    /// The last thing that was recognized, or empty while nothing came in yet.
    var lastLine: String
    var levels: [Double]
    var attendees: [String] = []

    @MainActor
    init(session: RecordingSession) {
        elapsed = session.elapsed
        isPaused = session.phase == .paused
        title = session.title
        lastLine = Self.tail(of: session.transcript)
        levels = session.levelHistory
        attendees = session.attendees
    }

    init(elapsed: TimeInterval, isPaused: Bool = false, title: String, lastLine: String, levels: [Double], attendees: [String] = []) {
        self.elapsed = elapsed
        self.isPaused = isPaused
        self.title = title
        self.lastLine = lastLine
        self.levels = levels
        self.attendees = attendees
    }

    /// The last sentence or so of the transcript.
    static func tail(of transcript: String, limit: Int = 140) -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let tail = trimmed.suffix(limit)
        if let cut = tail.firstIndex(where: { $0 == "." || $0 == "?" || $0 == "!" }), tail.distance(from: cut, to: tail.endIndex) > 20 {
            return String(tail[tail.index(after: cut)...]).trimmingCharacters(in: .whitespaces)
        }
        return "…" + tail
    }
}

/// The recording in progress: timer hero, breathing dot, last line, Pause and Stop.
struct RecordingHeroCard: View {
    enum Layout { case home, page }

    @Environment(\.meetingsTheme) private var theme
    let state: RecordingHeroState
    var layout: Layout = .page
    let onPause: () -> Void
    let onStop: () -> Void
    /// Home only: tapping the card opens the recorder page.
    var onOpen: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                BreathingDot(color: state.isPaused ? theme.inkSoft : theme.negativeColor, isActive: !state.isPaused)
                Eyebrow(state.isPaused ? "Paused" : "Recording", color: state.isPaused ? nil : theme.negativeColor)
                Spacer(minLength: 8)
                if layout == .home, let onOpen {
                    Button(action: onOpen) {
                        HStack(spacing: 4) {
                            Text("Open")
                                .font(MeetingsType.metaMedium)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(theme.ink)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(theme.ink.opacity(0.06), in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open the recording")
                }
            }

            ElapsedTimeLabel(elapsed: state.elapsed)
                .padding(.top, 12)

            if layout == .page {
                LevelMeter(history: state.isPaused ? [] : state.levels, isActive: !state.isPaused, themed: true)
                    .padding(.top, 12)
            }

            if layout == .home {
                VStack(alignment: .leading, spacing: 4) {
                    if !state.title.isEmpty {
                        Text(state.title)
                            .font(MeetingsType.rowTitle)
                            .foregroundStyle(theme.ink)
                            .lineLimit(1)
                    }
                    Text(state.lastLine.isEmpty ? "Listening…" : state.lastLine)
                        .font(MeetingsType.secondary)
                        .lineSpacing(3)
                        .foregroundStyle(theme.inkSoft)
                        .lineLimit(2)
                }
                .padding(.top, 12)
            }

            if layout == .home {
                HStack(spacing: 12) {
                    MeetingsButton(
                        title: state.isPaused ? "Resume" : "Pause",
                        systemImage: state.isPaused ? "play.fill" : "pause.fill",
                        role: .secondary,
                        action: onPause
                    )
                    MeetingsButton(title: "Stop", systemImage: "stop.fill", role: .negative, action: onStop)
                }
                .padding(.top, 20)
            }
        }
        .primaryCard()
        .accessibilityElement(children: .contain)
    }
}

/// The next calendar event with the one Record button.
struct NextMeetingCard: View {
    @Environment(\.meetingsTheme) private var theme
    let event: CalendarEventInfo
    let now: Date
    let onRecord: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(eyebrow)
            Text(event.title.isEmpty ? "Untitled event" : event.title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(theme.ink)
                .lineLimit(2)
                .padding(.top, MeetingsSpace.label)
            Text(meta)
                .font(MeetingsType.secondary)
                .foregroundStyle(theme.inkSoft)
                .lineLimit(1)
                .padding(.top, 4)
                .monospacedDigit()
            MeetingsButton(title: "Record", systemImage: "mic.fill", role: .primary, action: onRecord)
                .padding(.top, 20)
                .accessibilityLabel("Record \(event.title)")
        }
        .primaryCard()
    }

    private var isNow: Bool { event.start <= now && event.end > now }

    private var eyebrow: String {
        if isNow {
            return "Happening now · until \(event.end.formatted(date: .omitted, time: .shortened))"
        }
        return "Next meeting · \(Self.countdown(to: event.start, from: now))"
    }

    private var meta: String {
        let time = "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))"
        let people = event.attendeeNames.isEmpty ? nil : event.attendeeNames.joined(separator: ", ")
        return MetaLine.join([time, people])
    }

    /// "in 25 min", "in 2 h 10 min", "in a moment".
    static func countdown(to date: Date, from now: Date) -> String {
        let minutes = Int((date.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 { return "now" }
        if minutes < 2 { return "in a moment" }
        if minutes < 60 { return "in \(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "in \(hours) h" : "in \(hours) h \(rest) min"
    }
}

/// Nothing scheduled (or nothing recorded yet): one sentence and the Record button.
struct QuietHeroCard: View {
    @Environment(\.meetingsTheme) private var theme
    let isFirstMeeting: Bool
    let onRecord: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(isFirstMeeting ? "Get started" : "Nothing scheduled")
            Text(isFirstMeeting ? "Record your first meeting" : "Record a meeting")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(theme.ink)
                .padding(.top, MeetingsSpace.label)
            Text("Notes, transcript and a summary stay on this device.")
                .font(MeetingsType.secondary)
                .lineSpacing(3)
                .foregroundStyle(theme.inkSoft)
                .padding(.top, 4)
            MeetingsButton(title: "Record", systemImage: "mic.fill", role: .primary, action: onRecord)
                .padding(.top, 20)
                .accessibilityHint("Starts recording right away")
        }
        .primaryCard()
    }
}

/// Compact accent-tinted strip: open action items across meetings.
struct OpenActionsStrip: View {
    @Environment(\.meetingsTheme) private var theme
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "checklist")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(theme.ink)
                Text(MetaLine.count(count, "open action item", "open action items"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.ink)
                    .monospacedDigit()
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.inkSoft)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: MeetingsSpace.target)
            .background(theme.accentWash, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(count) open action items")
        .accessibilityHint("Shows them all")
    }
}

// MARK: - Rows

/// One past meeting in the home list: title, meta line, chevron, bottom hairline.
struct MeetingRow: View {
    @Environment(\.meetingsTheme) private var theme
    let meeting: Meeting
    var group: MeetingDayGroup = .earlier
    var openCount: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.displayTitle)
                        .font(MeetingsType.rowTitle)
                        .foregroundStyle(theme.ink)
                        .lineLimit(1)
                    Text(meta)
                        .font(MeetingsType.meta)
                        .foregroundStyle(theme.inkSoft)
                        .lineLimit(1)
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.inkSoft.opacity(0.7))
            }
            .padding(.vertical, 14)
            Hairline()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var meta: String {
        let when: String
        switch group {
        case .today, .yesterday:
            when = meeting.startedAt.formatted(date: .omitted, time: .shortened)
        case .thisWeek:
            when = meeting.startedAt.formatted(.dateTime.weekday(.wide))
        case .earlier:
            when = meeting.startedAt.formatted(date: .abbreviated, time: .omitted)
        }
        let speakers = max(meeting.speakerLabels.count, meeting.attendeeNames.count)
        return MetaLine.join([
            when,
            MetaLine.duration(meeting.duration),
            speakers > 0 ? MetaLine.count(speakers, "speaker", "speakers") : nil,
            openCount > 0 ? "\(openCount) open" : nil
        ])
    }
}

/// Every open action item, grouped by meeting.
struct OpenActionsScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.meetingsTheme) private var theme
    @Query(filter: #Predicate<ActionItemRecord> { $0.isDone == false }, sort: \ActionItemRecord.createdAt, order: .reverse)
    private var items: [ActionItemRecord]
    @Query(sort: \Meeting.startedAt, order: .reverse) private var meetings: [Meeting]
    @State private var saveError: UserMessage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Open action items")
                    .font(MeetingsType.pageTitle)
                    .foregroundStyle(theme.ink)
                    .padding(.bottom, 20)
                if let saveError {
                    BannerView(saveError, symbol: "exclamationmark.triangle", onDismiss: { self.saveError = nil })
                        .padding(.bottom, 16)
                }
                if items.isEmpty {
                    EmptyStateView(symbol: "checkmark", title: "Nothing open",
                                   message: "Action items from your meetings show up here until you tick them off.")
                } else {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ActionItemRow(
                            text: item.text,
                            owner: item.owner,
                            due: item.due.map { DueFormatter.string(from: $0) },
                            context: meetings.first { $0.id == item.meetingID }?.displayTitle,
                            isDone: item.isDone,
                            onToggle: { toggle(item) }
                        )
                        if index < items.count - 1 { Hairline() }
                    }
                }
            }
            .padding(.horizontal, MeetingsSpace.margin)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .themedPageBackground()
        .navigationTitle("")
        .inlineTitle()
    }

    private func toggle(_ item: ActionItemRecord) {
        item.isDone.toggle()
        do {
            try context.save()
            saveError = nil
        } catch {
            saveError = UserMessage.from(error, context: "The change could not be saved.")
        }
        MeetingsSnapshotPublisher.publishStoreChanges(context: context)
    }
}

// MARK: - Previews

#Preview("Home · light") {
    MeetingsHubPreview(scheme: .light)
}

#Preview("Home · dark") {
    MeetingsHubPreview(scheme: .dark)
}

#Preview("Home · recording") {
    MeetingsHubPreview(scheme: .light, recording: true)
}

#Preview("Home · recording · dark") {
    MeetingsHubPreview(scheme: .dark, recording: true)
}

#Preview("Home · empty") {
    MeetingsHubPreview(scheme: .light, empty: true)
}

#Preview("Home · empty · dark") {
    MeetingsHubPreview(scheme: .dark, empty: true)
}

/// Home screen with the sample store and the Warm palette.
struct MeetingsHubPreview: View {
    let scheme: ColorScheme
    var recording = false
    var empty = false

    var body: some View {
        HomeScreen(
            previewEvents: empty ? [] : MeetingPreviewData.sampleEvents(),
            previewRecording: recording ? RecordingHeroState(
                elapsed: 1_262,
                title: "Roadmap sync",
                lastLine: "Then we ship the beta on Friday and the test group gets a build on Thursday.",
                levels: MeetingPreviewData.waveform(phase: 1.3)
            ) : nil
        )
        .modelContainer(MeetingPreviewData.previewContainer(empty: empty))
        .meetingsTheme(MeetingPreviewData.warmTheme(scheme))
        .preferredColorScheme(scheme)
    }
}
