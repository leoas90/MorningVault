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

    /// Previews only: pinned clock / greeting for the Brief and injected Markets rows.
    private var previewNow: Date? = nil
    private var previewGreeting: String? = nil
    private var previewMarkets: MarketsPreviewRows? = nil

    init() {
        do {
            _meetingsContainer = State(initialValue: try MeetingNotesStore.sharedContainer())
        } catch {
            _meetingsStoreError = State(initialValue: error.localizedDescription)
        }
    }

    /// Preview hook: the real tab bar + navigation bars around an injected view model.
    init(previewViewModel: BriefingViewModel, previewNow: Date, previewGreeting: String,
         initialTab: Tab = .brief, previewMarkets: MarketsPreviewRows? = nil) {
        self.init()
        _viewModel = StateObject(wrappedValue: previewViewModel)
        _selectedTab = State(initialValue: initialTab)
        self.previewNow = previewNow
        self.previewGreeting = previewGreeting
        self.previewMarkets = previewMarkets
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
            case .settings: return "gearshape"
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
                onOpenMarkets: { selectedTab = .markets },
                previewNow: previewNow,
                previewGreeting: previewGreeting
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
            Group {
                if let previewMarkets {
                    MarketsView(previewSymbols: previewMarkets.symbols, quotes: previewMarkets.quotes, updatedAt: previewMarkets.updatedAt)
                } else {
                    MarketsView()
                }
            }
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

/// Rows and quotes for the Markets tab inside an app-level preview.
struct MarketsPreviewRows {
    var symbols: [TrackedSymbol]
    var quotes: [String: MarketQuote]
    var updatedAt: Date?
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
            Text(tab.rawValue)
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

/// The Brief, one continuous flow with no cards: the full-bleed weather hero (L1), then
/// answer first (greeting, one lede sentence), evidence second (the Next rows, the changes
/// rows, the Markets hairline list, health, headlines), all separated by hairlines on the
/// 20 pt margin grid. Share and Listen float in the navigation bar over the sky.
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
    @State private var showLater = false
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
                    VStack(alignment: .leading, spacing: Grid4.section) {
                        // Full bleed: the hero carries its own horizontal padding and its sky
                        // hangs up through the top safe area (status bar + navigation bar);
                        // everything below sits on the 20 pt margin grid.
                        hero(topInset: geo.safeAreaInsets.top)

                        VStack(alignment: .leading, spacing: Grid4.section) {
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
                        .padding(.horizontal, Grid4.margin)
                    }
                    .padding(.bottom, 24)
                    .id(refreshCount)
                    .transition(.opacity)
                }
                .background(Color.backgroundColor.ignoresSafeArea())
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbarColorScheme(heroStyle.usesLightText ? .dark : .light, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: share) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share briefing")
                    }
                    if voiceBriefingEnabled {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(action: toggleListen) {
                                Label(isVoicePlaying ? "Stop" : "Listen", systemImage: isVoicePlaying ? "stop.fill" : "waveform")
                                    .labelStyle(.titleAndIcon)
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .tint(Color.appAccentColor)
                            .accessibilityLabel(isVoicePlaying ? "Stop voice briefing" : "Listen to briefing")
                        }
                    }
                }
                .contentMargins(.bottom, 24, for: .scrollContent)
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

    private func toggleListen() {
        if isVoicePlaying {
            viewModel.stopVoiceBriefing()
            isVoicePlaying = false
        } else {
            viewModel.speakBriefingAloud()
            isVoicePlaying = true
        }
    }

    // MARK: Motion

    /// First appear: hero 1.02 → 1.0 over 450 ms; greeting + lede 120 ms later; Next rows
    /// 80 ms after that (40 ms stagger). Reduce Motion: plain fades ≤ 200 ms, no drift.
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
            updatedText: viewModel.morningSnapshot.updatedAt.map(EditorialFormat.time),
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

    // MARK: Hero (L1)

    /// Sky style for the current hour / weather / scheme (drives the nav bar glyph colour).
    private var heroStyle: SkyStyle {
        SkyStyle.resolve(hour: hour, condition: weather?.condition, colorScheme: colorScheme)
    }

    private func hero(topInset: CGFloat) -> some View {
        WeatherHero(
            hour: hour,
            weather: weather,
            dateText: EditorialFormat.dateEyebrow(now),
            updatedText: viewModel.morningSnapshot.updatedAt.map(EditorialFormat.time),
            isUpdating: viewModel.isLoading,
            greeting: greetingLine,
            notice: weatherNotice,
            topInset: topInset
        )
        .opacity(sceneIn ? 1 : 0)
    }

    private var weatherNotice: String? {
        let s = viewModel.morningSnapshot
        if !weatherEnabled || !s.weatherEnabled { return nil }
        if s.weatherNeedsLocation { return "Allow Location in Settings to see the weather here." }
        if let detail = s.weatherErrorDetail, !detail.isEmpty {
            if detail.localizedCaseInsensitiveContains("Location") {
                return "Allow Location in Settings to see the weather here."
            }
            return "Weather is unavailable right now. Pull to refresh."
        }
        if viewModel.hasLoaded, !viewModel.isLoading, section("weather") != nil { return "Weather is unavailable right now." }
        return nil
    }

    // MARK: Answer first

    @ViewBuilder
    private var answerBlock: some View {
        VStack(alignment: .leading, spacing: Grid4.greetingToLede) {
            if weather != nil {
                Text(greetingLine)
                    .font(.greeting)
                    .lineSpacing(Leading.greeting)
                    .foregroundStyle(Color.inkPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            lede
        }
        .entrance(delay: 0.12)
    }

    @ViewBuilder
    private var lede: some View {
        if let parts = ledeParts {
            VStack(alignment: .leading, spacing: 8) {
                Text(parts.lede)
                    .font(.lede)
                    .lineSpacing(Leading.lede)
                    .foregroundStyle(Color.inkPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
                if let rest = parts.rest {
                    Text(rest)
                        .font(.secondaryText)
                        .lineSpacing(Leading.secondary)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
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
                .lineSpacing(Leading.lede)
                .foregroundStyle(Color.inkPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(2)
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
            nextCard(schedule)
        } else if let cal = section("calendar"), cal.errorMessage != nil {
            BriefingSectionCard(section: cal)
        }

        if !viewModel.sinceYesterday.isEmpty {
            changesStrip
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

    // MARK: Next (L2)

    /// The one functional surface: the next two events, an "N later" row for the rest, and
    /// an "Earlier today" disclosure.
    private func nextCard(_ schedule: BriefSchedule) -> some View {
        let upcoming = schedule.upcoming
        let shown = Array(upcoming.prefix(2))
        let later = Array(upcoming.dropFirst(2))
        return VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Next")
                .padding(.bottom, 2)
            if upcoming.isEmpty {
                Text("No events remain today.")
                    .font(.bodyText)
                    .foregroundStyle(Color.inkSecondary)
                    .frame(height: Grid4.agendaRow)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, event in
                        eventRow(event, emphasis: true, index: index)
                        if index < shown.count - 1 || !later.isEmpty { Hairline() }
                    }
                    if !later.isEmpty {
                        disclosureRow(title: later.count == 1 ? "1 more event" : "\(later.count) more events", isOpen: $showLater,
                                      label: showLater ? "Hide later events" : "Show \(later.count) later events")
                        if showLater {
                            ForEach(Array(later.enumerated()), id: \.element.id) { index, event in
                                Hairline()
                                eventRow(event, emphasis: false, index: 0)
                            }
                            .transition(.opacity)
                        }
                    }
                }
            }
            if !schedule.earlier.isEmpty {
                Hairline()
                disclosureRow(title: "Earlier today (\(schedule.earlier.count))", isOpen: $showEarlier,
                              label: showEarlier ? "Hide earlier events" : "Show \(schedule.earlier.count) earlier events")
                if showEarlier {
                    ForEach(Array(schedule.earlier.enumerated()), id: \.element.id) { index, event in
                        Hairline()
                        eventRow(event, emphasis: false, index: 0)
                    }
                    .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func eventRow(_ event: CalendarLine, emphasis: Bool, index: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(BriefSchedule.shortTime(event.time))
                .font(.system(size: 15, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.inkSecondary)
                .frame(width: Grid4.timeColumn, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(event.title)
                .font(emphasis ? .agendaTitle : .system(size: 16, weight: .regular))
                .lineSpacing(3)
                .foregroundStyle(emphasis ? Color.inkPrimary : Color.inkSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .frame(minHeight: Grid4.agendaRow)
        .entrance(delay: 0.20 + Double(index) * 0.04)
        .accessibilityElement(children: .combine)
    }

    private func disclosureRow(title: String, isOpen: Binding<Bool>, label: String) -> some View {
        Button {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.25)) { isOpen.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.control)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .medium))
                    .rotationEffect(.degrees(isOpen.wrappedValue ? 180 : 0))
            }
            .foregroundStyle(Color.inkSecondary)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
    }

    // MARK: Changes

    /// Eyebrow plus plain rows with 16 pt glyphs (no strip), at most two rows.
    private var changesStrip: some View {
        let lines = Array(viewModel.sinceYesterday.prefix(2))
        return VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: viewModel.sinceYesterday.count == 1 ? "1 change since yesterday" : "\(viewModel.sinceYesterday.count) changes since yesterday",
                    color: Color.appAccentColor)
                .padding(.bottom, 2)
            ForEach(Array(lines.enumerated()), id: \.element) { index, line in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: changeGlyph(line).name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(changeGlyph(line).color)
                        .frame(width: 20)
                    Text(line)
                        .font(.secondaryText)
                        .lineSpacing(Leading.secondary)
                        .foregroundStyle(Color.inkPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
                .frame(minHeight: 44)
                if index < lines.count - 1 { Hairline() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        case .live: return "Today · delayed up to 5 min"
        default: return nil
        }
    }

    /// One hairline list, no card.
    private var marketsBlock: some View {
        let rows = marketRows
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: "Markets")
                Spacer()
                if let marketsStatusText {
                    Text(marketsStatusText)
                        .font(.system(size: 12, weight: .medium))
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
                .font(.system(size: 12, weight: .medium))
                .symbolRenderingMode(.hierarchical)
            Text(viewModel.aiDaySummary == nil ? "All data stays on your device" : "Written on this iPhone · All data stays on your device")
                .font(.system(size: 12))
        }
        .foregroundStyle(Color.inkSecondary)
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
    /// Preview clock: Monday 10 Nov 2025, 7:40 AM local (a trading day, so "markets opened" holds).
    static var previewNow: Date {
        Calendar.current.date(from: DateComponents(year: 2025, month: 11, day: 10, hour: 7, minute: 40)) ?? Date()
    }

    /// Preview clock in the evening (partly cloudy dusk; all three events already past).
    static var previewEvening: Date {
        Calendar.current.date(from: DateComponents(year: 2025, month: 11, day: 10, hour: 18, minute: 21)) ?? Date()
    }

    static let previewWeatherClear: String = "64°F (Clear) in Murrieta. Feels like 62°F. Humidity 40%. Wind 8 mph W."
    static let previewWeatherRain: String = "52°F (Rain) in Murrieta. Feels like 48°F. Humidity 91%. Wind 14 mph S."
    static let previewWeatherEvening: String = "61°F (Partly Cloudy) in Murrieta. Feels like 59°F. Humidity 48%. Wind 6 mph W."
    static let previewSummaryMorning: String = "A mild morning with three meetings, the first at nine. Markets opened lower, so the standup is the only thing that needs your attention early."
    static let previewSummaryRain: String = "A wet, cool morning with three meetings, the first at nine. Markets opened lower, so the standup is the only thing that needs your attention early."
    static let previewSummaryEvening: String = "All three meetings are behind you and nothing else is on the calendar today. SPY closed lower while BTC held its gain."
    static let previewChangesMorning: [String] = ["SPY is down 2.7% since yesterday's brief", "One new meeting: Dentist at 3:00 PM"]
    static let previewChangesEvening: [String] = ["SPY is down 2.7% since yesterday's brief", "BTC is up 1.1% since yesterday's brief"]

    /// A filled-in model for previews: every section, a two-sentence summary, no loading.
    /// The market series are preview data (see `MarketPreviewData`), not quotes. The weather,
    /// summary and changes passed in must agree with each other (rain is never "mild").
    @MainActor static func previewSample(
        now: Date = BriefingViewModel.previewNow,
        weather: String = BriefingViewModel.previewWeatherClear,
        summary: String = BriefingViewModel.previewSummaryMorning,
        changes: [String] = BriefingViewModel.previewChangesMorning
    ) -> BriefingViewModel {
        let vm = BriefingViewModel()
        vm.isPreview = true
        vm.hasLoaded = true
        vm.isLoading = false
        vm.networkBadge = .online
        vm.aiDaySummary = summary
        vm.sinceYesterday = changes
        let condition = WeatherSummary.parse(weather)?.condition ?? "Clear"
        let shortWeather = WeatherSummary.parse(weather).map { "\($0.temperature)\($0.unit), \($0.condition)" } ?? weather
        vm.briefingSections = [
            BriefingSection(id: "weather", title: "Weather", icon: condition.lowercased().contains("rain") ? "🌧️" : "🌤️",
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
            weatherIcon: "🌤️", weatherLine: shortWeather, location: "Murrieta",
            calendarLine: "3 events, first at 9:00 AM",
            marketQuotes: [
                MorningSnapshotQuote(symbol: "SPY", priceText: "$735.29", change24h: -2.70, prevClose: 755.0, series: MarketPreviewData.spy),
                MorningSnapshotQuote(symbol: "BTC", priceText: "$75,699", change24h: 1.12, prevClose: 74_860, series: MarketPreviewData.btc)
            ],
            marketsStatus: .live, weatherEnabled: true, weatherNeedsLocation: false,
            weatherErrorDetail: nil, updatedAt: now.addingTimeInterval(-19 * 60))
        return vm
    }

    /// Markets tab rows that match the Brief's sample (AAPL has no quote yet).
    @MainActor static var previewMarketRows: MarketsPreviewRows {
        MarketsPreviewRows(
            symbols: [TrackedSymbol(symbol: "SPY", entryPrice: 702.10), TrackedSymbol(symbol: "BTC", entryPrice: nil), TrackedSymbol(symbol: "AAPL", entryPrice: nil)],
            quotes: ["SPY": MarketQuote(price: 735.29, change: -2.70, prevClose: 755.0, series: MarketPreviewData.spy),
                     "BTC": MarketQuote(price: 75699.0, change: 1.12, prevClose: 74_860, series: MarketPreviewData.btc)],
            updatedAt: BriefingViewModel.previewNow.addingTimeInterval(-19 * 60))
    }
}

/// App-level preview: the real tab bar and navigation bars around sample data.
@MainActor private func appPreview(theme: AppTheme, viewModel: BriefingViewModel, now: Date, greeting: String, tab: ContentView.Tab = .brief) -> some View {
    UserDefaults.standard.set(true, forKey: "has_completed_onboarding")
    UserDefaults.standard.set(true, forKey: "weather_enabled")
    ThemeStore.shared.themeRaw = theme.rawValue
    return ContentView(previewViewModel: viewModel, previewNow: now, previewGreeting: greeting,
                       initialTab: tab, previewMarkets: BriefingViewModel.previewMarketRows)
        .preferredColorScheme(theme == .dark ? .dark : .light)
}

#Preview("App · Brief light") {
    appPreview(theme: .light, viewModel: BriefingViewModel.previewSample(), now: BriefingViewModel.previewNow, greeting: "Good morning, Yezid")
}

#Preview("App · Brief dark") {
    appPreview(theme: .dark,
               viewModel: BriefingViewModel.previewSample(now: BriefingViewModel.previewEvening,
                                                          weather: BriefingViewModel.previewWeatherEvening,
                                                          summary: BriefingViewModel.previewSummaryEvening,
                                                          changes: BriefingViewModel.previewChangesEvening),
               now: BriefingViewModel.previewEvening, greeting: "Good evening, Yezid")
}

#Preview("App · Brief rain") {
    UserDefaults.standard.set(true, forKey: "voice_briefing_enabled")
    return appPreview(theme: .light,
                      viewModel: BriefingViewModel.previewSample(weather: BriefingViewModel.previewWeatherRain,
                                                                 summary: BriefingViewModel.previewSummaryRain),
                      now: BriefingViewModel.previewNow, greeting: "Good morning, Yezid")
}

#Preview("App · Markets light") {
    appPreview(theme: .light, viewModel: BriefingViewModel.previewSample(), now: BriefingViewModel.previewNow, greeting: "Good morning, Yezid", tab: .markets)
}

#Preview("App · Markets dark") {
    appPreview(theme: .dark, viewModel: BriefingViewModel.previewSample(), now: BriefingViewModel.previewNow, greeting: "Good morning, Yezid", tab: .markets)
}

#Preview("Brief · no weather") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    let vm = BriefingViewModel.previewSample()
    vm.briefingSections.removeAll { $0.id == "weather" }
    vm.morningSnapshot.weatherNeedsLocation = true
    return BriefTabView(
        viewModel: vm,
        userName: "Yezid",
        localOnly: false,
        isVoicePlaying: .constant(false),
        showShareSheet: .constant(false),
        previewNow: BriefingViewModel.previewNow,
        previewGreeting: "Good morning, Yezid"
    )
    .preferredColorScheme(.light)
}
