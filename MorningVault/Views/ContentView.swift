import SwiftUI
import UIKit
import SwiftData
import MeetingNotesKit

struct ContentView: View {
    @AppStorage("user_name") private var userName: String = ""
    @AppStorage("local_only") private var localOnly = false
    @AppStorage("has_completed_onboarding") private var hasCompletedOnboarding = false
    @AppStorage("theme") private var themeRaw: String = AppTheme.system.rawValue
    @AppStorage("appearance") private var appearanceRaw: String = "warm"

    @StateObject private var viewModel = BriefingViewModel()
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
            case .meetings: return "waveform.circle.fill"
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
        .id(themeRaw + appearanceRaw)
        .tint(Color.warmPrimaryAccent)
        .task {
            AIService.shared.prewarm()
            _ = await ContactsService.shared.fetchDeviceName()
            await viewModel.silentRefresh()
        }
        .fullScreenCover(isPresented: .constant(!hasCompletedOnboarding)) {
            OnboardingView()
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
    @Binding var isVoicePlaying: Bool
    @Binding var showShareSheet: Bool

    @AppStorage("weather_enabled") private var weatherEnabled = true
    @AppStorage("voice_briefing_enabled") private var voiceBriefingEnabled = false
    @ObservedObject private var voiceService = VoiceBriefingService.shared
    @State private var isRefreshing = false
    @State private var headerHasAppeared = false

    private var greetingLine: String {
        let name = userName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "\(greetingText)." : "\(greetingText), \(name)."
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<21: return "Good evening"
        default: return "Hello"
        }
    }

    private func networkBadgeText() -> String {
        switch viewModel.networkBadge {
        case .local: return "LOCAL"
        case .online: return "LIVE"
        case .email: return "EMAIL"
        case .none: return ""
        }
    }

    private func networkBadgeColor() -> Color {
        switch viewModel.networkBadge {
        case .local: return Color.warmLocalBadge
        case .online: return Color.warmExternalBadge
        case .email: return .orange
        case .none: return .clear
        }
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
                        EmptyStateView(
                            title: "Set Your Alarm",
                            message: "Configure your briefing time in Settings to get started.",
                            systemImage: "alarm"
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
            .navigationTitle("Morning Vault")
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

                    // AI Summary badge and text (badge above, so the summary gets full width)
                    if let summary = viewModel.aiDaySummary {
                        VStack(alignment: .leading, spacing: 4) {
                            BounceLabel(
                                text: "AI Summary",
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

                // Network badge — 3-state: LOCAL, LIVE (online), EMAIL
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