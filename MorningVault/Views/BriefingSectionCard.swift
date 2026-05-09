import SwiftUI

// MARK: - BriefingSectionCard

struct BriefingSectionCard: View {
    let section: BriefingSection
    var delay: Double = 0

    @State private var isExpanded = true
    @State private var hasAppeared = false

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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Text(section.content)
                        .font(.subheadline)
                        .foregroundStyle(Color.warmTextSecondary)
                        .lineSpacing(4)
                        .padding(.top, 8)
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
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.warmTextPrimary.opacity(0.06), radius: 8, x: 0, y: 4)
        .cardEntrance(delay: delay)
    }

    private var springAnimation: Animation {
        .spring(response: AppAnimation.springResponse, dampingFraction: AppAnimation.springDamping)
    }
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