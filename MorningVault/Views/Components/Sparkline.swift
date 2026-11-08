import SwiftUI

// MARK: - Sparkline

/// Line + 12 % area from a real series, drawn in a `Canvas` (round caps and joins, a dotted
/// 1 pt previous-close reference). App rows: 104×40 at 2 pt; the Brief: 84×28 at 1.5 pt.
/// Draws left-to-right over 500 ms on appear; complete at once under Reduce Motion. Never
/// shown without data: callers pass `nil` for no series.
struct Sparkline: View {
    let points: [Double]
    var prevClose: Double? = nil
    var color: Color
    var lineWidth: CGFloat = 2
    /// False for offscreen renders (share card): the line is complete immediately.
    var animated: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 1
    @State private var didAnimate = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let shown: CGFloat = animated ? progress : 1
            let reference = Color.inkSecondary.opacity(0.85)
            Canvas { context, _ in
                let line = linePath(in: size)
                var clip = Path()
                clip.addRect(CGRect(x: 0, y: 0, width: size.width * shown, height: size.height))
                context.clip(to: clip)
                context.fill(areaPath(in: size),
                             with: .linearGradient(Gradient(colors: [color.opacity(0.12), color.opacity(0.0)]),
                                                   startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                if let y = prevCloseY(in: size) {
                    var dotted = Path()
                    dotted.move(to: CGPoint(x: 0, y: y))
                    dotted.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(dotted, with: .color(reference), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [1, 3]))
                }
                context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                // Endpoint marker: the latest value.
                if shown >= 1, let last = line.currentPoint {
                    let r = lineWidth * 1.6
                    context.fill(Path(ellipseIn: CGRect(x: last.x - r, y: last.y - r, width: r * 2, height: r * 2)), with: .color(color))
                }
            }
        }
        .onAppear {
            // Static preview renders snapshot before `onAppear`, so the line starts complete
            // and the draw-on only runs in the app: reset to 0, then animate to 1 next tick.
            guard animated, !reduceMotion, !Self.isPreviewRender, !didAnimate else { return }
            didAnimate = true
            progress = 0
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.5)) { progress = 1 }
            }
        }
        .accessibilityHidden(true)
    }

    /// Static preview renders capture before the draw-on animation finishes.
    private static let isPreviewRender = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

    private var bounds: (min: Double, max: Double)? {
        guard points.count > 1, let lo = points.min(), let hi = points.max() else { return nil }
        // Include prevClose in the scale only when it is within ~ the series range already;
        // the dotted line is a reference, not a reason to flatten the curve.
        return (lo, hi == lo ? lo + 1 : hi)
    }

    private func y(for value: Double, in size: CGSize, bounds b: (min: Double, max: Double)) -> CGFloat {
        let inset: CGFloat = lineWidth * 2
        let t = (value - b.min) / (b.max - b.min)
        return size.height - inset - CGFloat(t) * (size.height - inset * 2)
    }

    private func linePath(in size: CGSize) -> Path {
        var path = Path()
        guard let b = bounds else { return path }
        let edge = lineWidth * 1.6
        let step = (size.width - edge * 2) / CGFloat(points.count - 1)
        for (i, v) in points.enumerated() {
            let p = CGPoint(x: edge + CGFloat(i) * step, y: y(for: v, in: size, bounds: b))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }

    private func areaPath(in size: CGSize) -> Path {
        var path = linePath(in: size)
        guard !path.isEmpty, let last = path.currentPoint else { return path }
        let edge = lineWidth * 1.6
        path.addLine(to: CGPoint(x: last.x, y: size.height))
        path.addLine(to: CGPoint(x: edge, y: size.height))
        path.closeSubpath()
        return path
    }

    private func prevCloseY(in size: CGSize) -> CGFloat? {
        guard let prevClose, let b = bounds, prevClose >= b.min, prevClose <= b.max else { return nil }
        return y(for: prevClose, in: size, bounds: b)
    }
}

// MARK: - Market row

/// Hairline-list row: symbol label over a tabular quote, signed delta with ▲/▼ and a
/// percentage, sparkline right. `compact` is the Brief (24 pt quote, 84×28 line at 1.5 pt);
/// the Markets tab uses 30/34 and a 104×40 line at 2 pt in a ~104 pt row.
struct MarketRow: View {
    let symbol: String
    let priceText: String
    let change: Double
    var series: [Double] = []
    var prevClose: Double? = nil
    var compact: Bool = true
    /// Optional line under the delta (entry price on the Markets tab) and its coloured P&L.
    var footnote: String? = nil
    var footnoteDetail: String? = nil
    var footnoteDetailColor: Color? = nil

    private var semantic: Color {
        if change > 0 { return Color.positiveColor }
        if change < 0 { return Color.negativeColor }
        return Color.inkSecondary
    }

    private var deltaText: String {
        let arrow = change > 0 ? "▲" : (change < 0 ? "▼" : "")
        return "\(arrow) \(String(format: "%.2f", abs(change)))%".trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                Eyebrow(text: symbol)
                Text(priceText)
                    .font(compact ? .system(size: 24, weight: .medium).monospacedDigit() : .marketQuote)
                    .foregroundStyle(Color.inkPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                Text(deltaText)
                    .font(.delta)
                    .foregroundStyle(semantic)
            }
            Spacer(minLength: 8)
            if series.count > 1 {
                Sparkline(points: series, prevClose: prevClose, color: semantic, lineWidth: compact ? 1.5 : 2)
                    .frame(width: compact ? 84 : 104, height: compact ? 28 : 40)
            }
        }
        .padding(.top, compact ? 12 : 16)
        .padding(.bottom, footnote == nil ? (compact ? 12 : 16) : 6)
        if let footnote {
            HStack(spacing: 6) {
                Text(footnote)
                    .foregroundStyle(Color.inkSecondary)
                if let footnoteDetail {
                    Text(footnoteDetail)
                        .fontWeight(.semibold)
                        .foregroundStyle(footnoteDetailColor ?? Color.inkSecondary)
                }
            }
            .font(.system(size: 13, weight: .medium).monospacedDigit())
            .lineLimit(1)
            .padding(.bottom, compact ? 12 : 12)
        }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(symbol) \(priceText), \(change >= 0 ? "up" : "down") \(String(format: "%.2f", abs(change))) percent\(footnote.map { ". \($0) \(footnoteDetail ?? "")" } ?? "")")
    }
}

#Preview("Rows") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    return VStack(spacing: 0) {
        MarketRow(symbol: "SPY", priceText: "$735.29", change: -2.70, series: MarketPreviewData.spy, prevClose: 755.0, compact: false)
        Hairline()
        MarketRow(symbol: "BTC", priceText: "$75,699", change: 1.12, series: MarketPreviewData.btc, prevClose: 74_860, compact: false)
        Hairline()
        MarketRow(symbol: "AAPL", priceText: "$231.10", change: 0.00, compact: false)
    }
    .padding(20)
    .background(Color.backgroundColor)
}

/// Preview-only series (not real market data; shaped like a day of 15-minute closes).
enum MarketPreviewData {
    static let spy: [Double] = [
        755.2, 754.6, 753.1, 752.4, 751.0, 750.3, 749.6, 748.0, 748.4, 746.9, 745.2, 744.8,
        743.0, 742.1, 741.6, 742.3, 740.9, 739.4, 738.8, 739.5, 738.1, 737.0, 736.4, 736.9,
        735.8, 735.1, 735.9, 735.4, 735.0, 735.29
    ]
    static let btc: [Double] = [
        74_860, 74_910, 74_700, 74_620, 74_780, 74_950, 75_040, 74_980, 75_120, 75_260, 75_180, 75_300,
        75_410, 75_380, 75_520, 75_460, 75_610, 75_570, 75_690, 75_740, 75_660, 75_720, 75_810, 75_770,
        75_690, 75_640, 75_700, 75_760, 75_710, 75_699
    ]
}
