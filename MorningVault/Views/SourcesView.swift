import SwiftUI

struct SourcesView: View {
    @State private var sources: [NewsSource] = []

    var body: some View {
        List {
            Section("News Sources") {
                if sources.isEmpty {
                    Text("No sources selected. Go to Settings to add sources.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sources) { source in
                        HStack {
                            Image(systemName: source.icon)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 28)
                            VStack(alignment: .leading) {
                                Text(source.displayName)
                                    .font(.subheadline)
                                Text(source.feedURL)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
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
        sources = loadSelectedSources()
    }
}

// MARK: - Source Editor View

struct SourceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSources: Set<NewsSource> = []

    var body: some View {
        List {
            ForEach(NewsSource.allCases) { source in
                Button {
                    if selectedSources.contains(source) {
                        selectedSources.remove(source)
                    } else {
                        selectedSources.insert(source)
                    }
                } label: {
                    HStack {
                        Image(systemName: source.icon)
                            .foregroundStyle(selectedSources.contains(source) ? Color.accentColor : .secondary)
                            .frame(width: 28)
                        VStack(alignment: .leading) {
                            Text(source.displayName)
                                .foregroundStyle(.primary)
                            Text(source.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: selectedSources.contains(source) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedSources.contains(source) ? Color.accentColor : .secondary)
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
        selectedSources = Set(loadSelectedSources())
    }

    private func saveAndDismiss() {
        saveSelectedSources(Array(selectedSources))
        dismiss()
    }
}

#Preview {
    NavigationStack { SourcesView() }
}