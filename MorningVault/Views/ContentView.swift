import SwiftUI
import UIKit
import SwiftData
import MeetingNotesKit

struct ContentView: View {
    @AppStorage("user_name") private var userName: String = ""
    @AppStorage("local_only") private var localOnly = false
    @AppStorage("has_completed_onboarding") private var hasCompletedOnboarding = false

    @StateObject private var viewModel = BriefingViewModel()
    @ObservedObject private var meetingsRouter = MeetingsRouter.shared
    @State private var selectedTab: Tab = .brief
    @State private var tabBarIconScales: [Tab: CGFloat] = [:]
    @State private var showShareSheet = false
    @State private var isVoicePlaying = false
    /// The one meetings store, shared with the brief and Siri through `MeetingNotesStore.sharedContainer()`.
    @State private var meetingsContainer: ModelContainer?
    @State private var meetingsStoreError: String?

    init() {
        do {
            _meetingsContainer = State(initialValue: try MeetingNotesStore.sharedContainer())
        } catch {
            _meetingsStoreError = State(initialValue: error.localizedDescription)
        }
    }

    enum Tab: String, CaseIterable {
        case brief = "Brief"
        case markets = "Markets"
        case meetings = "Meetings"
        case settings = "Settings"

        var icon: String {
            switch self {
            case .brief: return "sun.max"
            case .markets: return "chart.line.uptrend.xyaxis"
            case .meetings: return "waveform"
            case .settings: return "gearshape"
            }
        }

        var filledIcon: String {
            switch self {
            case .brief: return "sun.max.fill"
            case .markets: return "chart.line.uptrend.xyaxis"
            case .meetings: return "waveform"
            case .settings: return "gearshape.fill"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // MARK: - Brief Tab
            BriefTabView(
                viewModel: viewModel,
                userName: userName,
                localOnly: localOnly,
                isVoicePlaying: $isVoicePlaying,
                showShareSheet: $showShareSheet,
                onOpenMarkets: { selectedTab = .markets }
            )
            .tabItem {
                TabIcon(
                    tab: Tab.brief,
                    isSelected: selectedTab == Tab.brief,
                    scales: $tabBarIconScales
                )
            }
            .tag(Tab.brief)

            // MARK: - Markets Tab (has its own NavigationStack)
            MarketsView()
            .tabItem {
                TabIcon(
                    tab: Tab.markets,
                    isSelected: selectedTab == Tab.markets,
                    scales: $tabBarIconScales
                )
            }
            .tag(Tab.markets)

            // MARK: - Meetings Tab (MeetingNotesKit)
            Group {
                if let meetingsContainer {
                    MeetingsHubView().modelContainer(meetingsContainer)
                } else {
                    ContentUnavailableView {
                        Label("Meetings unavailable", systemImage: "waveform.slash")
                    } description: {
                        Text("The meetings store could not be opened on this device.")
                        if let meetingsStoreError {
                            Text(meetingsStoreError)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } actions: {
                        Button("Try again") {
                            do {
                                meetingsContainer = try MeetingNotesStore.sharedContainer()
                                meetingsStoreError = nil
                            } catch {
                                meetingsStoreError = error.localizedDescription
                            }
                        }
                    }
                }
            }
            .tabItem {
                TabIcon(
                    tab: Tab.meetings,
                    isSelected: selectedTab == Tab.meetings,
                    scales: $tabBarIconScales
                )
            }
            .tag(Tab.meetings)

            // MARK: - Settings Tab (has its own NavigationStack)
            SettingsView()
            .tabItem {
                TabIcon(
                    tab: Tab.settings,
                    isSelected: selectedTab == Tab.settings,
                    scales: $tabBarIconScales
                )
            }
            .tag(Tab.settings)
        }
        .tint(Color.warmPrimaryAccent)
        .task {
            // Once per launch: drop recording folders that have no meeting row.
            if let meetingsContainer {
                MeetingNotesStore.sweepOrphanedAudioOnce(container: meetingsContainer)
            }
        }
        // Meetings reads these through the environment, so it follows Theme and Appearance
        // without carrying brand colors itself. Changing a theme updates in place.
        .meetingsTheme(MeetingsTheme(
            background: Color.warmBackground,
            surface: Color.warmSurface,
            accent: Color.warmPrimaryAccent,
            negative: Color.warmNegative,
            cardRadius: AppRadius.card
        ))
        .task {
            AIService.shared.prewarm()
            await viewModel.silentRefresh()
        }
        .fullScreenCover(isPresented: .constant(!hasCompletedOnboarding)) {
            OnboardingView()
        }
        .onReceive(meetingsRouter.$pending) { route in
            // Widget / Live Activity deep links and the Brief card's Record button all land
            // here; the Meetings home performs the route itself.
            if route != nil { selectedTab = .meetings }
        }
        .onReceive(NotificationCenter.default.publisher(for: .viewBriefingRequested)) { _ in
            selectedTab = .brief
            Task {
                await viewModel.silentRefresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appBecameActive)) { _ in
            // Foreground: refresh in place, never yank the user off their current tab.
            Task {
                await viewModel.silentRefresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .unitsChanged)) { _ in
            // Section text and the AI summary are built with the chosen units, so rebuild both.
            Task {
                await viewModel.generateBriefing()
            }
        }
    }
}

// MARK: - Tab Icon with Animation

struct TabIcon: View {
    let tab: ContentView.Tab
    let isSelected: Bool
    @Binding var scales: [ContentView.Tab: CGFloat]

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: isSelected ? tab.filledIcon : tab.icon)
                .font(.title3)
                .scaleEffect(scales[tab] ?? 1.0)
        }
        .onChange(of: isSelected) { _, newValue in
            if newValue {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    scales[tab] = 1.15
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                        scales[tab] = 1.0
                    }
                }
            }
        }
    }
}

// MARK: - Brief Tab

/// The Brief: a full-bleed sky scene with the temperature, then answer first (greeting, one
/// lede sentence, Listen), evidence second (Next, changes, Markets rows, health, headlines).
struct BriefTabView: View {
    @ObservedObject var viewModel: BriefingViewModel
    let userName: String
    let localOnly: Bool
    @Binding var isVoicePlaying: Bool
    @Binding var showShareSheet: Bool
    /// Tap on a Markets row switches to the Markets tab.
    var onOpenMarkets: (() -> Void)? = nil
    /// Previews only: pin the clock (scene hour, Next rows, "Updated") and the greeting.
    var previewNow: Date? = nil
    var previewGreeting: String? = nil

    @AppStorage("weather_enabled") private var weatherEnabled = true
    @AppStorage("voice_briefing_enabled") private var voiceBriefingEnabled = false
    @ObservedObject private var voiceService = VoiceBriefingService.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("calendar_enabled") private var calendarEnabled = true
    @AppStorage("health_enabled") private var healthEnabled = true
    @AppStorage("headlines_enabled") private var headlinesEnabled = true
    private let greeting = GreetingService.shared

    /// Scene entrance flag (see `runEntrance`); text and rows use `.entrance(delay:)`.
    @State private var sceneIn = false
    /// Bumps on every completed refresh: crossfades the content and fires the haptic.
    @State private var refreshCount = 0
    @State private var showEarlier = false
    @State private var shareItems: [Any] = []

    // MARK: Derived

    private var now: Date { previewNow ?? Date() }
    private var hour: Int { Calendar.current.component(.hour, from: now) }

    private var greetingLine: String {
        let line = previewGreeting ?? greeting.line
        return line.hasSuffix(".") ? line : line + "."
    }

    private func section(_ id: String) -> BriefingSection? {
        viewModel.briefingSections.first { $0.id == id }
    }

    private var weather: WeatherSummary? {
        guard weatherEnabled, let text = section("weather")?.content else { return nil }
        return WeatherSummary.parse(text)
    }

    private var skyStyle: SkyStyle {
        SkyStyle.resolve(hour: hour, condition: weather?.condition, colorScheme: colorScheme)
    }

    private var sceneInk: Color { skyStyle.usesLightText ? Color.white : Color.inkPrimary }
    private var sceneInkSecondary: Color { skyStyle.usesLightText ? Color.white.opacity(0.78) : Color.inkPrimary.opacity(0.68) }

    private var schedule: BriefSchedule? {
        guard let cal = section("calendar"), cal.errorMessage == nil else { return nil }
        return BriefSchedule.make(from: CalendarLine.parse(cal.content), now: now)
    }

    private var ledeParts: (lede: String, rest: String?)? {
        viewModel.aiDaySummary.map { EditorialFormat.splitLede($0) }
    }

    /// Why the Brief is empty, in the user's terms: no source on, no Calendar access, or
    /// nothing loaded yet. The alarm has nothing to do with it.
    private var emptyState: (title: String, message: String, icon: String) {
        let anySourceOn = healthEnabled || calendarEnabled || weatherEnabled || headlinesEnabled
        if !anySourceOn {
            return ("Turn on a source in Settings", "Health, Calendar, Weather and Headlines are all off. Turn one on under Settings › Data Sources.", "switch.2")
        }
        if calendarEnabled, !CalendarService.shared.isAuthorized {
            return ("Allow Calendar access", "Your day's events show here once MorningVault can read your calendar. Allow it under Settings › Permissions.", "calendar.badge.exclamationmark")
        }
        if localOnly, !healthEnabled, !calendarEnabled {
            return ("Turn on an on-device source", "Local-only mode keeps Headlines and Markets off. Turn on Health or Calendar to fill the Brief.", "lock.fill")
        }
        return ("Pull to refresh", "Nothing loaded yet. Pull down to load today's Brief.", "arrow.clockwise")
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    sceneHero(safeTop: geo.safeAreaInsets.top)

                    VStack(alignment: .leading, spacing: 30) {
                        answerBlock

                        if viewModel.isLoading && viewModel.briefingSections.isEmpty {
                            LoadingStateView()
                        } else if viewModel.briefingSections.isEmpty && viewModel.meetingPrep == nil {
                            let state = emptyState
                            EmptyStateView(title: state.title, message: state.message, systemImage: state.icon)
                        } else {
                            evidence
                        }

                        privacyFooter
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                    .id(refreshCount)
                    .transition(.opacity)
                }
            }
            .ignoresSafeArea(edges: .top)
            .background(Color.backgroundColor.ignoresSafeArea())
            .environment(\.skyTint, skyStyle.tint)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                await viewModel.generateBriefing()
                withAnimation(.easeInOut(duration: 0.32)) { refreshCount += 1 }
            }
            .sensoryFeedback(.success, trigger: refreshCount)
            .scrollDismissesKeyboard(.interactively)
            .task {
                guard !viewModel.hasLoaded else { return }
                await viewModel.loadData()
            }
            .task(id: greetingTaskKey) {
                // Once per day per name; a cached greeting returns immediately.
                await greeting.refresh(name: userName, context: greetingContext)
            }
            .onChange(of: weatherEnabled) { _, _ in
                Task { await viewModel.loadData(force: true) }
            }
            .task(id: voiceBriefingEnabled) {
                // Load Emma's voice before the first Listen tap.
                if voiceBriefingEnabled { voiceService.prewarm() }
            }
            .onChange(of: voiceService.isPlaying) { _, playing in
                // The synthesizer finishing (or being cut off) is what ends "playing".
                isVoicePlaying = playing
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: shareItems.isEmpty ? [briefingShareText()] : shareItems)
                    .presentationDetents([.medium, .large])
            }
            .onAppear(perform: runEntrance)
            }
        }
    }

    /// Re-runs the greeting task when the name or the day changes, or when the first
    /// event/weather first arrive (the opener mentions one of them).
    private var greetingTaskKey: String {
        let b = SharedBriefingStore.loadToday()
        return "\(SharedBriefing.today())|\(userName)|\(b?.firstEventTitle ?? "")|\(b?.weatherLine ?? "")"
    }

    private var greetingContext: GreetingService.Context {
        let b = SharedBriefingStore.loadToday()
        return .init(firstEventTitle: b?.firstEventTitle, firstEventStart: b?.firstEventStart, weatherLine: b?.weatherLine)
    }

    // MARK: Motion

    /// First appear: scene 1.02 → 1.0 over 450 ms; temperature rises 8 pt over 350 ms;
    /// greeting + lede 120 ms later; Next rows 80 ms after that (40 ms stagger in the rows).
    /// Reduce Motion: plain fades ≤ 200 ms, no drift.
    private func runEntrance() {
        guard !sceneIn else { return }
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.2)) { sceneIn = true }
            return
        }
        withAnimation(.smooth(duration: 0.45)) { sceneIn = true }
    }

    // MARK: Share

    private func share() {
        let card = ShareCardView(
            hour: hour,
            weather: weather,
            greeting: greetingLine,
            lede: ledeParts?.lede,
            nextEvent: schedule?.upcoming.first,
            quotes: marketQuotesForShare,
            dateText: EditorialFormat.dateEyebrow(now),
            colorScheme: colorScheme
        )
        var items: [Any] = []
        if let image = card.render() { items.append(image) }
        items.append(briefingShareText())
        shareItems = items
        showShareSheet = true
    }

    private var marketQuotesForShare: [MorningSnapshotQuote] {
        marketRows.prefix(2).map { line in
            let s = viewModel.marketSeries[line.symbol]
            return MorningSnapshotQuote(symbol: line.symbol, priceText: line.price, change24h: line.change,
                                        prevClose: s?.prevClose, series: s?.points ?? [])
        }
    }

    private func briefingShareText() -> String {
        let dateString = now.formatted(date: .complete, time: .omitted)
        var lines: [String] = ["MorningVault — \(dateString)"]
        for section in viewModel.briefingSections.prefix(5) {
            lines.append("• \(section.title): \(section.content)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Scene hero

    /// The scene runs under the status bar; `safeTop` keeps the top row below it.
    private func sceneHero(safeTop: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sceneTopRow
            Spacer(minLength: 24)
            if let weather {
                weatherBlock(weather)
            } else {
                greetingInScene
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, safeTop + 6)
        .padding(.bottom, 30)
        .containerRelativeFrame(.vertical, alignment: .bottom) { length, _ in max(320, length * 0.38) + safeTop }
        .background {
            ZStack(alignment: .bottom) {
                SkyScene(hour: hour, condition: weather?.condition)
                // Fade into the canvas over 80 pt: no card seam.
                LinearGradient(colors: [Color.backgroundColor.opacity(0), Color.backgroundColor], startPoint: .top, endPoint: .bottom)
                    .frame(height: 80)
            }
        }
        .opacity(sceneIn ? 1 : 0)
        .scaleEffect(sceneIn || reduceMotion ? 1 : 1.02)
    }

    private var sceneTopRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Eyebrow(text: EditorialFormat.dateEyebrow(now), color: sceneInkSecondary)
            Spacer(minLength: 8)
            updatedStatus
            IconButton(systemImage: "square.and.arrow.up", label: "Share briefing", tint: sceneInk, action: share)
                .padding(.trailing, -10)
        }
    }

    @ViewBuilder
    private var updatedStatus: some View {
        if let updated = viewModel.morningSnapshot.updatedAt {
            HStack(spacing: 6) {
                BreathingDot(color: sceneInk)
                Text("Updated \(EditorialFormat.time(updated))")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
            }
            .foregroundStyle(sceneInkSecondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Updated \(EditorialFormat.time(updated)). \(viewModel.networkBadge == .local ? "Local only" : "Live data")")
        } else if viewModel.isLoading {
            Text("Updating…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(sceneInkSecondary)
        }
    }

    private func weatherBlock(_ w: WeatherSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(w.temperature)
                .font(.display(92, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(sceneInk)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityLabel("\(w.temperature) \(w.unit)")
                .padding(.bottom, -10)
                .entrance(delay: 0, rise: 8)
            Text("\(w.condition) · \(w.location)")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(sceneInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Hairline(color: sceneInk.opacity(0.22))
                .padding(.top, 4)
            HStack(alignment: .top, spacing: 0) {
                sceneStat("Feels like", w.feelsLike)
                sceneStat("Humidity", w.humidity)
                sceneStat("Wind", w.wind)
            }
            if let note = w.note, !note.isEmpty {
                Text(note)
                    .font(.system(size: 13))
                    .foregroundStyle(sceneInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sceneStat(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Eyebrow(text: label, color: sceneInkSecondary)
            Text(value ?? "—")
                .font(.system(size: 15, weight: .medium).monospacedDigit())
                .foregroundStyle(sceneInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Weather unavailable: the time-of-day sky alone, with the greeting in that slot.
    private var greetingInScene: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(greetingLine)
                .font(.display(40, weight: .medium))
                .foregroundStyle(sceneInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .entrance(delay: 0, rise: 8)
            if let notice = weatherNotice {
                Text(notice)
                    .font(.system(size: 13))
                    .foregroundStyle(sceneInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 300, alignment: .leading)
    }

    private var weatherNotice: String? {
        let s = viewModel.morningSnapshot
        if !weatherEnabled || !s.weatherEnabled { return nil }
        if s.weatherNeedsLocation { return "Allow Location for MorningVault to see the weather here, then pull to refresh." }
        if let detail = s.weatherErrorDetail, !detail.isEmpty {
            if detail.localizedCaseInsensitiveContains("Location") {
                return "Weather needs your location. Allow it in Settings, then pull to refresh."
            }
            return "Weather is unavailable right now. Pull to refresh to try again."
        }
        if viewModel.hasLoaded, !viewModel.isLoading, section("weather") != nil { return "Weather is unavailable right now." }
        return nil
    }

    // MARK: Answer first

    @ViewBuilder
    private var answerBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            if weather != nil {
                Text(greetingLine)
                    .font(.display(40, weight: .medium))
                    .lineSpacing(2)
                    .foregroundStyle(Color.inkPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.88)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }

            lede

            if voiceBriefingEnabled {
                PillButton(
                    title: isVoicePlaying ? "Stop" : "Listen",
                    systemImage: isVoicePlaying ? "stop.fill" : "waveform",
                    prominent: true,
                    isActive: isVoicePlaying
                ) {
                    if isVoicePlaying {
                        viewModel.stopVoiceBriefing()
                        isVoicePlaying = false
                    } else {
                        viewModel.speakBriefingAloud()
                        isVoicePlaying = true
                    }
                }
                .accessibilityLabel(isVoicePlaying ? "Stop voice briefing" : "Listen to briefing")
                .padding(.top, 4)
            }
        }
        .entrance(delay: 0.12)
    }

    @ViewBuilder
    private var lede: some View {
        if let parts = ledeParts {
            VStack(alignment: .leading, spacing: 10) {
                Text(parts.lede)
                    .font(.lede)
                    .lineSpacing(6)
                    .foregroundStyle(Color.inkPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
                if let rest = parts.rest {
                    Text(rest)
                        .font(.secondaryText)
                        .lineSpacing(5)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if viewModel.isGeneratingAI {
            VStack(alignment: .leading, spacing: 8) {
                SkeletonLine(height: 16)
                SkeletonLine(width: 220, height: 16)
            }
            .accessibilityLabel("Writing your day summary")
        } else if let opener = greeting.opener {
            Text(opener)
                .font(.lede)
                .lineSpacing(6)
                .foregroundStyle(Color.inkPrimary)
                .fixedSize(horizontal: false, vertical: true)
        } else if let reason = viewModel.aiUnavailableReason {
            Text(reason)
                .font(.secondaryText)
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Evidence

    @ViewBuilder
    private var evidence: some View {
        if let schedule {
            nextBlock(schedule)
        } else if let cal = section("calendar"), cal.errorMessage != nil {
            BriefingSectionCard(section: cal)
        }

        if !viewModel.sinceYesterday.isEmpty {
            changesBlock
        }

        if section("markets") != nil || !viewModel.morningSnapshot.marketQuotes.isEmpty {
            marketsBlock
        }

        ForEach(viewModel.briefingSections.filter { !["weather", "calendar", "markets"].contains($0.id) }) { section in
            BriefingSectionCard(section: section)
        }

        if let prep = viewModel.meetingPrep {
            MeetingPrepCard(prep: Binding(
                get: { prep },
                set: { viewModel.meetingPrep = $0 }
            ))
        }
    }

    // MARK: Next

    private func nextBlock(_ schedule: BriefSchedule) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Next")
            if schedule.upcoming.isEmpty {
                Text("Nothing else today.")
                    .font(.bodyText)
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(schedule.upcoming.prefix(3).enumerated()), id: \.element.id) { index, event in
                        eventRow(event, emphasis: true, index: index)
                        if index < min(schedule.upcoming.count, 3) - 1 { Hairline() }
                    }
                }
            }
            if !schedule.earlier.isEmpty {
                earlierDisclosure(schedule.earlier)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func eventRow(_ event: CalendarLine, emphasis: Bool, index: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(BriefSchedule.shortTime(event.time))
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.inkSecondary)
                .frame(width: 56, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(event.title)
                .font(.system(size: 17, weight: emphasis ? .semibold : .regular))
                .foregroundStyle(emphasis ? Color.inkPrimary : Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
        .entrance(delay: 0.20 + Double(index) * 0.04)
        .accessibilityElement(children: .combine)
    }

    private func earlierDisclosure(_ earlier: [CalendarLine]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.25)) { showEarlier.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("Earlier today (\(earlier.count))")
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .rotationEffect(.degrees(showEarlier ? 180 : 0))
                }
                .foregroundStyle(Color.inkSecondary)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(showEarlier ? "Hide earlier events" : "Show \(earlier.count) earlier events")
            if showEarlier {
                ForEach(Array(earlier.enumerated()), id: \.element.id) { index, event in
                    eventRow(event, emphasis: false, index: 0)
                    if index < earlier.count - 1 { Hairline() }
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: Changes

    private var changesBlock: some View {
        let lines = viewModel.sinceYesterday
        return VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: lines.count == 1 ? "1 change since yesterday" : "\(lines.count) changes since yesterday")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(lines, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: changeGlyph(line).name)
                            .font(.system(size: 13, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(changeGlyph(line).color)
                            .frame(width: 16)
                        Text(line)
                            .font(.secondaryText)
                            .foregroundStyle(Color.inkPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func changeGlyph(_ line: String) -> (name: String, color: Color) {
        let l = line.lowercased()
        if l.contains("%") || l.contains("market") {
            if l.contains("down") || l.contains("fell") || l.contains("lower") || l.contains("−") || l.contains("-") {
                return ("arrow.down.right", Color.negativeColor)
            }
            return ("arrow.up.right", Color.positiveColor)
        }
        if l.contains("removed") || l.contains("cancel") { return ("minus.circle", Color.inkSecondary) }
        return ("plus.circle", Color.inkSecondary)
    }

    // MARK: Markets

    private var marketRows: [MarketLine] {
        if let content = section("markets")?.content {
            let parsed = MarketLine.parse(content)
            if !parsed.isEmpty { return parsed }
        }
        return viewModel.morningSnapshot.marketQuotes.map {
            MarketLine(symbol: $0.symbol, price: $0.priceText, change: $0.change24h)
        }
    }

    private var marketsStatusText: String? {
        switch viewModel.morningSnapshot.marketsStatus {
        case .cached: return "Cached"
        case .live: return "Delayed up to 5 min"
        default: return nil
        }
    }

    private var marketsBlock: some View {
        let rows = marketRows
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: "Markets")
                Spacer()
                if let marketsStatusText {
                    Text(marketsStatusText)
                        .font(.metaText)
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            if rows.isEmpty {
                Text(viewModel.morningSnapshot.marketsStatus == .loading ? "Loading prices…" : "Market prices are unavailable right now.")
                    .font(.secondaryText)
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, line in
                        let series = viewModel.marketSeries[line.symbol]
                            ?? viewModel.morningSnapshot.marketQuotes.first { $0.symbol == line.symbol }.map { MarketSeries(prevClose: $0.prevClose, points: $0.series) }
                        Button {
                            onOpenMarkets?()
                        } label: {
                            MarketRow(symbol: line.symbol, priceText: line.price, change: line.change,
                                      series: series?.points ?? [], prevClose: series?.prevClose, compact: true)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressable)
                        .accessibilityHint(onOpenMarkets == nil ? "" : "Opens the Markets tab")
                        if index < rows.count - 1 { Hairline() }
                    }
                }
            }
        }
    }

    // MARK: Footer

    private var privacyFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .medium))
                .symbolRenderingMode(.hierarchical)
            Text(viewModel.aiDaySummary == nil ? "All data stays on your device" : "Written on this iPhone · All data stays on your device")
                .font(.system(size: 12))
        }
        .foregroundStyle(Color.inkSecondary)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var excludedActivityTypes: [UIActivity.ActivityType]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.excludedActivityTypes = excludedActivityTypes
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Previews

extension BriefingViewModel {
    /// Preview clock: Saturday 8 Nov 2025, 7:40 AM local.
    static var previewNow: Date {
        Calendar.current.date(from: DateComponents(year: 2025, month: 11, day: 8, hour: 7, minute: 40)) ?? Date()
    }

    /// Preview clock in the evening (partly cloudy dusk; two events already past).
    static var previewEvening: Date {
        Calendar.current.date(from: DateComponents(year: 2025, month: 11, day: 8, hour: 18, minute: 21)) ?? Date()
    }

    /// A filled-in model for previews: every section, a two-sentence summary, no loading.
    /// The market series are preview data (see `MarketPreviewData`), not quotes.
    @MainActor static func previewSample(
        now: Date = BriefingViewModel.previewNow,
        weather: String = "64°F (Partly Cloudy) in Murrieta. Feels like 62°F. Humidity 40%. Wind 8 mph W.",
        summary: String = "A mild morning with three meetings, the first at nine. Markets opened lower, so the standup is the only thing that needs your attention early."
    ) -> BriefingViewModel {
        let vm = BriefingViewModel()
        vm.hasLoaded = true
        vm.isLoading = false
        vm.networkBadge = .online
        vm.aiDaySummary = summary
        vm.sinceYesterday = ["SPY is down 2.7% since yesterday's brief", "One new meeting: Dentist at 3:00 PM"]
        vm.briefingSections = [
            BriefingSection(id: "weather", title: "Weather", icon: "🌤️",
                            content: weather,
                            sentiment: "positive"),
            BriefingSection(id: "calendar", title: "Calendar", icon: "📅",
                            content: "9:00 AM — Standup\n11:30 AM — Design review with Priya\n3:00 PM — Dentist",
                            sentiment: nil),
            BriefingSection(id: "markets", title: "Markets", icon: "📈",
                            content: "SPY: $735.29 ↓2.70%\nBTC: $75,699 ↑1.12%",
                            sentiment: "bearish"),
            BriefingSection(id: "health", title: "Health", icon: "❤️‍🔥",
                            content: "Last night: 7h 12m asleep (of 7h 50m in bed). Today: 8432 steps. HRV: 45ms. Resting HR: 58 bpm. ",
                            sentiment: nil),
            BriefingSection(id: "headlines", title: "Headlines", icon: "📰",
                            content: "• Fed holds rates steady as inflation cools\n• Apple previews on-device models for iOS 27\n• Storm system to bring rain to Southern California",
                            sentiment: nil)
        ]
        vm.marketSeries = [
            "SPY": MarketSeries(prevClose: 755.0, points: MarketPreviewData.spy),
            "BTC": MarketSeries(prevClose: 74_860, points: MarketPreviewData.btc)
        ]
        vm.morningSnapshot = MorningSnapshot(
            weatherIcon: "🌤️", weatherLine: "64°F, Partly Cloudy", location: "Murrieta",
            calendarLine: "3 events, first at 9:00 AM",
            marketQuotes: [
                MorningSnapshotQuote(symbol: "SPY", priceText: "$735.29", change24h: -2.70, prevClose: 755.0, series: MarketPreviewData.spy),
                MorningSnapshotQuote(symbol: "BTC", priceText: "$75,699", change24h: 1.12, prevClose: 74_860, series: MarketPreviewData.btc)
            ],
            marketsStatus: .live, weatherEnabled: true, weatherNeedsLocation: false,
            weatherErrorDetail: nil, updatedAt: now.addingTimeInterval(-19 * 60))
        return vm
    }
}

#Preview("Brief · light") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    return BriefTabView(
        viewModel: BriefingViewModel.previewSample(weather: "64°F (Clear) in Murrieta. Feels like 62°F. Humidity 40%. Wind 8 mph W."),
        userName: "Yezid",
        localOnly: false,
        isVoicePlaying: .constant(false),
        showShareSheet: .constant(false),
        previewNow: BriefingViewModel.previewNow,
        previewGreeting: "Good morning, Yezid"
    )
    .preferredColorScheme(.light)
}

#Preview("Brief · dark") {
    ThemeStore.shared.themeRaw = AppTheme.dark.rawValue
    return BriefTabView(
        viewModel: BriefingViewModel.previewSample(
            now: BriefingViewModel.previewEvening,
            summary: "Three meetings done and the dentist behind you; nothing else on the calendar tonight. SPY closed lower while BTC held its gain."),
        userName: "Yezid",
        localOnly: false,
        isVoicePlaying: .constant(false),
        showShareSheet: .constant(false),
        previewNow: BriefingViewModel.previewEvening,
        previewGreeting: "Good evening, Yezid"
    )
    .preferredColorScheme(.dark)
}

#Preview("Brief · rain") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    return BriefTabView(
        viewModel: BriefingViewModel.previewSample(weather: "52°F (Rain) in Murrieta. Feels like 48°F. Humidity 91%. Wind 14 mph S."),
        userName: "Yezid",
        localOnly: false,
        isVoicePlaying: .constant(true),
        showShareSheet: .constant(false),
        previewNow: BriefingViewModel.previewNow,
        previewGreeting: "Good morning, Yezid"
    )
    .preferredColorScheme(.light)
}

#Preview("App") {
    ContentView()
}
