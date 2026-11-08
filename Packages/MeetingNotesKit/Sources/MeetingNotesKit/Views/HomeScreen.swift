import Combine
import SwiftData
import SwiftUI

/// The controls a recording can zoom out of (and back into).
enum HomeZoomSource {
    static let newMeeting = "new-meeting"
    static let live = "live-recording"
    static func event(_ id: String) -> String { "event-\(id)" }
}

/// What a new meeting is started for: a calendar event, nothing, or the recording that is
/// already running (reopening its page).
struct NewMeetingRequest: Identifiable, Hashable {
    let id = UUID()
    var calendarEventID: String?
    var title: String = ""
    var attendees: [String] = []
    /// Reopen the page of the recording in progress instead of starting a new one.
    var resumesLive = false
    /// The control the page zooms out of.
    var sourceID: String = HomeZoomSource.newMeeting

    init() {}

    init(event: CalendarEventInfo) {
        calendarEventID = event.id
        title = event.title
        attendees = event.attendeeNames
        sourceID = HomeZoomSource.event(event.id)
    }

    static var live: NewMeetingRequest {
        var request = NewMeetingRequest()
        request.resumesLive = true
        request.sourceID = HomeZoomSource.live
        return request
    }
}

/// Where the home screen can go.
enum HomeDestination: Hashable {
    case meeting(UUID)
    case openActions
    case record(NewMeetingRequest)

    var isRecording: Bool {
        if case .record = self { return true }
        return false
    }
}

/// The first screen, one flow top to bottom: the title, the recording in progress (if
/// any), what is next on the calendar, open action items, then past meetings by day.
/// The one call to action is the New meeting pill at the bottom; it is replaced by the
/// inline recording controls while a meeting records.
struct HomeScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.meetingsTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Meeting.startedAt, order: .reverse) private var meetings: [Meeting]
    @Query(filter: #Predicate<ActionItemRecord> { $0.isDone == false }, sort: \ActionItemRecord.createdAt)
    private var openActions: [ActionItemRecord]
    @StateObject private var calendar = CalendarService()
    /// The one recording session of the tab. Owned here so the recorder's page can be
    /// left and reopened while the meeting keeps recording.
    @StateObject private var liveSession = RecordingSession()
    @ObservedObject private var router = MeetingsRouter.shared
    @AppStorage(MarkdownCopiesSetting.key) private var saveMarkdownCopies = false
    @Namespace private var zoom
    @State private var searchText = ""
    @State private var showVoiceEnrollment = false
    @State private var now = Date()
    @State private var path: [HomeDestination] = []
    /// A delete that the store refused, shown until dismissed.
    @State private var saveError: UserMessage?

    /// Previews only: events shown instead of the calendar's.
    var previewEvents: [CalendarEventInfo]?
    /// Previews only: a recording shown inline instead of the live session's.
    var previewRecording: LiveRecordingState?

    private let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                header
                    .homeRow(top: 8, bottom: meetings.isEmpty ? 8 : 16)

                if meetings.isEmpty, !isSearching {
                    Text(upcomingEvents.isEmpty
                         ? "Nothing recorded yet. Notes, transcript and a summary stay on this device."
                         : "Nothing recorded yet. Record the next meeting, or start one now.")
                        .font(MeetingsType.secondary)
                        .lineSpacing(3)
                        .foregroundStyle(theme.inkSoft)
                        .homeRow(top: 0, bottom: 16)
                        .accessibilityHint("Use New meeting to start recording")
                } else {
                    searchField
                        .homeRow(top: 0, bottom: 20)
                }

                if let saveError {
                    BannerView(saveError, symbol: "exclamationmark.triangle", onDismiss: { self.saveError = nil })
                        .homeRow(top: 0, bottom: 16)
                }

                if !isSearching {
                    liveBlock
                        .homeRow(top: 0, bottom: 0)

                    if let event = upcomingEvents.first {
                        Eyebrow(isHappening(event) ? "Now" : "Next")
                            .homeRow(top: isLive ? MeetingsSpace.sectionGap : 4, bottom: 4)
                        NextEventRow(event: event, now: now, onRecord: { start(NewMeetingRequest(event: event)) })
                            .zoomSource(id: HomeZoomSource.event(event.id), in: zoom)
                            .homeRow(top: 0, bottom: 0)
                    }

                    if !openActions.isEmpty {
                        OpenActionsRow(count: openActions.count, hasRowAbove: upcomingEvents.first != nil) {
                            path.append(.openActions)
                        }
                        .homeRow(top: upcomingEvents.isEmpty ? (isLive ? MeetingsSpace.sectionGap : 4) : 0, bottom: 0)
                    }
                }

                if meetings.isEmpty {
                    if isSearching {
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
            .safeAreaInset(edge: .bottom) { newMeetingPill }
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
                case .record(let request):
                    recordingPage(for: request)
                }
            }
            .refreshable { await refresh() }
            .sheet(isPresented: $showVoiceEnrollment) {
                VoiceEnrollmentScreen()
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
            .onChange(of: path) { old, new in
                // Back from the recorder page: the widget snapshot picks up what was saved.
                if old.contains(where: \.isRecording), !new.contains(where: \.isRecording) {
                    MeetingsSnapshotPublisher.publishStoreChanges(context: context)
                }
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
        .background(theme.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Live recording

    /// The recording in progress, inline between hairlines. Appears and leaves with a fade
    /// and a slide from the top (a plain fade under Reduce Motion).
    private var liveBlock: some View {
        VStack(spacing: 0) {
            if let state = recordingState {
                LiveRecordingBlock(
                    state: state,
                    onPause: {
                        if liveSession.phase == .paused { liveSession.resume() } else { liveSession.pause() }
                    },
                    onStop: {
                        Task { await liveSession.stop(context: context) }
                    },
                    onOpen: { start(.live) }
                )
                .zoomSource(id: HomeZoomSource.live, in: zoom)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.smooth(duration: 0.35), value: isLive)
    }

    private var recordingState: LiveRecordingState? {
        if let previewRecording { return previewRecording }
        guard liveSession.isRecording else { return nil }
        return LiveRecordingState(session: liveSession)
    }

    private var isLive: Bool { recordingState != nil }

    // MARK: - New meeting

    /// The persistent call to action: a 52 pt accent pill. While a recording runs the
    /// inline Pause and Stop take its place.
    private var newMeetingPill: some View {
        ZStack {
            if !isLive {
                Button {
                    start(NewMeetingRequest())
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "mic.fill")
                            .font(MeetingsType.symbol)
                        Text("New meeting")
                            .font(MeetingsType.button)
                    }
                    .foregroundStyle(theme.onAccentColor)
                    .padding(.horizontal, 24)
                    .frame(height: MeetingsSpace.control)
                    .background(theme.accentColor, in: Capsule())
                    .shadow(color: theme.accentColor.opacity(0.28), radius: 14, y: 6)
                    .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .zoomSource(id: HomeZoomSource.newMeeting, in: zoom)
                .accessibilityLabel("New meeting")
                .accessibilityHint("Starts recording right away")
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .animation(.smooth(duration: 0.35), value: isLive)
    }

    /// Pushes the recorder page. A tap while a meeting records reopens that recording
    /// instead of starting another.
    private func start(_ request: NewMeetingRequest) {
        if path.contains(where: \.isRecording) { return }
        let target: NewMeetingRequest = liveSession.isRecording && !request.resumesLive ? .live : request
        path.append(.record(target))
    }

    /// The recorder page, zooming out of the control that started it. Once the meeting
    /// records, the way back zooms into the inline recording block instead, because the
    /// New meeting pill has left the screen by then.
    @ViewBuilder
    private func recordingPage(for request: NewMeetingRequest) -> some View {
        let page = MeetingScreen(
            session: liveSession,
            initialTitle: request.title,
            initialAttendees: request.attendees,
            calendarEventID: request.calendarEventID,
            autoStart: !request.resumesLive,
            isModal: false
        )
        page.recordingZoom(sourceID: isLive ? HomeZoomSource.live : request.sourceID, in: zoom, reduceMotion: reduceMotion)
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
            // One recording at a time: a Record tap while one runs opens its page.
            if path.contains(where: \.isRecording) { return }
            if ActiveRecordingRegistry.shared.isRecording {
                path = [.record(.live)]
                return
            }
            path.removeAll()
            if let eventID, calendar.event(with: eventID) == nil {
                await calendar.loadToday()
            }
            guard !path.contains(where: \.isRecording), !ActiveRecordingRegistry.shared.isRecording else { return }
            var request = NewMeetingRequest()
            if let eventID, let event = calendar.event(with: eventID) {
                request = NewMeetingRequest(event: event)
            } else {
                request.calendarEventID = eventID
                request.title = title
                request.attendees = attendees
            }
            path = [.record(request)]
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

    private func isHappening(_ event: CalendarEventInfo) -> Bool {
        event.start <= now && event.end > now
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

// MARK: - Live recording

/// What the inline recording block shows, taken from the live session (or a preview).
struct LiveRecordingState: Equatable {
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

/// The recording in progress on the home: breathing dot, the timer, the last line heard,
/// and Pause / Stop as 44 pt icon buttons on the right. Hairlines above and below, no box.
/// Tapping the text opens the recorder page.
struct LiveRecordingBlock: View {
    @Environment(\.meetingsTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: LiveRecordingState
    let onPause: () -> Void
    let onStop: () -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(alignment: .top, spacing: 12) {
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            BreathingDot(color: state.isPaused ? theme.inkSoft : theme.negativeColor, isActive: !state.isPaused)
                            Eyebrow(state.isPaused ? "Paused" : "Recording", color: state.isPaused ? nil : theme.negativeColor)
                                .contentTransition(.numericText())
                        }
                        ElapsedTimeLabel(elapsed: state.elapsed)
                            .padding(.top, 8)
                        if !state.title.isEmpty {
                            Text(state.title)
                                .font(MeetingsType.rowTitle)
                                .foregroundStyle(theme.ink)
                                .lineLimit(1)
                                .padding(.top, 8)
                        }
                        Text(state.lastLine.isEmpty ? "Listening…" : state.lastLine)
                            .font(MeetingsType.secondary)
                            .lineSpacing(3)
                            .foregroundStyle(theme.inkSoft)
                            .lineLimit(2)
                            .padding(.top, state.title.isEmpty ? 8 : 4)
                            .contentTransition(.opacity)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(state.isPaused ? "Paused recording" : "Recording in progress")
                .accessibilityHint("Opens the recording")

                HStack(spacing: 0) {
                    ControlIconButton(
                        systemImage: state.isPaused ? "play.fill" : "pause.fill",
                        label: state.isPaused ? "Resume" : "Pause",
                        action: onPause
                    )
                    ControlIconButton(systemImage: "stop.fill", label: "Stop", tint: theme.negativeColor, action: onStop)
                }
                .padding(.top, 4)
            }
            .padding(.vertical, 16)
            .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: state.isPaused)
            Hairline()
        }
        .accessibilityElement(children: .contain)
    }
}

/// 44 pt round icon control: a tinted symbol on a 6 % wash. Used for inline Pause and Stop.
struct ControlIconButton: View {
    @Environment(\.meetingsTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let systemImage: String
    let label: String
    var tint: Color?
    let action: () -> Void

    var body: some View {
        let color = tint ?? theme.ink
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                .frame(width: 36, height: 36)
                .background(color.opacity(0.08), in: Circle())
                .frame(width: MeetingsSpace.target, height: MeetingsSpace.target)
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
    }
}

/// The small accent record control at the end of the next-event row.
struct RecordIconButton: View {
    @Environment(\.meetingsTheme) private var theme
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "mic.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.onAccentColor)
                .frame(width: 36, height: 36)
                .background(theme.accentColor, in: Circle())
                .frame(width: MeetingsSpace.target, height: MeetingsSpace.target)
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
        .accessibilityHint("Starts recording right away")
    }
}

// MARK: - Rows

/// The next calendar event as a plain row: time column, title and people, record control.
struct NextEventRow: View {
    @Environment(\.meetingsTheme) private var theme
    let event: CalendarEventInfo
    let now: Date
    let onRecord: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.start.formatted(date: .omitted, time: .shortened))
                        .font(MeetingsType.metaMedium)
                        .foregroundStyle(theme.ink)
                    Text(countdown)
                        .font(MeetingsType.meta)
                        .foregroundStyle(isNow ? theme.accentColor : theme.inkSoft)
                }
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 72, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title.isEmpty ? "Untitled event" : event.title)
                        .font(MeetingsType.rowTitle)
                        .foregroundStyle(theme.ink)
                        .lineLimit(1)
                    Text(meta)
                        .font(MeetingsType.meta)
                        .foregroundStyle(theme.inkSoft)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                RecordIconButton(label: "Record \(event.title.isEmpty ? "event" : event.title)", action: onRecord)
            }
            .padding(.vertical, 12)
            Hairline()
        }
    }

    private var isNow: Bool { event.start <= now && event.end > now }

    private var countdown: String {
        isNow ? "until \(event.end.formatted(date: .omitted, time: .shortened))" : Self.countdown(to: event.start, from: now)
    }

    private var meta: String {
        let people = event.attendeeNames.isEmpty ? nil : event.attendeeNames.joined(separator: ", ")
        return MetaLine.join([people, event.location]).isEmpty
            ? "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))"
            : MetaLine.join([people, event.location])
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

/// Open action items across meetings: a plain row with the count and a chevron.
struct OpenActionsRow: View {
    @Environment(\.meetingsTheme) private var theme
    let count: Int
    /// False when this is the first row of its run, so it draws its own top hairline.
    var hasRowAbove = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                if !hasRowAbove { Hairline() }
                HStack(spacing: 12) {
                    Text("Open action items")
                        .font(MeetingsType.rowTitle)
                        .foregroundStyle(theme.ink)
                    Spacer(minLength: 8)
                    Text("\(count)")
                        .font(MeetingsType.metaMedium)
                        .foregroundStyle(theme.inkSoft)
                        .monospacedDigit()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.inkSoft)
                }
                .padding(.vertical, 14)
                Hairline()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(count) open action items")
        .accessibilityHint("Shows them all")
    }
}

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
                    .foregroundStyle(theme.inkSoft)
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

#Preview("Home · next event · light") {
    MeetingsHubPreview(scheme: .light)
}

#Preview("Home · next event · dark") {
    MeetingsHubPreview(scheme: .dark)
}

#Preview("Home · recording · light") {
    MeetingsHubPreview(scheme: .light, recording: true)
}

#Preview("Home · recording · dark") {
    MeetingsHubPreview(scheme: .dark, recording: true)
}

#Preview("Home · empty · light") {
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
            previewRecording: recording ? MeetingPreviewData.liveRecording : nil
        )
        .modelContainer(MeetingPreviewData.previewContainer(empty: empty))
        .meetingsTheme(MeetingPreviewData.warmTheme(scheme))
        .preferredColorScheme(scheme)
    }
}

extension View {
    /// The zoom source for the recorder page. `matchedTransitionSource` ships on macOS too,
    /// so the package's macOS build keeps it.
    @ViewBuilder
    func zoomSource(id: String, in namespace: Namespace.ID) -> some View {
        matchedTransitionSource(id: id, in: namespace)
    }

    /// The zoom the recorder page pushes with. The zoom transition is iOS only, so the
    /// package's macOS build falls back to the platform's default push.
    @ViewBuilder
    func recordingZoom(sourceID: String, in namespace: Namespace.ID, reduceMotion: Bool) -> some View {
        #if os(iOS)
        if reduceMotion {
            self
        } else {
            navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        }
        #else
        self
        #endif
    }
}
