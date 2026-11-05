import SwiftUI

// MARK: - Warm Mode Colors

// MARK: - Color Extension for Hex

// MARK: - Design System Tokens

/// Consistent corner radii used throughout the app.
/// Update here to propagate a radius change everywhere.
enum AppRadius {
    static let card: CGFloat = 20
    static let button: CGFloat = 14
    static let banner: CGFloat = 8
    static let badge: CGFloat = 6
}

extension Color {
    init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var hexValue: UInt64 = 0
        Scanner(string: trimmed).scanHexInt64(&hexValue)
        let red = Double((hexValue >> 16) & 0xFF) / 255.0
        let green = Double((hexValue >> 8) & 0xFF) / 255.0
        let blue = Double(hexValue & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }

    @MainActor static var warmBackground: Color { Color.backgroundColor }
    @MainActor static var warmSurface: Color { Color.surfaceColor }
    @MainActor static var warmCardBackground: Color { Color.surfaceColor }
    @MainActor static var warmPrimaryAccent: Color { Color.appAccentColor }
    @MainActor static var warmSecondaryAccent: Color { Color.positiveColor }
    @MainActor static var warmTextPrimary: Color { Color(UIColor.dynamic(light: .black, dark: .white)) }
    @MainActor static var warmTextSecondary: Color { Color(UIColor.dynamic(light: UIColor(white: 0.4, alpha: 1), dark: UIColor(white: 0.7, alpha: 1))) }
    @MainActor static var warmDivider: Color { Color(UIColor.dynamic(light: UIColor(white: 0.9, alpha: 1), dark: UIColor(white: 0.2, alpha: 1))) }
    @MainActor static var warmPositive: Color { Color.positiveColor }
    @MainActor static var warmNegative: Color { Color.negativeColor }
    @MainActor static var warmAISummary: Color { Color.aiSummaryBadgeColor }
    @MainActor static var warmLocalBadge: Color { Color.positiveColor }
    @MainActor static var warmExternalBadge: Color { Color.aiSummaryBadgeColor }
}

// MARK: - NumberText View (Animated value changes)

struct NumberText: View {
    let value: Double
    let format: String
    let trend: Trend

    enum Trend {
        case up, down, neutral
    }

    @State private var displayedValue: Double = 0
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 4) {
            trendIcon
            valueText
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(animationBackground)
        .onAppear {
            displayedValue = value
        }
        .onChange(of: value) { oldValue, newValue in
            animateValue(from: oldValue, to: newValue)
        }
    }

    @ViewBuilder
    private var trendIcon: some View {
        if trend != .neutral {
            Image(systemName: trend == .up ? "arrow.up.right" : "arrow.down.right")
                .font(.caption2)
                .foregroundStyle(trend == .up ? Color.warmPositive : Color.warmNegative)
        }
    }

    private var valueText: Text {
        Text(String(format: format, displayedValue))
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(Color.warmTextPrimary)
    }

    private var animationBackground: some ShapeStyle {
        if isAnimating {
            return trend == .up ? Color.warmPositive.opacity(0.15) : Color.warmNegative.opacity(0.15)
        } else {
            return Color.clear
        }
    }

    private func animateValue(from: Double, to: Double) {
        guard !UIAccessibility.isReduceMotionEnabled else {
            displayedValue = to
            return
        }

        isAnimating = true
        let steps = 10
        let duration = AppAnimation.tickAnimationDuration * Double(steps)
        let delta = (to - from) / Double(steps)

        for i in 0..<steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration * Double(i) / Double(steps)) {
                withAnimation(.linear(duration: duration / Double(steps))) {
                    displayedValue = from + delta * Double(i + 1)
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            isAnimating = false
        }
    }
}

// MARK: - SparklineView (Animated draw-on)

struct SparklineView: View {
    let dataPoints: [Double]
    let color: Color
    let showGradient: Bool

    @State private var drawProgress: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let path = createSparklinePath(in: geometry.size)

            ZStack {
                // Gradient fill
                if showGradient {
                    path.fill(
                        LinearGradient(
                            colors: [color.opacity(0.3), color.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .mask(
                        Rectangle()
                            .frame(width: geometry.size.width * drawProgress)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    )
                }

                // Line
                path
                    .trim(from: 0, to: drawProgress)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .onAppear {
            if !UIAccessibility.isReduceMotionEnabled {
                withAnimation(.easeInOut(duration: AppAnimation.sparklineDrawDuration)) {
                    drawProgress = 1
                }
            } else {
                drawProgress = 1
            }
        }
    }

    private func createSparklinePath(in size: CGSize) -> Path {
        guard dataPoints.count > 1 else {
            return Path()
        }

        let minVal = dataPoints.min() ?? 0
        let maxVal = dataPoints.max() ?? 1
        let range = maxVal - minVal
        let normalizedRange = range > 0 ? range : 1

        let stepX = size.width / CGFloat(dataPoints.count - 1)
        let scaleY = size.height / normalizedRange

        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height - (dataPoints[0] - minVal) * scaleY))

        for i in 1..<dataPoints.count {
            let x = CGFloat(i) * stepX
            let y = size.height - (dataPoints[i] - minVal) * scaleY
            path.addLine(to: CGPoint(x: x, y: y))
        }

        // Close path for gradient fill
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()

        return path
    }
}

// MARK: - BounceLabel (Badge with bounce-in animation)

struct BounceLabel: View {
    let text: String
    let color: Color
    let icon: String?

    @State private var hasAppeared = false

    init(text: String, color: Color, icon: String? = nil) {
        self.text = text
        self.color = color
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 3) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.caption2)
            }
            Text(text)
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
        .scaleEffect(hasAppeared ? 1 : 0)
        .onAppear {
            if !UIAccessibility.isReduceMotionEnabled {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    hasAppeared = true
                }
            } else {
                hasAppeared = true
            }
        }
    }
}

// MARK: - SectionIcon (SF Symbol with bounce on appear)

struct SectionIcon: View {
    let systemName: String
    let color: Color
    let delay: Double

    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.12))
                .frame(width: 36, height: 36)

            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color)
        }
        .scaleEffect(hasAppeared ? 1 : 0.8)
        .opacity(hasAppeared ? 1 : 0)
        .onAppear {
            if !UIAccessibility.isReduceMotionEnabled {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        hasAppeared = true
                    }
                }
            } else {
                hasAppeared = true
            }
        }
    }
}

// MARK: - AnimatedCard (Base card with entrance animation)

struct AnimatedCard<Content: View>: View {
    let delay: Double
    let content: () -> Content

    @State private var hasAppeared = false

    init(delay: Double = 0, @ViewBuilder content: @escaping () -> Content) {
        self.delay = delay
        self.content = content
    }

    var body: some View {
        content()
            .padding(20)
            .background(Color.warmSurface)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: Color.warmTextPrimary.opacity(0.06), radius: 8, x: 0, y: 4)
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 20)
            .onAppear {
                if !UIAccessibility.isReduceMotionEnabled {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        withAnimation(.easeOut(duration: AppAnimation.cardEntranceDuration)) {
                            hasAppeared = true
                        }
                    }
                } else {
                    hasAppeared = true
                }
            }
    }
}

// MARK: - SentimentBadge (Bounce-in sentiment indicator)

struct AnimatedSentimentBadge: View {
    let sentiment: String

    @State private var hasAppeared = false

    private var color: Color {
        switch sentiment.lowercased() {
        case "bullish", "positive": return Color.warmPositive
        case "bearish", "negative": return Color.warmNegative
        case "neutral": return Color.warmTextSecondary
        default: return Color.warmPrimaryAccent
        }
    }

    private var icon: String {
        switch sentiment.lowercased() {
        case "bullish", "positive": return "arrow.up.right"
        case "bearish", "negative": return "arrow.down.right"
        case "neutral": return "arrow.right"
        default: return "arrow.right"
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
            Text(sentiment.capitalized)
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
        .scaleEffect(hasAppeared ? 1 : 0)
        .onAppear {
            if !UIAccessibility.isReduceMotionEnabled {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                    hasAppeared = true
                }
            } else {
                hasAppeared = true
            }
        }
    }
}
