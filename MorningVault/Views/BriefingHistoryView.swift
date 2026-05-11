import SwiftUI

// MARK: - Briefing History View

struct BriefingHistoryView: View {
    @State private var entries: [BriefingArchiveEntry] = []
    @State private var selectedEntry: BriefingArchiveEntry?
    @State private var hasAppeared = false
    @State private var isLoading = false
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.warmBackground.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .scaleEffect(1.2)
                } else if entries.isEmpty {
                    EmptyStateView(
                        title: "No Briefings Yet",
                        message: "Your daily briefings will appear here once they're generated.",
                        systemImage: "clock.arrow.circlepath"
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredEntries) { entry in
                                BriefingHistoryCard(entry: entry, onTap: {
                                    selectedEntry = entry
                                })
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                }
            }
            .navigationTitle("Briefing History")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search briefings")
            .sheet(item: $selectedEntry) { entry in
                BriefingDetailView(entry: entry)
            }
            .task {
                await loadEntries()
            }
        }
    }

    private var filteredEntries: [BriefingArchiveEntry] {
        if searchText.isEmpty {
            return entries
        }
        return entries.filter { entry in
            entry.sections.contains { section in
                section.title.localizedCaseInsensitiveContains(searchText) ||
                section.content.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    private func loadEntries() async {
        isLoading = true
        entries = await briefingArchive.getAllEntries()
        isLoading = false
    }
}

// MARK: - History Card

struct BriefingHistoryCard: View {
    let entry: BriefingArchiveEntry
    let onTap: () -> Void

    @State private var hasAppeared = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Date column
                VStack(spacing: 2) {
                    Text(entry.dayOfWeek.prefix(3))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.warmPrimaryAccent)

                    Text(String(Calendar.current.component(.day, from: entry.date)))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.warmTextPrimary)

                    Text(monthAbbr)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 50)

                // Divider
                Rectangle()
                    .fill(Color.warmTextSecondary.opacity(0.2))
                    .frame(width: 1)

                // Content preview
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        if let mood = entry.mood {
                            Text(mood.emoji)
                                .font(.caption)
                            Text(mood.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(entry.sections.count) sections")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if let summary = entry.aiSummary {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(Color.warmTextPrimary)
                            .lineLimit(2)
                    } else {
                        Text(sectionTitles.joined(separator: " • "))
                            .font(.subheadline)
                            .foregroundStyle(Color.warmTextPrimary)
                            .lineLimit(1)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(Color.warmSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.warmTextPrimary.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
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

    private var monthAbbr: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: entry.date)
    }

    private var sectionTitles: [String] {
        entry.sections.prefix(3).map { $0.title }
    }
}

// MARK: - Detail View

struct BriefingDetailView: View {
    let entry: BriefingArchiveEntry
    @Environment(\.dismiss) private var dismiss
    @State private var highlights: [Highlight] = []
    @State private var hasAppeared = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Text(entry.formattedDate)
                            .font(.headline)
                            .foregroundStyle(Color.warmTextSecondary)

                        if let mood = entry.mood {
                            HStack {
                                Text(mood.emoji)
                                    .font(.title2)
                                Text(mood.label)
                                    .font(.title2)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(Color.warmSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .sunriseCard(mood: entry.mood)
                    .padding(.horizontal, 20)

                    // AI Summary
                    if let summary = entry.aiSummary {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("AI Summary", systemImage: "sparkles")
                                .font(.headline)
                                .foregroundStyle(Color.warmAISummary)

                            Text(summary)
                                .font(.body)
                                .foregroundStyle(Color.warmTextPrimary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color.warmSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 20)
                    }

                    // Sections
                    ForEach(entry.sections) { section in
                        BriefingSectionCard(section: section, delay: 0)
                            .padding(.horizontal, 20)
                    }

                    // Highlights
                    if !highlights.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Highlights", systemImage: "highlighter")
                                .font(.headline)

                            ForEach(highlights) { highlight in
                                HighlightRow(highlight: highlight)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color.warmSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.vertical, 20)
            }
            .background(Color.warmBackground.ignoresSafeArea())
            .navigationTitle("Briefing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: entry.id) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .task {
                highlights = await highlightStorage.getHighlights(forSection: "all")
            }
        }
    }
}

// MARK: - Highlight Row

struct HighlightRow: View {
    let highlight: Highlight
    @State private var hasAppeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\"\(highlight.text)\"")
                .font(.body)
                .foregroundStyle(Color.warmTextPrimary)

            if let note = highlight.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(highlight.createdAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color.warmBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .opacity(hasAppeared ? 1 : 0)
        .offset(x: hasAppeared ? 0 : -10)
        .onAppear {
            if !UIAccessibility.isReduceMotionEnabled {
                withAnimation(.easeOut(duration: 0.3)) {
                    hasAppeared = true
                }
            } else {
                hasAppeared = true
            }
        }
    }
}

#Preview {
    BriefingHistoryView()
}