import SwiftUI

struct SourcesView: View {
    @AppStorage("rss_sources") private var rssSourcesData: Data = Data()
    @State private var sources: [RSSSource] = []

    private struct RSSSource: Codable, Identifiable {
        let id: String
        let name: String
        let url: String
    }

    var body: some View {
        List {
            Section("News Sources") {
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

            Section {
                Button {
                    // Placeholder: open RSS editor
                } label: {
                    Label("Manage Sources", systemImage: "plus.circle")
                }
            }
        }
        .navigationTitle("Sources")
        .onAppear { loadSources() }
    }

    private func loadSources() {
        if let data = try? JSONDecoder().decode([RSSSource].self, from: rssSourcesData), !data.isEmpty {
            sources = data
        } else {
            sources = [
                RSSSource(id: "1", name: "Hacker News", url: "news.ycombinator.com"),
                RSSSource(id: "2", name: "TechCrunch", url: "techcrunch.com"),
                RSSSource(id: "3", name: "The Verge", url: "theverge.com")
            ]
        }
    }
}

#Preview {
    NavigationStack { SourcesView() }
}