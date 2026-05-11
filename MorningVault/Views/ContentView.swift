import SwiftUI

struct ContentView: View {
    @AppStorage("user_name") private var userName: String = ""
    @AppStorage("local_only") private var localOnly = false
    @AppStorage("has_completed_onboarding") private var hasCompletedOnboarding = false

    @StateObject private var viewModel = BriefingViewModel()
    @State private var selectedTab: Tab = .brief
    @State private var tabBarIconScales: [Tab: CGFloat] = [:]
    @State private var showBriefingFromDeepLink = false

    enum Tab: String, CaseIterable {
        case brief = "Brief"
        case markets = "Markets"
        case history = "History"
        case settings = "Settings"

        var icon: String {
            switch self {
            case .brief: return "sun.max"
            case .markets: return "chart.line.uptrend.xyaxis"
            case .history: return "clock.arrow.circlepath"
            case .settings: return "gearshape"
            }
        }

        var filledIcon: String {
            switch self {
            case .brief: return "sun.max.fill"
            case .markets: return "chart.line.uptrend.xyaxis"
            case .history: return "clock.arrow.circlepath"
            case .settings: return "gearshape.fill"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // MARK: - Brief Tab
            BriefTabView(viewModel: viewModel, userName: userName, localOnly: localOnly)
                .tabItem {
                    TabIcon(
                        tab: Tab.brief,
                        isSelected: selectedTab == Tab.brief,
                        scales: $tabBarIconScales
                    )
                }
                .tag(Tab.brief)

            // MARK: - Markets Tab
            NavigationStack {
                MarketsView()
            }
            .tabItem {
                TabIcon(
                    tab: Tab.markets,
                    isSelected: selectedTab == Tab.markets,
                    scales: $tabBarIconScales
                )
            }
            .tag(Tab.markets)

            // MARK: - History Tab
            NavigationStack {
                BriefingHistoryView()
            }
            .tabItem {
                TabIcon(
                    tab: Tab.history,
                    isSelected: selectedTab == Tab.history,
                    scales: $tabBarIconScales
                )
            }
            .tag(Tab.history)

            // MARK: - Settings Tab
            NavigationStack {
                SettingsView()
            }
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
            // Try to read the user's name from their Me card / device (off main thread)
            let fetchedName = await ContactsService.shared.fetchDeviceName()
            // Silent refresh: load from cache for instant display, background refresh follows
            await viewModel.silentRefresh()
        }
        .fullScreenCover(isPresented: .constant(!hasCompletedOnboarding)) {
            OnboardingView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .viewBriefingRequested)) { _ in
            // User tapped "View Brief" notification — switch to Brief tab and refresh
            selectedTab = .brief
            Task {
                await viewModel.silentRefresh()
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
                .font(.system(size: 20))
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

    @State private var isRefreshing = false
    @State private var headerHasAppeared = false
    @State private var showMoodPicker = false
    @State private var showShareSheet = false
    @State private var selectedMood: MoodType? = nil
    @State private var isVoicePlaying = false

    private var greetingText: String {
        contextualSignal.currentTimeGreeting
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    // Header with greeting
                    headerSection
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    // Briefing sections with stagger
                    if viewModel.isLoading {
                        LoadingStateView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else if viewModel.briefingSections.isEmpty && viewModel.meetingPrep == nil {
                        EmptyStateView(
                            title: "Set Your Alarm",
                            message: "Configure your briefing time in Settings to get started.",
                            systemImage: "alarm"
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ForEach(Array(viewModel.briefingSections.enumerated()), id: \.element.id) { index, section in
                            // Use enumerated index for stagger delay
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

                        // Audio Play Button — appears after sections
                        AudioPlayButton(sections: viewModel.briefingSections) { audioService in
                            // Audio service is ready — listen button shown above privacy footer
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }

                    // AI summary placeholder when localOnly=true
                    if localOnly && viewModel.aiDaySummary == nil {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Color.warmAISummary)
                            Text("AI summary disabled — enable live data in Settings to unlock.")
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
            .navigationTitle("Morning Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showMoodPicker = true
                    } label: {
                        Image(systemName: "face.smiling")
                            .foregroundStyle(Color.warmPrimaryAccent)
                    }
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
                            ZStack {
                                Image(systemName: isVoicePlaying ? "speaker.wave.3.fill" : "speaker.wave.2")
                                    .foregroundStyle(isVoicePlaying ? Color.warmPrimaryAccent : Color.warmTextSecondary)
                                if isVoicePlaying {
                                    Text("Playing...")
                                        .font(.caption2)
                                        .foregroundStyle(Color.warmPrimaryAccent)
                                        .offset(y: 16)
                                }
                            }
                        }
                        .disabled(!UserDefaults.standard.bool(forKey: "voice_briefing_enabled"))

                        Button {
                            showShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(Color.warmPrimaryAccent)
                        }

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
                    }
                }
            }
            .refreshable {
                isRefreshing = true
                await viewModel.generateBriefing()
                isRefreshing = false
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: isRefreshing) { _, refreshing in
                if !refreshing {
                    // Reset refresh indicator when done
                }
            }
            .sheet(isPresented: $showMoodPicker) {
                MorningMoodView(selectedMood: $selectedMood)
            }
            .sheet(isPresented: $showShareSheet) {
                BriefingShareView(
                    sections: viewModel.briefingSections,
                    aiSummary: viewModel.aiDaySummary,
                    highlights: [],
                    mood: selectedMood
                )
            }
            .task {
                await viewModel.loadData()
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    // Greeting with time-of-day feel
                    Text("\(greetingText), \(userName).")
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.warmTextPrimary)

                    // AI Summary badge and text
                    if let summary = viewModel.aiDaySummary {
                        HStack(spacing: 8) {
                            BounceLabel(
                                text: "AI Summary",
                                color: Color.warmAISummary,
                                icon: "sparkles"
                            )
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(Color.warmTextSecondary)
                                .lineLimit(2)
                        }
                    }
                }

                Spacer()

                // Network badge — shows LIVE when external (Polygon.io/WeatherKit/RSS), LOCAL when cache-only
                BounceLabel(
                    text: viewModel.networkBadge == .local ? "LOCAL" : "LIVE",
                    color: viewModel.networkBadge == .local ? Color.warmLocalBadge : Color.warmExternalBadge,
                    icon: viewModel.networkBadge == .local ? "checkmark.shield" : "network"
                )
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

// MARK: - Custom Refresh Header (animated sun with spinner)
struct CustomRefreshHeader: View {
    let isRefreshing: Bool
    @State private var rotation: Double = 0
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        Group {
            if isRefreshing {
                VStack(spacing: 6) {
                    ZStack {
                        // Outer pulse ring
                        Circle()
                            .stroke(Color.warmPrimaryAccent.opacity(0.2), lineWidth: 2)
                            .frame(width: 44, height: 44)
                            .scaleEffect(pulseScale)
                            .opacity(2.0 - Double(pulseScale))

                        // Rotating sun icon
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.warmPrimaryAccent)
                            .rotationEffect(.degrees(rotation))
                    }

                    Text("Refreshing...")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.warmTextSecondary)
                }
                .frame(height: 60)
                .frame(maxWidth: .infinity)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onChange(of: isRefreshing) { _, refreshing in
            if refreshing {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
                withAnimation(.easeOut(duration: 1.0).repeatForever(autoreverses: false)) {
                    pulseScale = 1.6
                }
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    rotation = 0
                    pulseScale = 1.0
                }
            }
        }
        .onAppear {
            if isRefreshing {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
                withAnimation(.easeOut(duration: 1.0).repeatForever(autoreverses: false)) {
                    pulseScale = 1.6
                }
            }
        }
    }
}

#Preview {
    ContentView()
}