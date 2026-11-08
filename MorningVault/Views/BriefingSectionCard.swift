import SwiftUI

// MARK: - BriefingSectionCard
//
// One card per briefing section, laid out by section id: weather (big numeral), calendar
// (timeline), markets (rows with change pills), headlines (numbered list), health (stat
// tiles). Anything that fails to parse falls back to the section text.

struct BriefingSectionCard: View {
    let section: BriefingSection
    var delay: Double = 0
    /// Optional: tap on the Markets card goes to the Markets tab.
    var onOpenMarkets: (() -> Void)? = nil

    @ObservedObject private var readState = NewsReadStateTracker.shared

    init(section: BriefingSection, delay: Double = 0, onOpenMarkets: (() -> Void)? = nil) {
        self.section = section
        self.delay = delay
        self.onOpenMarkets = onOpenMarkets
    }

    private var hasArticles: Bool {
        section.rssFeed != nil && !(section.rssFeed?.articles.isEmpty ?? true)
    }

    private var eyebrowTitle: String {
        switch section.id {
        case "calendar": return "Today"
        default: return section.title
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Group {
                switch section.id {
                case "weather": weatherBody
                case "calendar": calendarBody
                case "markets": marketsBody
                case "headlines": headlinesBody
                case "health": healthBody
                default: plainBody
                }
            }

            if section.errorMessage != nil {
                permissionBanner
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .editorialCard()
        .cardEntrance(delay: delay)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            Eyebrow(text: eyebrowTitle)
            Spacer()
            if section.id == "headlines", let feed = section.rssFeed {
                let unread = readState.unreadCount(in: [feed])
                if unread > 0 {
                    Text("\(unread) unread")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.appAccentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.appAccentColor.opacity(0.12), in: Capsule())
                }
            } else if let sentiment = section.sentiment, section.id != "weather" {
                SentimentPill(sentiment: sentiment)
            }
        }
    }

    // MARK: Weather

    @ViewBuilder
    private var weatherBody: some View {
        if let w = WeatherSummary.parse(section.content) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    Text(w.temperature)
                        .font(.display(56, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.inkPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .accessibilityLabel("\(w.temperature) \(w.unit)")

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 4) {
                        Image(systemName: WeatherSummary.symbol(for: w.condition))
                            .font(.system(size: 28, weight: .regular))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.appAccentColor)
                        Text(w.condition)
                            .font(.headline)
                            .foregroundStyle(Color.inkPrimary)
                            .multilineTextAlignment(.trailing)
                        Text(w.location)
                            .font(.subheadline)
                            .foregroundStyle(Color.inkSecondary)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.top, 6)
                }

                Hairline()

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 0) {
                        weatherStat("Feels like", w.feelsLike)
                        weatherStat("Humidity", w.humidity)
                        weatherStat("Wind", w.wind)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        weatherStat("Feels like", w.feelsLike)
                        weatherStat("Humidity", w.humidity)
                        weatherStat("Wind", w.wind)
                    }
                }

                if let note = w.note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            plainBody
        }
    }

    private func weatherStat(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.inkSecondary)
            Text(value ?? "—")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.inkPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Calendar

    @ViewBuilder
    private var calendarBody: some View {
        let events = CalendarLine.parse(section.content)
        if events.isEmpty {
            if section.errorMessage == nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Clear day")
                        .font(.display(22))
                        .foregroundStyle(Color.inkPrimary)
                    Text(section.content.isEmpty ? "Nothing on the calendar. Good time for deep work." : section.content)
                        .font(.subheadline)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                plainBody
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    HStack(alignment: .top, spacing: 12) {
                        Text(event.time)
                            .font(.subheadline.weight(.medium).monospacedDigit())
                            .foregroundStyle(Color.inkSecondary)
                            .frame(width: 72, alignment: .trailing)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        ZStack(alignment: .top) {
                            Rectangle()
                                .fill(Color.inkPrimary.opacity(0.14))
                                .frame(width: 1)
                                .padding(.top, index == 0 ? 8 : 0)
                                .padding(.bottom, index == events.count - 1 ? 12 : 0)
                            Circle()
                                .fill(index == 0 ? Color.appAccentColor : Color.inkSecondary)
                                .frame(width: 8, height: 8)
                                .padding(.top, 5)
                        }
                        .frame(width: 8)

                        Text(event.title)
                            .font(index == 0 ? .body.weight(.semibold) : .body)
                            .foregroundStyle(Color.inkPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, index == events.count - 1 ? 0 : 14)

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 2)
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
                    HStack(spacing: 12) {
                        Text(line.symbol)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.inkPrimary)
                            .frame(minWidth: 52, alignment: .leading)
                        Spacer(minLength: 0)
                        Text(line.price)
                            .font(.body.weight(.medium).monospacedDigit())
                            .foregroundStyle(Color.inkPrimary)
                        ChangePill(change: line.change)
                            .frame(minWidth: 76, alignment: .trailing)
                    }
                    .padding(.vertical, 10)
                    if index < lines.count - 1 { Hairline() }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onOpenMarkets?() }
            .accessibilityHint(onOpenMarkets == nil ? "" : "Opens the Markets tab")
        }
    }

    // MARK: Headlines

    @ViewBuilder
    private var headlinesBody: some View {
        if hasArticles, let feed = section.rssFeed {
            articleList(feed: feed)
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
                                .font(.body)
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
                    .font(.display(15, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.appAccentColor)
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
        let articles = Array(feed.articles.prefix(10))
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(articles.enumerated()), id: \.element.id) { index, article in
                numberedRow(index: index, isLast: index == articles.count - 1) {
                    ArticleRowView(
                        article: article,
                        state: readState.state(for: article.id),
                        onRead:    { readState.markRead(article.id) },
                        onLater:   { readState.markLater(article.id) },
                        onSkip:    { readState.markSkipped(article.id) },
                        onUnread:  { readState.markUnread(article.id) }
                    )
                }
            }

            if unread > 0 {
                Button("Mark all read") {
                    for article in feed.articles {
                        readState.markRead(article.id)
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.inkSecondary)
                .padding(.top, 10)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(Color.positiveColor)
                    Text("All caught up")
                        .foregroundStyle(Color.inkSecondary)
                }
                .font(.caption)
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
            let columns: [GridItem] = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(stats) { stat in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stat.label)
                            .font(.caption)
                            .foregroundStyle(Color.inkSecondary)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(stat.value)
                                .font(.display(24, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(Color.inkPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            if let unit = stat.unit {
                                Text(unit)
                                    .font(.caption)
                                    .foregroundStyle(Color.inkSecondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.inkPrimary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    // MARK: Fallback

    private var plainBody: some View {
        Text(section.content)
            .font(.body)
            .foregroundStyle(Color.inkPrimary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var permissionBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Color.negativeColor)
            Text(section.errorMessage ?? "")
                .font(.caption)
                .foregroundStyle(Color.inkPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text("Settings › Permissions")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.inkSecondary)
        }
        .padding(10)
        .background(Color.negativeColor.opacity(0.08), in: RoundedRectangle(cornerRadius: AppRadius.banner, style: .continuous))
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

            // Article content
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
        .contentShape(Rectangle())
        .onTapGesture {
            if state == .unread {
                onRead()
            } else {
                openArticle()
            }
        }
    }

    private func cycleState() {
        switch state {
        case .unread:  onRead()
        case .read:    onLater()
        case .later:   onUnread()
        case .skipped: onUnread()
        }
    }

    private func openArticle() {
        guard let url = URL(string: article.url), article.url.hasPrefix("http") else { return }
        // Opening URLs would require UIApplication.shared — handled by parent view controller
        NotificationCenter.default.post(
            name: .openArticleURL,
            object: nil,
            userInfo: ["url": url]
        )
    }

}

// MARK: - Notification Names

extension Notification.Name {
    static let openArticleURL = Notification.Name("openArticleURL")
}


// MARK: - Empty State View

/// Quiet card: names the actual cause (source off, permission, nothing loaded) and nothing else.
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
                .font(.display(22))
                .foregroundStyle(Color.inkPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .editorialCard()
    }
}

// MARK: - Loading State View

/// Three card-shaped skeletons with a shimmer, in place of a spinner.
struct LoadingStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { index in
                VStack(alignment: .leading, spacing: 12) {
                    SkeletonLine(width: 72, height: 10)
                    SkeletonLine(width: index == 0 ? 140 : nil, height: index == 0 ? 32 : 14)
                    SkeletonLine(height: 14)
                    SkeletonLine(width: 180, height: 14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .editorialCard()
            }
        }
        .accessibilityLabel("Loading your briefing")
    }
}

// MARK: - Preview

#Preview("Cards") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    return ScrollView {
        VStack(spacing: 16) {
            BriefingSectionCard(section: BriefingSection(
                id: "weather", title: "Weather", icon: "🌤️",
                content: "64°F (Partly Cloudy) in Murrieta. Feels like 62°F. Humidity 40%. Wind 8 mph W.",
                sentiment: "positive"))
            BriefingSectionCard(section: BriefingSection(
                id: "calendar", title: "Calendar", icon: "📅",
                content: "9:00 AM — Standup\n11:30 AM — Design review with Priya\n3:00 PM — Dentist",
                sentiment: nil))
            BriefingSectionCard(section: BriefingSection(
                id: "markets", title: "Markets", icon: "📈",
                content: "SPY: $735.29 ↓2.70%\nBTC: $75,699 ↑1.12%",
                sentiment: "bearish"))
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
        VStack(spacing: 16) {
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
