import SwiftUI

// MARK: - BriefingSectionCard
//
// One block per briefing section (eyebrow + content, hairlines, no card background), laid
// out by section id: calendar (time column rows), markets (hairline rows with sparklines),
// headlines (numbered list), health (stat row). Weather is the sky scene and the calendar's
// upcoming events are the Next block in the Brief; this view is their fallback and the
// health / headlines sections. Anything that fails to parse falls back to the section text.

struct BriefingSectionCard: View {
    let section: BriefingSection
    var delay: Double = 0
    /// Optional: tap on the Markets card goes to the Markets tab.
    var onOpenMarkets: (() -> Void)? = nil

    /// Sparkline inputs per symbol for the markets rows (none = no sparkline).
    var marketSeries: [String: MarketSeries] = [:]

    @ObservedObject private var readState = NewsReadStateTracker.shared
    /// Snapshots of stories saved with "Save for later".
    @ObservedObject private var saved = SavedArticleStore.shared
    /// Household checklist behind the `today` section (previews pass a sample model).
    @ObservedObject private var checklist: ChecklistViewModel

    init(section: BriefingSection, delay: Double = 0, onOpenMarkets: (() -> Void)? = nil,
         marketSeries: [String: MarketSeries] = [:], checklist: ChecklistViewModel = .shared) {
        self.section = section
        self.delay = delay
        self.onOpenMarkets = onOpenMarkets
        self.marketSeries = marketSeries
        self.checklist = checklist
    }

    private var hasArticles: Bool {
        section.rssFeed != nil && !(section.rssFeed?.articles.isEmpty ?? true)
    }

    private var eyebrowTitle: String {
        switch section.id {
        case "calendar": return "Today"
        case "headlines": return "Headlines"
        default: return section.title
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Group {
                switch section.id {
                case "calendar": calendarBody
                case "markets": marketsBody
                case "headlines": headlinesBody
                case "health": healthBody
                case "today": TodaySectionView(model: checklist)
                default: plainBody
                }
            }

            if section.errorMessage != nil {
                permissionBanner
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardEntrance(delay: delay)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Eyebrow(text: eyebrowTitle)
            Spacer()
            if section.id == "today", checklist.hasLoaded {
                let progress = checklist.progressToday
                if progress.total > 0 {
                    Text("\(progress.done) of \(progress.total)")
                        .font(.metaText.monospacedDigit())
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            if section.id == "headlines", let feed = section.rssFeed {
                let unread = readState.unreadCount(in: [feed])
                if unread > 0 {
                    Text("\(unread) unread")
                        .font(.metaText)
                        .foregroundStyle(Color.inkSecondary)
                }
            }
        }
    }

    // MARK: Calendar

    @ViewBuilder
    private var calendarBody: some View {
        let events = CalendarLine.parse(section.content)
        if events.isEmpty {
            if section.errorMessage == nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nothing else today.")
                        .font(.bodyText)
                        .foregroundStyle(Color.inkPrimary)
                    Text(section.content.isEmpty ? "Nothing on the calendar. Good time for deep work." : section.content)
                        .font(.secondaryText)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                plainBody
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(event.time)
                            .font(.system(size: 13, weight: .medium).monospacedDigit())
                            .foregroundStyle(Color.inkSecondary)
                            .frame(width: 56, alignment: .leading)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(event.title)
                            .font(.system(size: 17, weight: index == 0 ? .semibold : .regular))
                            .foregroundStyle(Color.inkPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 11)
                    if index < events.count - 1 { Hairline() }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Markets

    @ViewBuilder
    private var marketsBody: some View {
        let lines = MarketLine.parse(section.content)
        if lines.isEmpty {
            plainBody
        } else {
            VStack(spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                    let series = marketSeries[line.symbol]
                    Button {
                        onOpenMarkets?()
                    } label: {
                        MarketRow(symbol: line.symbol, priceText: line.price, change: line.change,
                                  series: series?.points ?? [], prevClose: series?.prevClose, compact: true)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityHint(onOpenMarkets == nil ? "" : "Opens the Markets tab")
                    if index < lines.count - 1 { Hairline() }
                }
            }
        }
    }

    // MARK: Headlines

    @ViewBuilder
    private var headlinesBody: some View {
        if hasArticles, let feed = section.rssFeed {
            articleList(feed: feed)
                // Stories marked "Save for later" before the Saved list existed carry only an
                // id; pick up the ones still in the feed so they get a snapshot too.
                .task(id: feed.id) { saved.migrate(from: [feed], states: readState.states) }
        } else {
            let lines = section.content
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .map { $0.hasPrefix("•") ? String($0.dropFirst()).trimmingCharacters(in: .whitespaces) : $0 }
                .filter { !$0.isEmpty }
            if lines.count > 1 {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        numberedRow(index: index, isLast: index == lines.count - 1) {
                            Text(line)
                                .font(.bodyText)
                                .foregroundStyle(Color.inkPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } else {
                plainBody
            }
        }
    }

    private func numberedRow<Content: View>(index: Int, isLast: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(String(format: "%02d", index + 1))
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.inkSecondary)
                    .frame(width: 24, alignment: .leading)
                content()
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            if !isLast { Hairline() }
        }
    }

    private func articleList(feed: RSSFeedData) -> some View {
        let unread = readState.unreadCount(in: [feed])
        // The view model already cut the feed to the Headlines in brief setting.
        let articles = feed.articles
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(articles.enumerated()), id: \.element.id) { index, article in
                numberedRow(index: index, isLast: index == articles.count - 1) {
                    ArticleRowView(
                        article: article,
                        state: readState.state(for: article.id),
                        onRead:    { readState.markRead(article.id); saved.remove(id: article.id) },
                        // Saving keeps a snapshot, so the story survives the next refresh.
                        onLater:   { readState.markLater(article.id); saved.save(article, sourceName: feed.sourceName) },
                        onSkip:    { readState.markSkipped(article.id); saved.remove(id: article.id) },
                        onUnread:  { readState.markUnread(article.id); saved.remove(id: article.id) }
                    )
                }
            }

            // Anything saved before this list existed and still in the feed.
            SavedArticlesLink(store: saved)
                .padding(.top, 4)

            if unread > 0 {
                Button("Mark all read") {
                    for article in feed.articles {
                        readState.markRead(article.id)
                        saved.remove(id: article.id)
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.inkSecondary)
                .buttonStyle(.pressable)
                .padding(.top, 10)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 13, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                    Text("All caught up")
                }
                .font(.metaText)
                .foregroundStyle(Color.inkSecondary)
                .padding(.top, 10)
            }
        }
    }

    // MARK: Health

    @ViewBuilder
    private var healthBody: some View {
        let stats = HealthStat.parse(section.content)
        if stats.isEmpty {
            plainBody
        } else {
            // Two columns of stats, label over value, like the weather stats in the scene.
            let columns: [GridItem] = [GridItem(.flexible(), spacing: 12, alignment: .leading), GridItem(.flexible(), spacing: 12, alignment: .leading)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(stats) { stat in
                    VStack(alignment: .leading, spacing: 3) {
                        Eyebrow(text: stat.label)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(stat.value)
                                .font(.system(size: 22, weight: .medium).monospacedDigit())
                                .foregroundStyle(Color.inkPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            if let unit = stat.unit {
                                Text(unit)
                                    .font(.metaText)
                                    .foregroundStyle(Color.inkSecondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: Fallback

    private var plainBody: some View {
        Text(section.content)
            .font(.bodyText)
            .foregroundStyle(Color.inkPrimary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var permissionBanner: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.negativeColor)
            Text(section.errorMessage ?? "")
                .font(.metaText)
                .foregroundStyle(Color.inkPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text("Settings › Permissions")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.inkSecondary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Article Row View

struct ArticleRowView: View {
    let article: RSSArticle
    let state: NewsArticleState
    let onRead: () -> Void
    let onLater: () -> Void
    let onSkip: () -> Void
    let onUnread: () -> Void

    @State private var showingActions = false
    /// Article open in the in-app reader (SFSafariViewController sheet); nil when closed.
    @State private var reader: ReaderLink? = nil

    private struct ReaderLink: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    private var stateIcon: String {
        switch state {
        case .unread: return "circle"
        case .read:   return "checkmark.circle.fill"
        case .later:  return "bookmark.fill"
        case .skipped: return "forward.fill"
        }
    }

    private var stateColor: Color {
        switch state {
        case .unread:  return Color.inkSecondary
        case .read:    return Color.warmPositive
        case .later:   return Color.warmPrimaryAccent
        case .skipped: return Color.inkSecondary.opacity(0.6)
        }
    }

    private var stateLabel: String {
        switch state {
        case .unread:  return ""
        case .read:    return "Read"
        case .later:   return "Saved"
        case .skipped: return "Skipped"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // State icon button
            Button {
                cycleState()
            } label: {
                Image(systemName: stateIcon)
                    .font(.body)
                    .foregroundStyle(stateColor)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(state == .unread ? "Mark as read" : "Change status: \(stateLabel)")

            // Article content: tapping the title area opens the story in the reader.
            VStack(alignment: .leading, spacing: 3) {
                Text(article.title)
                    .font(.body)
                    .fontWeight(state == .unread ? .medium : .regular)
                    .foregroundStyle(state == .skipped ? Color.inkSecondary : Color.inkPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(state == .unread ? 3 : 2)
                    .strikethrough(state == .skipped)

                if let summary = article.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(2)
                }

                // State label + actions (shown when not unread)
                if state != .unread {
                    HStack(spacing: 12) {
                        Text(stateLabel)
                            .font(.caption2)
                            .foregroundStyle(stateColor)

                        if state == .read || state == .skipped {
                            Button("Undo") {
                                onUnread()
                            }
                            .font(.caption2)
                            .foregroundStyle(Color.inkSecondary)
                        }

                        if state == .later {
                            Button("Open") {
                                openArticle()
                            }
                            .font(.caption2)
                            .foregroundStyle(Color.inkSecondary)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { openArticle() }
            .accessibilityAddTraits(canOpen ? .isButton : [])
            .accessibilityHint(canOpen ? "Opens the article" : "")

            Spacer(minLength: 0)

            // Expand to show quick actions
            if state == .unread {
                Menu {
                    Button {
                        onRead()
                    } label: {
                        Label("Mark as read", systemImage: "checkmark")
                    }
                    Button {
                        onLater()
                    } label: {
                        Label("Save for later", systemImage: "bookmark")
                    }

                    Button {
                        onSkip()
                    } label: {
                        Label("Skip", systemImage: "forward")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption)
                        .foregroundStyle(Color.inkSecondary)
                        .padding(.leading, 4)
                        .frame(minWidth: 28, minHeight: 28)
                }
                .accessibilityLabel("Article actions")
            }
        }
        .sheet(item: $reader) { link in
            SafariView(url: link.url)
                .ignoresSafeArea()
        }
    }

    private var canOpen: Bool { SafariView.isOpenable(article.url) }

    private func cycleState() {
        switch state {
        case .unread:  onRead()
        case .read:    onLater()
        case .later:   onUnread()
        case .skipped: onUnread()
        }
    }

    /// Opens the story in the in-app reader. An empty or non-web URL does nothing.
    /// Opening an unread story also marks it read, the same as the old tap did.
    private func openArticle() {
        guard let url = SafariView.openableURL(from: article.url) else { return }
        if state == .unread { onRead() }
        reader = ReaderLink(url: url)
    }

}

// MARK: - Notification Names

extension Notification.Name {
    /// Settings > Data sources > Headlines in brief changed; the Brief reloads its headlines.
    static let headlineCountChanged = Notification.Name("headlineCountChanged")
}


// MARK: - Empty State View

/// Flat block (no card): names the actual cause (source off, permission, nothing loaded) and nothing else.
struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.appAccentColor)
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.inkPrimary)
            Text(message)
                .font(.secondaryText)
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Loading State View

/// Three block-shaped skeletons with a shimmer, in place of a spinner (no card frames).
struct LoadingStateView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(0..<3, id: \.self) { index in
                VStack(alignment: .leading, spacing: 12) {
                    SkeletonLine(width: 72, height: 10)
                    SkeletonLine(width: index == 0 ? 140 : nil, height: index == 0 ? 26 : 14)
                    SkeletonLine(height: 14)
                    SkeletonLine(width: 180, height: 14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityLabel("Loading your briefing")
    }
}

// MARK: - Preview

#Preview("Sections") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    return ScrollView {
        VStack(spacing: 28) {
            BriefingSectionCard(section: BriefingSection(
                id: "calendar", title: "Calendar", icon: "📅",
                content: "9:00 AM — Standup\n11:30 AM — Design review with Priya\n3:00 PM — Dentist",
                sentiment: nil))
            BriefingSectionCard(section: BriefingSection(
                id: "markets", title: "Markets", icon: "📈",
                content: "SPY: $735.29 ↓2.70%\nBTC: $75,699 ↑1.12%",
                sentiment: "bearish"),
                marketSeries: ["SPY": MarketSeries(prevClose: 755.0, points: MarketPreviewData.spy),
                               "BTC": MarketSeries(prevClose: 74_860, points: MarketPreviewData.btc)])
            BriefingSectionCard(section: BriefingSection(
                id: "health", title: "Health", icon: "❤️‍🔥",
                content: "Last night: 7h 12m asleep (of 7h 50m in bed). Today: 8432 steps. HRV: 45ms. Resting HR: 58 bpm. ",
                sentiment: nil))
            BriefingSectionCard(section: BriefingSection(
                id: "headlines", title: "Headlines", icon: "📰",
                content: "• Fed holds rates steady as inflation cools\n• Apple previews on-device models for iOS 27\n• Storm system to bring rain to Southern California",
                sentiment: nil))
            EmptyStateView(
                title: "Allow Calendar access",
                message: "Your day's events show here once MorningVault can read your calendar.",
                systemImage: "calendar.badge.exclamationmark")
            LoadingStateView()
        }
        .padding(20)
    }
    .background(Color.backgroundColor)
}

#Preview("Headlines, empty, loading") {
    ThemeStore.shared.themeRaw = AppTheme.dark.rawValue
    return ScrollView {
        VStack(spacing: 28) {
            BriefingSectionCard(section: BriefingSection(
                id: "headlines", title: "Headlines", icon: "📰",
                content: "• Fed holds rates steady as inflation cools\n• Apple previews on-device models for iOS 27\n• Storm system to bring rain to Southern California",
                sentiment: nil))
            BriefingSectionCard(section: BriefingSection(
                id: "calendar", title: "Calendar", icon: "📅",
                content: "No events scheduled. Your calendar is clear for today.",
                sentiment: nil))
            EmptyStateView(
                title: "Allow Calendar access",
                message: "Your day's events show here once MorningVault can read your calendar.",
                systemImage: "calendar.badge.exclamationmark")
            LoadingStateView()
        }
        .padding(20)
    }
    .background(Color.backgroundColor)
    .preferredColorScheme(.dark)
}
