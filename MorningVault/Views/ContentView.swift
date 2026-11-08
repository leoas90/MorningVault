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

struct BriefTabView: View {
    @ObservedObject var viewModel: BriefingViewModel
    let userName: String
    let localOnly: Bool
    @Binding var isVoicePlaying: Bool
    @Binding var showShareSheet: Bool
    /// Tap on the Markets card switches to the Markets tab.
    var onOpenMarkets: (() -> Void)? = nil
    /// Previews only: pin the hero gradient to an hour instead of the clock.
    var previewHour: Int? = nil

    @AppStorage("weather_enabled") private var weatherEnabled = true
    @AppStorage("voice_briefing_enabled") private var voiceBriefingEnabled = false
    @ObservedObject private var voiceService = VoiceBriefingService.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var isRefreshing = false
    @State private var headerHasAppeared = false
    @AppStorage("calendar_enabled") private var calendarEnabled = true
    @AppStorage("health_enabled") private var healthEnabled = true
    @AppStorage("headlines_enabled") private var headlinesEnabled = true
    private let greeting = GreetingService.shared

    private var greetingLine: String {
        let line = greeting.line
        return line.hasSuffix(".") ? line : line + "."
    }

    private var heroHour: Int {
        previewHour ?? Calendar.current.component(.hour, from: Date())
    }

    /// Ink on the sunrise/day washes, white on pre-dawn/dusk and in dark mode.
    private var heroInk: Color {
        TimeOfDayGradient.usesLightText(hour: heroHour, colorScheme: colorScheme) ? Color.white : Color.inkPrimary
    }

    private var heroInkSecondary: Color {
        TimeOfDayGradient.usesLightText(hour: heroHour, colorScheme: colorScheme)
            ? Color.white.opacity(0.85) : Color.inkPrimary.opacity(0.72)
    }

    private func networkBadgeText() -> String {
        switch viewModel.networkBadge {
        case .local: return "Local"
        case .online: return "Live"
        case .none: return ""
        }
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

    private var networkBadgeIcon: String {
        viewModel.networkBadge == .local ? "checkmark.shield" : "dot.radiowaves.left.and.right"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    heroSection

                    LazyVStack(spacing: 16) {
                        MorningSnapshotCard(snapshot: viewModel.morningSnapshot)

                        // Briefing sections with stagger. The skeleton only replaces an empty
                        // screen; a refresh keeps the current cards in place.
                        if viewModel.isLoading && viewModel.briefingSections.isEmpty {
                            LoadingStateView()
                        } else if viewModel.briefingSections.isEmpty && viewModel.meetingPrep == nil {
                            let state = emptyState
                            EmptyStateView(
                                title: state.title,
                                message: state.message,
                                systemImage: state.icon
                            )
                        } else {
                            ForEach(Array(viewModel.briefingSections.enumerated()), id: \.element.id) { index, section in
                                BriefingSectionCard(
                                    section: section,
                                    delay: Double(index) * AppAnimation.cardStaggerDelay,
                                    onOpenMarkets: section.id == "markets" ? onOpenMarkets : nil
                                )
                                .transition(.opacity)
                            }

                            // Meeting Prep card (Feature #1) — shown after briefing sections
                            if let prep = viewModel.meetingPrep {
                                MeetingPrepCard(prep: Binding(
                                    get: { prep },
                                    set: { viewModel.meetingPrep = $0 }
                                ))
                                .transition(.opacity)
                            }
                        }

                        privacyFooter
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
            }
            .background(Color.backgroundColor.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                isRefreshing = true
                await viewModel.generateBriefing()
                isRefreshing = false
            }
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
                ShareSheet(items: [briefingShareText()])
                    .presentationDetents([.medium, .large])
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

    private func briefingShareText() -> String {
        let dateString = Date().formatted(date: .complete, time: .omitted)
        var lines: [String] = ["MorningVault — \(dateString)"]
        for section in viewModel.briefingSections.prefix(5) {
            lines.append("• \(section.title): \(section.content)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Hero

    /// Masthead: date eyebrow, serif greeting, the AI day summary as the lede, then the
    /// Listen / Share / Refresh pills. The time-of-day wash sits behind it and runs under
    /// the status bar.
    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: EditorialFormat.dateEyebrow(), color: heroInkSecondary)
                Spacer()
                if viewModel.networkBadge != .none {
                    HStack(spacing: 4) {
                        Image(systemName: networkBadgeIcon)
                        Text(networkBadgeText())
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(heroInkSecondary)
                    .accessibilityLabel(viewModel.networkBadge == .local ? "Local only" : "Live data")
                }
            }

            Text(greetingLine)
                .font(.display(34))
                .foregroundStyle(heroInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if let opener = greeting.opener {
                Text(opener)
                    .font(.system(.subheadline, design: .serif).italic())
                    .foregroundStyle(heroInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            lede

            if !viewModel.sinceYesterday.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "Since yesterday", color: heroInkSecondary)
                    ForEach(viewModel.sinceYesterday, id: \.self) { line in
                        Text(line)
                            .font(.footnote)
                            .foregroundStyle(heroInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            actionRow
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 22)
        .background {
            ZStack(alignment: .bottom) {
                TimeOfDayGradient(hour: heroHour)
                LinearGradient(colors: [.clear, Color.backgroundColor], startPoint: .center, endPoint: .bottom)
                    .frame(height: 90)
            }
            .ignoresSafeArea(edges: .top)
        }
        .opacity(headerHasAppeared ? 1 : 0)
        .onAppear {
            if !UIAccessibility.isReduceMotionEnabled {
                withAnimation(.easeOut(duration: 0.4)) {
                    headerHasAppeared = true
                }
            } else {
                headerHasAppeared = true
            }
        }
    }

    @ViewBuilder
    private var lede: some View {
        if let summary = viewModel.aiDaySummary {
            VStack(alignment: .leading, spacing: 8) {
                Text(summary)
                    .font(.lede)
                    .lineSpacing(4)
                    .foregroundStyle(heroInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(.easeOut(duration: 0.2), value: summary)
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                    Text("Written on this iPhone")
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(heroInkSecondary)
                .accessibilityLabel("Day summary written on this iPhone")
            }
        } else if viewModel.isGeneratingAI {
            VStack(alignment: .leading, spacing: 8) {
                SkeletonLine(height: 14)
                SkeletonLine(width: 220, height: 14)
            }
            .accessibilityLabel("Writing your day summary")
        } else if let reason = viewModel.aiUnavailableReason {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                Text(reason)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(heroInkSecondary)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            // Listen only shows when Voice briefing is on in Settings; a greyed-out pill
            // read as broken.
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
            }

            PillButton(title: "Share", systemImage: "square.and.arrow.up", prominent: !voiceBriefingEnabled) {
                showShareSheet = true
            }
            .accessibilityLabel("Share briefing")

            Button {
                Task {
                    isRefreshing = true
                    await viewModel.generateBriefing()
                    isRefreshing = false
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.inkPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.surfaceColor, in: Circle())
                    .overlay(Circle().strokeBorder(Color.inkPrimary.opacity(0.16), lineWidth: 1))
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .animation(
                        isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                        value: isRefreshing
                    )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading || isRefreshing)
            .accessibilityLabel("Refresh briefing")

            Spacer(minLength: 0)
        }
    }

    private var privacyFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.caption2)
            Text("All data stays on your device")
                .font(.caption)
        }
        .foregroundStyle(Color.inkSecondary)
        .padding(.vertical, 8)
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
    /// A filled-in model for previews: every section, a two-sentence summary, no loading.
    @MainActor static func previewSample() -> BriefingViewModel {
        let vm = BriefingViewModel()
        vm.hasLoaded = true
        vm.isLoading = false
        vm.networkBadge = .online
        vm.aiDaySummary = "A mild, partly cloudy morning with three meetings, the first at nine. Markets opened lower, so the standup is the only thing that needs your attention early."
        vm.sinceYesterday = ["SPY is down 2.7% since yesterday's brief", "One new meeting: Dentist at 3:00 PM"]
        vm.briefingSections = [
            BriefingSection(id: "weather", title: "Weather", icon: "🌤️",
                            content: "64°F (Partly Cloudy) in Murrieta. Feels like 62°F. Humidity 40%. Wind 8 mph W.",
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
        vm.morningSnapshot = MorningSnapshot(
            weatherIcon: "🌤️", weatherLine: "64°F, Partly Cloudy", location: "Murrieta",
            calendarLine: "3 events, first at 9:00 AM",
            marketQuotes: [
                MorningSnapshotQuote(symbol: "SPY", priceText: "$735.29", change24h: -2.70),
                MorningSnapshotQuote(symbol: "BTC", priceText: "$75,699", change24h: 1.12)
            ],
            marketsStatus: .live, weatherEnabled: true, weatherNeedsLocation: false,
            weatherErrorDetail: nil, updatedAt: Date())
        return vm
    }
}

#Preview("Brief · light") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    return BriefTabView(
        viewModel: BriefingViewModel.previewSample(),
        userName: "Yezid",
        localOnly: false,
        isVoicePlaying: .constant(false),
        showShareSheet: .constant(false),
        previewHour: 7
    )
    .preferredColorScheme(.light)
}

#Preview("Brief · dark") {
    ThemeStore.shared.themeRaw = AppTheme.dark.rawValue
    return BriefTabView(
        viewModel: BriefingViewModel.previewSample(),
        userName: "Yezid",
        localOnly: false,
        isVoicePlaying: .constant(false),
        showShareSheet: .constant(false)
    )
    .preferredColorScheme(.dark)
}

#Preview("App") {
    ContentView()
}
