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
    @State private var meetingsContainer: ModelContainer? = try? MeetingNotesStore.modelContainer()

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
                showShareSheet: $showShareSheet
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
                    ContentUnavailableView("Meetings unavailable", systemImage: "waveform.slash",
                                           description: Text("The meetings store could not be opened on this device."))
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

    @AppStorage("weather_enabled") private var weatherEnabled = true
    @AppStorage("voice_briefing_enabled") private var voiceBriefingEnabled = false
    @ObservedObject private var voiceService = VoiceBriefingService.shared
    @State private var isRefreshing = false
    @State private var headerHasAppeared = false
    @AppStorage("calendar_enabled") private var calendarEnabled = true
    @AppStorage("health_enabled") private var healthEnabled = true
    @AppStorage("headlines_enabled") private var headlinesEnabled = true
    private let greeting = GreetingService.shared

    private var greetingLine: String { greeting.line }

    private func networkBadgeText() -> String {
        switch viewModel.networkBadge {
        case .local: return "LOCAL"
        case .online: return "LIVE"
        case .none: return ""
        }
    }

    private func networkBadgeColor() -> Color {
        switch viewModel.networkBadge {
        case .local: return Color.warmLocalBadge
        case .online: return Color.warmExternalBadge
        case .none: return .clear
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
        viewModel.networkBadge == .local ? "checkmark.shield" : "network"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    // Header with greeting
                    headerSection
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    MorningSnapshotCard(snapshot: viewModel.morningSnapshot)
                        .padding(.horizontal, 20)

                    // Briefing sections with stagger. The spinner only replaces an empty
                    // screen; a refresh keeps the current cards in place.
                    if viewModel.isLoading && viewModel.briefingSections.isEmpty {
                        LoadingStateView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else if viewModel.briefingSections.isEmpty && viewModel.meetingPrep == nil {
                        let state = emptyState
                        EmptyStateView(
                            title: state.title,
                            message: state.message,
                            systemImage: state.icon
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ForEach(Array(viewModel.briefingSections.enumerated()), id: \.element.id) { index, section in
                            BriefingSectionCard(section: section, delay: Double(index) * AppAnimation.cardStaggerDelay)
                                .padding(.horizontal, 20)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                                    removal: .opacity.combined(with: .move(edge: .top))
                                ))
                        }

                        // Meeting Prep card (Feature #1) — shown after briefing sections
                        if let prep = viewModel.meetingPrep {
                            MeetingPrepCard(prep: Binding(
                                get: { prep },
                                set: { viewModel.meetingPrep = $0 }
                            ))
                            .padding(.horizontal, 20)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity.combined(with: .move(edge: .top))
                            ))
                        }
                    }

                    // AI summary placeholder when localOnly=true
                    if viewModel.aiDaySummary == nil, let reason = viewModel.aiUnavailableReason {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Color.warmAISummary)
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(Color.warmTextSecondary)
                        }
                        .padding(.horizontal, 20)
                    }

                    // Privacy footer
                    privacyFooter
                }
            }
            .background(Color.warmBackground.ignoresSafeArea())
            .navigationTitle("MorningVault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EmptyView()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            if isVoicePlaying {
                                viewModel.stopVoiceBriefing()
                                isVoicePlaying = false
                            } else {
                                viewModel.speakBriefingAloud()
                                isVoicePlaying = true
                            }
                        } label: {
                            Image(systemName: isVoicePlaying ? "stop.circle.fill" : "speaker.wave.2")
                                .foregroundStyle(isVoicePlaying ? Color.warmPrimaryAccent : Color.warmTextSecondary)
                                .symbolEffect(.variableColor.iterative, isActive: isVoicePlaying)
                        }
                        .disabled(!voiceBriefingEnabled)
                        .accessibilityLabel(isVoicePlaying ? "Stop voice briefing" : "Listen to briefing")

                        Button {
                            showShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(Color.warmPrimaryAccent)
                        }
                        .accessibilityLabel("Share briefing")

                        Button {
                            Task {
                                isRefreshing = true
                                await viewModel.generateBriefing()
                                isRefreshing = false
                            }
                        } label: {
                            ZStack {
                                Image(systemName: "arrow.clockwise")
                                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                                    .animation(
                                        isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                                        value: isRefreshing
                                    )
                            }
                        }
                        .disabled(viewModel.isLoading || isRefreshing)
                        .accessibilityLabel("Refresh briefing")
                    }
                }
            }
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
        var lines: [String] = ["☀️ MorningVault — \(dateString)"]
        for section in viewModel.briefingSections.prefix(5) {
            lines.append("• \(section.title): \(section.content)")
        }
        return lines.joined(separator: "\n")
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(greetingLine)
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.warmTextPrimary)

                    if let opener = greeting.opener {
                        Text(opener)
                            .font(.subheadline)
                            .foregroundStyle(Color.warmTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // AI Summary badge and text (badge above, so the summary gets full width)
                    if let summary = viewModel.aiDaySummary {
                        VStack(alignment: .leading, spacing: 4) {
                            BounceLabel(
                                text: "AI summary",
                                color: Color.warmAISummary,
                                icon: "sparkles"
                            )
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(Color.warmTextSecondary)
                                .lineLimit(6)
                                .fixedSize(horizontal: false, vertical: true)
                                .animation(.easeOut(duration: 0.2), value: summary)
                        }
                    }

                    if !viewModel.sinceYesterday.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Since yesterday")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.warmAISummary)
                            ForEach(viewModel.sinceYesterday, id: \.self) { line in
                                Text("• \(line)")
                                    .font(.caption)
                                    .foregroundStyle(Color.warmTextSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.top, 2)
                        .accessibilityElement(children: .combine)
                    }
                }

                Spacer()

                // Network badge — LOCAL or LIVE (online)
                if viewModel.networkBadge != .none {
                    BounceLabel(
                        text: networkBadgeText(),
                        color: networkBadgeColor(),
                        icon: networkBadgeIcon
                    )
                }
            }
        }
        .opacity(headerHasAppeared ? 1 : 0)
        .offset(y: headerHasAppeared ? 0 : -10)
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

    private var privacyFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.caption2)
            Text("All data stays on your device")
                .font(.caption)
        }
        .foregroundStyle(Color.warmTextSecondary)
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

#Preview {
    ContentView()
}