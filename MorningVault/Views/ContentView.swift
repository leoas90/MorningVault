import SwiftUI

struct ContentView: View {
    @AppStorage("local_only") private var localOnly = false
    @AppStorage("user_name") private var userName: String = "Alex"
    @StateObject private var viewModel = BriefingViewModel()
    @State private var selectedTab: Tab = .brief
    @State private var tabBarIconScales: [Tab: CGFloat] = [:]

    enum Tab: String, CaseIterable {
        case brief = "Brief"
        case sources = "Sources"
        case settings = "Settings"

        var icon: String {
            switch self {
            case .brief: return "sun.max"
            case .sources: return "newspaper"
            case .settings: return "gearshape"
            }
        }

        var filledIcon: String {
            switch self {
            case .brief: return "sun.max.fill"
            case .sources: return "newspaper.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // MARK: - Brief Tab
            BriefTabView(viewModel: viewModel, userName: userName, localOnly: localOnly)
                .onChange(of: selectedTab) { oldTab, newTab in
                    if newTab == Tab.brief {
                        Task { await viewModel.loadData() }
                    }
                }
                .tabItem {
                    TabIcon(
                        tab: Tab.brief,
                        isSelected: selectedTab == Tab.brief,
                        scales: $tabBarIconScales
                    )
                }
                .tag(Tab.brief)

            // MARK: - Sources Tab
            NavigationStack {
                SourcesView()
            }
            .tabItem {
                TabIcon(
                    tab: Tab.sources,
                    isSelected: selectedTab == Tab.sources,
                    scales: $tabBarIconScales
                )
            }
            .tag(Tab.sources)

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

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Header with greeting
                    headerSection
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    // Briefing sections with stagger
                    if viewModel.isLoading {
                        LoadingStateView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else if viewModel.briefingSections.isEmpty {
                        EmptyStateView(
                            title: "Set Your Alarm",
                            message: "Configure your briefing time in Settings to get started.",
                            systemImage: "alarm"
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ForEach(Array(viewModel.briefingSections.enumerated()), id: \.element.id) { index, section in
                            BriefingSectionCard(section: section)
                                .padding(.horizontal, 20)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                                    removal: .opacity.combined(with: .move(edge: .top))
                                ))
                        }
                    }

                    // Privacy footer
                    privacyFooter
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                }
            }
            .background(Color.warmBackground.ignoresSafeArea())
            .navigationTitle("Morning Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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
            .refreshable {
                await viewModel.generateBriefing()
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

                // Network badge with local indicator
                BounceLabel(
                    text: "LOCAL",
                    color: Color.warmLocalBadge,
                    icon: "checkmark.shield"
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

#Preview {
    ContentView()
}