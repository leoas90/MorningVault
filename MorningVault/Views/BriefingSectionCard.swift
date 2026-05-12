import SwiftUI

// MARK: - BriefingSectionCard

struct BriefingSectionCard: View {
    let section: BriefingSection
    var delay: Double = 0

    @State private var isExpanded = true
    @State private var hasAppeared = false
    @StateObject private var readState = NewsReadStateTracker.shared

    private var sectionColor: Color {
        switch section.title.lowercased() {
        case _ where section.title.lowercased().contains("health"):
            return Color.warmPrimaryAccent
        case _ where section.title.lowercased().contains("weather"):
            return Color.warmSecondaryAccent
        case _ where section.title.lowercased().contains("market"):
            return Color.warmPositive
        default:
            return Color.warmPrimaryAccent
        }
    }

    private var sectionIcon: String {
        let iconMap = [
            "🌤️": "cloud.sun",
            "💪": "heart.fill",
            "📅": "calendar",
            "📰": "newspaper",
            "📈": "chart.line.uptrend.xyaxis",
            "🔔": "bell",
            "⏰": "clock"
        ]
        return iconMap[section.icon] ?? "square.grid.2x2"
    }

    private var hasArticles: Bool {
        section.rssFeed != nil && !(section.rssFeed?.articles.isEmpty ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerButton

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    // Article list for headlines section
                    if hasArticles, let feed = section.rssFeed {
                        articleListView(feed: feed)
                    }

                    // Section content text
                    if !hasArticles {
                        Text(section.content)
                            .font(.subheadline)
                            .foregroundStyle(Color.warmTextSecondary)
                            .lineSpacing(4)
                            .padding(.top, 8)
                    }

                    // Permission denied banner
                    if section.errorMessage != nil {
                        permissionBanner
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity.combined(with: .move(edge: .top))
                ))
            }
        }
        .padding(20)
        .background(Color.warmSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
        .shadow(color: Color.warmTextPrimary.opacity(0.06), radius: 8, x: 0, y: 4)
        .cardEntrance(delay: delay)
    }

    private var headerButton: some View {
        Button {
            withAnimation(springAnimation) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                SectionIcon(
                    systemName: sectionIcon,
                    color: sectionColor,
                    delay: delay
                )

                Text(section.title)
                    .font(.headline)
                    .foregroundStyle(Color.warmTextPrimary)

                Spacer()

                if let sentiment = section.sentiment {
                    AnimatedSentimentBadge(sentiment: sentiment)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.warmPrimaryAccent.opacity(0.5))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(springAnimation, value: isExpanded)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var permissionBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Color.warmNegative)
            Text(section.errorMessage ?? "")
                .font(.caption)
                .foregroundStyle(Color.warmNegative)
            Spacer()
            Text("Enable in Settings")
                .font(.caption2)
                .foregroundStyle(Color.warmTextSecondary)
        }
        .padding(10)
        .background(Color.warmNegative.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.banner))
    }

    private func articleListView(feed: RSSFeedData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Inbox Zero: unread count + reset button
            let unread = readState.unreadCount(in: [feed])
            if unread > 0 {
                HStack {
                    Text("\(unread) unread")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.warmPrimaryAccent)
                    Spacer()
                    Button("Mark all read") {
                        for article in feed.articles {
                            readState.markRead(article.id)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }

            ForEach(feed.articles.prefix(10)) { article in
                ArticleRowView(
                    article: article,
                    state: readState.state(for: article.id),
                    onRead:    { readState.markRead(article.id) },
                    onLater:   { readState.markLater(article.id) },
                    onSkip:    { readState.markSkipped(article.id) },
                    onUnread:  { readState.markUnread(article.id) }
                )
            }

            // "Inbox Zero" empty state
            if unread == 0 {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark.circle")
                            .font(.title2)
                            .foregroundStyle(Color.warmPositive)
                        Text("Inbox Zero!")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.warmTextPrimary)
                        Text("All caught up")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 16)
                    Spacer()
                }
            }
        }
        .padding(.top, 4)
    }

    private var springAnimation: Animation {
        .spring(response: AppAnimation.springResponse, dampingFraction: AppAnimation.springDamping)
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
        case .unread:  return .secondary
        case .read:    return Color.warmPositive
        case .later:   return Color.warmPrimaryAccent
        case .skipped: return .secondary.opacity(0.5)
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
                    .font(.system(size: 16))
                    .foregroundStyle(stateColor)
                    .frame(width: 24)
            }
            .buttonStyle(.plain)

            // Article content
            VStack(alignment: .leading, spacing: 3) {
                Text(article.title)
                    .font(.subheadline)
                    .fontWeight(state == .unread ? .medium : .regular)
                    .foregroundStyle(state == .skipped ? .secondary : Color.warmTextPrimary)
                    .lineLimit(state == .unread ? 3 : 2)
                    .strikethrough(state == .skipped)

                if let summary = article.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                            .foregroundStyle(.secondary)
                        }

                        if state == .later {
                            Button("Open") {
                                openArticle()
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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
                        Label("Mark as Read", systemImage: "checkmark")
                    }
                    Button {
                        onLater()
                    } label: {
                        Label("Save for Later", systemImage: "bookmark")
                    }

                    Button {
                        onSkip()
                    } label: {
                        Label("Skip", systemImage: "forward")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(state == .unread ? Color.warmPrimaryAccent.opacity(0.04) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String

    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(Color.warmPrimaryAccent.opacity(0.5))
                .scaleEffect(hasAppeared ? 1 : 0.8)
                .opacity(hasAppeared ? 1 : 0)

            Text(title)
                .font(.headline)
                .foregroundStyle(Color.warmTextPrimary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.warmTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .onAppear {
            if !UIAccessibility.isReduceMotionEnabled {
                withAnimation(.easeOut(duration: 0.4)) {
                    hasAppeared = true
                }
            } else {
                hasAppeared = true
            }
        }
    }
}

// MARK: - Loading State View

struct LoadingStateView: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.warmPrimaryAccent.opacity(0.2), lineWidth: 4)
                    .frame(width: 40, height: 40)

                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color.warmPrimaryAccent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 40, height: 40)
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
            }

            Text("Generating briefing...")
                .font(.subheadline)
                .foregroundStyle(Color.warmTextSecondary)
        }
        .padding()
        .onAppear {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        BriefingSectionCard(
            section: BriefingSection(
                id: "1",
                title: "Weather",
                icon: "🌤️",
                content: "Partly cloudy with a high of 72°F. Perfect weather for a morning walk.",
                sentiment: "positive"
            )
        )
        .padding(.horizontal)

        EmptyStateView(
            title: "Set Your Alarm",
            message: "Configure your briefing time in Settings to get started.",
            systemImage: "alarm"
        )
        .padding(.horizontal)

        LoadingStateView()
    }
}