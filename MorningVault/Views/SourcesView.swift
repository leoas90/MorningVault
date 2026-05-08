import SwiftUI

struct SourcesView: View {
    @AppStorage("selected_news_sources") private var selectedSourcesData: Data = Data()
    @State private var sources: [RSSSource] = []

    private struct RSSSource: Codable, Identifiable {
        let id: String
        let name: String
        let url: String
    }

    var body: some View {
        List {
            Section("News Sources") {
                if sources.isEmpty {
                    Text("No sources selected. Go to Settings to add sources.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sources) { source in
                        HStack {
                            Image(systemName: "newspaper")
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading) {
                                Text(source.name)
                                    .font(.subheadline)
                                Text(source.url)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                NavigationLink {
                    SourceEditorView()
                } label: {
                    Label("Manage Sources", systemImage: "plus.circle")
                }
            }
        }
        .navigationTitle("Sources")
        .onAppear { loadSources() }
    }

    private func loadSources() {
        let sourceURLs: [String: String] = [
            "hacker-news": "https://hnrss.org/frontpage",
            "techcrunch": "https://techcrunch.com/feed/",
            "ars-technica": "https://feeds.arstechnica.com/arstechnica/index",
            "bbc": "https://feeds.bbci.co.uk/news/rss.xml",
            "reuters": "https://www.reutersagency.com/feed/",
            "ap": "https://apnews.com/rss",
            "npr": "https://feeds.npr.org/1001/rss.xml",
            "the-verge": "https://www.theverge.com/rss/index.xml",
            "wired": "https://www.wired.com/feed/rss",
            "bloomberg": "https://feeds.bloomberg.com/markets/news.rss"
        ]

        let displayNames: [String: String] = [
            "hacker-news": "Hacker News",
            "techcrunch": "TechCrunch",
            "ars-technica": "Ars Technica",
            "bbc": "BBC News",
            "reuters": "Reuters",
            "ap": "Associated Press",
            "npr": "NPR",
            "the-verge": "The Verge",
            "wired": "Wired",
            "bloomberg": "Bloomberg"
        ]

        if let data = try? JSONDecoder().decode([String].self, from: selectedSourcesData) {
            sources = data.compactMap { id in
                guard let url = sourceURLs[id] else { return nil }
                return RSSSource(id: id, name: displayNames[id] ?? id.capitalized, url: url)
            }
        } else {
            // Default to Hacker News
            sources = [
                RSSSource(id: "hacker-news", name: "Hacker News", url: sourceURLs["hacker-news"]!)
            ]
        }
    }
}

// MARK: - Source Editor View

struct SourceEditorView: View {
    @AppStorage("selected_news_sources") private var selectedSourcesData: Data = Data()
    @Environment(\.dismiss) private var dismiss

    private let allSources: [(id: String, name: String, description: String, icon: String)] = [
        ("hacker-news", "Hacker News", "Tech & startup news", "chevron.left.forwardslash.chevron.right"),
        ("techcrunch", "TechCrunch", "Startup coverage", "dollarsign.circle"),
        ("ars-technica", "Ars Technica", "Deep tech & science", "atom"),
        ("bbc", "BBC News", "World news", "globe"),
        ("reuters", "Reuters", "Breaking news", "bolt"),
        ("ap", "Associated Press", "National news", "newspaper"),
        ("npr", "NPR", "Public radio", "waveform"),
        ("the-verge", "The Verge", "Tech culture", "desktopcomputer"),
        ("wired", "Wired", "Tech magazine", "wifi"),
        ("bloomberg", "Bloomberg", "Business & finance", "chart.line.uptrend.xyaxis")
    ]

    @State private var selectedSources: Set<String> = []

    var body: some View {
        List {
            ForEach(allSources, id: \.id) { source in
                Button {
                    if selectedSources.contains(source.id) {
                        selectedSources.remove(source.id)
                    } else {
                        selectedSources.insert(source.id)
                    }
                } label: {
                    HStack {
                        Image(systemName: source.icon)
                            .foregroundStyle(selectedSources.contains(source.id) ? Color.accentColor : .secondary)
                            .frame(width: 28)
                        VStack(alignment: .leading) {
                            Text(source.name)
                                .foregroundStyle(.primary)
                            Text(source.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: selectedSources.contains(source.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedSources.contains(source.id) ? Color.accentColor : .secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Edit Sources")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadSelected() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { saveAndDismiss() }
            }
        }
    }

    private func loadSelected() {
        if let data = try? JSONDecoder().decode([String].self, from: selectedSourcesData) {
            selectedSources = Set(data)
        }
    }

    private func saveAndDismiss() {
        if let encoded = try? JSONEncoder().encode(Array(selectedSources)) {
            selectedSourcesData = encoded
        }
        dismiss()
    }
}

#Preview {
    NavigationStack { SourcesView() }
}