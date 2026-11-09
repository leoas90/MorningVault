import SwiftUI

/// Everything saved with "Save for later": hairline rows, newest first. Tapping opens the
/// story in the same in-app reader the Brief uses; swipe removes it.
///
/// Reachable from the Brief's Headlines block and from Settings > Data sources, and it stays
/// readable with Headlines turned off: the list is the user's, not the feed's.
struct SavedArticlesView: View {
    @ObservedObject var store: SavedArticleStore
    @ObservedObject private var readState = NewsReadStateTracker.shared
    /// Story open in the reader; nil when closed.
    @State private var reader: ReaderLink?

    init(store: SavedArticleStore = .shared) {
        self.store = store
    }

    private struct ReaderLink: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    var body: some View {
        Group {
            if store.articles.isEmpty {
                empty
            } else {
                list
            }
        }
        .background(Color.backgroundColor.ignoresSafeArea())
        .navigationTitle("Saved")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $reader) { link in
            SafariView(url: link.url)
                .ignoresSafeArea()
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Saved")
            Text("Nothing saved yet")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.inkPrimary)
            Text("Save for later on a headline keeps it here, even after the feed moves on.")
                .font(.secondaryText)
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Grid4.margin)
        .padding(.top, 20)
    }

    private var list: some View {
        List {
            Section {
                ForEach(store.articles) { article in
                    Button {
                        open(article)
                    } label: {
                        row(article)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 0, leading: Grid4.margin, bottom: 0, trailing: Grid4.margin))
                    .listRowSeparatorTint(Color.hairline)
                    .listRowBackground(Color.backgroundColor)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            unsave(article)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.compactMap { store.articles.indices.contains($0) ? store.articles[$0].id : nil }
                    for id in ids where readState.state(for: id) == .later { readState.markUnread(id) }
                    store.remove(atOffsets: offsets)
                }
            }

            // Count as a last row, not a Section footer: a plain-list footer draws its own
            // pale band and ignores the row insets, which broke the hairline grid.
            Text(store.articles.count == 1 ? "1 saved story" : "\(store.articles.count) saved stories")
                .font(.metaText)
                .foregroundStyle(Color.inkSecondary)
                .frame(minHeight: 36)
                .listRowInsets(EdgeInsets(top: 0, leading: Grid4.margin, bottom: 0, trailing: Grid4.margin))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.backgroundColor)
                .accessibilityHidden(true)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(_ article: SavedArticle) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(article.title)
                .font(.bodyText)
                .foregroundStyle(Color.inkPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)
            if let gist = article.gist {
                Text(gist)
                    .font(.metaText)
                    .foregroundStyle(Color.inkSecondary)
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                Text(article.sourceName)
                Text("·")
                Text(article.savedText())
            }
            .font(.metaText)
            .foregroundStyle(Color.inkSecondary)
            .lineLimit(1)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(article.title), \(article.sourceName), \(article.savedText())")
        .accessibilityHint(SafariView.isOpenable(article.url) ? "Opens the story" : "")
    }

    /// Opening from the saved list also marks the story read and takes it off the list:
    /// that is what "later" was for.
    private func open(_ article: SavedArticle) {
        guard let url = SafariView.openableURL(from: article.url) else { return }
        readState.markRead(article.id)
        store.remove(id: article.id)
        reader = ReaderLink(url: url)
    }

    private func unsave(_ article: SavedArticle) {
        if readState.state(for: article.id) == .later { readState.markUnread(article.id) }
        store.remove(id: article.id)
    }
}

/// "Saved (3)" link under the Brief's headlines, shown only when something is saved.
struct SavedArticlesLink: View {
    @ObservedObject var store: SavedArticleStore

    init(store: SavedArticleStore = .shared) {
        self.store = store
    }

    var body: some View {
        if store.count > 0 {
            NavigationLink {
                SavedArticlesView(store: store)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Saved (\(store.count))")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Color.inkSecondary)
                .frame(minHeight: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Saved stories, \(store.count)")
        }
    }
}

// MARK: - Previews

@MainActor
private func savedPreviewStore(_ articles: [SavedArticle]) -> SavedArticleStore {
    let suite = UserDefaults(suiteName: "preview.saved.\(UUID().uuidString)") ?? .standard
    let store = SavedArticleStore(defaults: suite, key: "preview")
    for article in articles.reversed() { store.save(article) }
    return store
}

#Preview("Saved") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    return NavigationStack {
        SavedArticlesView(store: savedPreviewStore(SavedArticle.sample))
    }
}

#Preview("Saved, empty") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    return NavigationStack {
        SavedArticlesView(store: savedPreviewStore([]))
    }
}

#Preview("Saved, dark") {
    ThemeStore.shared.themeRaw = AppTheme.dark.rawValue
    return NavigationStack {
        SavedArticlesView(store: savedPreviewStore(SavedArticle.sample))
    }
    .preferredColorScheme(.dark)
}
