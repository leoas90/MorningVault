import SwiftUI

// MARK: - Daily Briefing Archive View

struct DailyArchiveView: View {
    @State private var entries: [BriefingArchiveEntry] = []
    @State private var selectedMonth: Date = Date()
    @State private var hasAppeared = false
    @State private var isLoading = false

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ZStack {
                Color.warmBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Month selector
                    MonthSelectorView(selectedMonth: $selectedMonth)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)

                    if isLoading {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.2)
                        Spacer()
                    } else if entriesForMonth.isEmpty {
                        Spacer()
                        EmptyStateView(
                            title: "No Briefings",
                            message: "No briefings archived for \(monthYearString).",
                            systemImage: "calendar.badge.exclamationmark"
                        )
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(entriesForMonth) { entry in
                                    ArchiveDayRow(entry: entry)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        }
                    }
                }
            }
            .navigationTitle("Archive")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await loadEntries()
            }
            .onChange(of: selectedMonth) { _, _ in
                Task { await loadEntries() }
            }
        }
    }

    private var entriesForMonth: [BriefingArchiveEntry] {
        entries.filter { calendar.isDate($0.date, equalTo: selectedMonth, toGranularity: .month) }
    }

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: selectedMonth)
    }

    private func loadEntries() async {
        isLoading = true
        entries = await briefingArchive.getAllEntries()
        isLoading = false
    }
}

// MARK: - Month Selector

struct MonthSelectorView: View {
    @Binding var selectedMonth: Date

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: selectedMonth)
    }

    var body: some View {
        HStack {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .foregroundStyle(Color.warmPrimaryAccent)
            }

            Spacer()

            Text(monthYearString)
                .font(.headline)
                .foregroundStyle(Color.warmTextPrimary)

            Spacer()

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .foregroundStyle(Color.warmPrimaryAccent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.warmSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Archive Day Row

struct ArchiveDayRow: View {
    let entry: BriefingArchiveEntry
    @State private var hasAppeared = false
    @State private var isExpanded = false

    private var dayOfWeek: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: entry.date)
    }

    private var dayNumber: String {
        String(Calendar.current.component(.day, from: entry.date))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Day header
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 16) {
                    // Day number
                    VStack(spacing: 2) {
                        Text(dayOfWeek.prefix(3))
                            .font(.caption2)
                            .foregroundStyle(Color.warmPrimaryAccent)
                        Text(dayNumber)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.warmTextPrimary)
                    }
                    .frame(width: 44)

                    // Summary
                    VStack(alignment: .leading, spacing: 4) {
                        if let mood = entry.mood {
                            HStack(spacing: 4) {
                                Text(mood.emoji)
                                    .font(.caption)
                                Text(mood.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(entry.aiSummary ?? sectionSummary)
                            .font(.subheadline)
                            .foregroundStyle(Color.warmTextPrimary)
                            .lineLimit(isExpanded ? 10 : 1)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(Color.warmSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(entry.sections) { section in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: section.icon)
                                .font(.caption)
                                .foregroundStyle(Color.warmPrimaryAccent)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(section.title)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.warmTextSecondary)

                                Text(section.content)
                                    .font(.caption)
                                    .foregroundStyle(Color.warmTextPrimary)
                                    .lineLimit(3)
                            }

                            Spacer()
                        }
                    }
                }
                .padding(16)
                .background(Color.warmBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 10)
        .onAppear {
            if !UIAccessibility.isReduceMotionEnabled {
                withAnimation(.easeOut(duration: 0.35)) {
                    hasAppeared = true
                }
            } else {
                hasAppeared = true
            }
        }
    }

    private var sectionSummary: String {
        entry.sections.prefix(2).map { $0.title }.joined(separator: " • ")
    }
}

// MARK: - Stats View

struct ArchiveStatsView: View {
    @State private var moodTrend: [MoodEntry] = []
    @State private var avgSections = 0
    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: 16) {
            // Stats cards
            HStack(spacing: 12) {
                StatCard(
                    title: "Mood Trend",
                    value: moodTrend.isEmpty ? "—" : moodTrend.last?.mood.emoji ?? "—",
                    subtitle: "\(moodTrend.count) days"
                )

                StatCard(
                    title: "Avg Sections",
                    value: "\(avgSections)",
                    subtitle: "per day"
                )
            }

            // Mood trend chart
            if !moodTrend.isEmpty {
                MoodTrendView(moodEntries: moodTrend)
            }
        }
        .padding(20)
        .background(Color.warmSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 10)
        .onAppear {
            if !UIAccessibility.isReduceMotionEnabled {
                withAnimation(.easeOut(duration: 0.4)) {
                    hasAppeared = true
                }
            } else {
                hasAppeared = true
            }
        }
        .task {
            moodTrend = await briefingArchive.getMoodTrend()
            avgSections = await briefingArchive.getAverageSectionsPerDay()
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(Color.warmTextPrimary)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.warmBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    DailyArchiveView()
}