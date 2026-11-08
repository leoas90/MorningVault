import SwiftUI

// MARK: - Sparkline

/// Line + faint area from a real series. Draws left-to-right over 500 ms on appear; complete
/// at once under Reduce Motion. Never shown without data: callers pass `nil` for no series.
struct Sparkline: View {
    let points: [Double]
    var prevClose: Double? = nil
    var color: Color
    var lineWidth: CGFloat = 1.5
    /// False for offscreen renders (share card): the line is complete immediately.
    var animated: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let line = linePath(in: size)
            let shown: CGFloat = animated ? progress : 1
            ZStack(alignment: .leading) {
                areaPath(in: size)
                    .fill(LinearGradient(colors: [color.opacity(0.22), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: size.width * shown)
                    }
                if let y = prevCloseY(in: size) {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    .stroke(Color.inkSecondary.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
                line
                    .trim(from: 0, to: shown)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
        .onAppear {
            if reduceMotion || !animated {
                progress = 1
            } else {
                withAnimation(.easeOut(duration: 0.5)) { progress = 1 }
            }
        }
        .accessibilityHidden(true)
    }

    private var bounds: (min: Double, max: Double)? {
        guard points.count > 1, let lo = points.min(), let hi = points.max() else { return nil }
        // Include prevClose in the scale only when it is within ~ the series range already;
        // the dotted line is a reference, not a reason to flatten the curve.
        return (lo, hi == lo ? lo + 1 : hi)
    }

    private func y(for value: Double, in size: CGSize, bounds b: (min: Double, max: Double)) -> CGFloat {
        let inset: CGFloat = lineWidth
        let t = (value - b.min) / (b.max - b.min)
        return size.height - inset - CGFloat(t) * (size.height - inset * 2)
    }

    private func linePath(in size: CGSize) -> Path {
        var path = Path()
        guard let b = bounds else { return path }
        let step = size.width / CGFloat(points.count - 1)
        for (i, v) in points.enumerated() {
            let p = CGPoint(x: CGFloat(i) * step, y: y(for: v, in: size, bounds: b))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }

    private func areaPath(in size: CGSize) -> Path {
        var path = linePath(in: size)
        guard !path.isEmpty else { return path }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()
        return path
    }

    private func prevCloseY(in size: CGSize) -> CGFloat? {
        guard let prevClose, let b = bounds, prevClose >= b.min, prevClose <= b.max else { return nil }
        return y(for: prevClose, in: size, bounds: b)
    }
}

// MARK: - Market row

/// Hairline-list row: symbol eyebrow over a tabular price, signed delta with ▲/▼, sparkline
/// right. `compact` is the Brief (26 pt price, 84×28 line); the Markets tab uses the larger set.
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
            VStack(alignment: .leading, spacing: compact ? 3 : 4) {
                Eyebrow(text: symbol)
                Text(priceText)
                    .font(.system(size: compact ? 26 : 32, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.inkPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                Text(deltaText)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(semantic)
            }
            Spacer(minLength: 8)
            if series.count > 1 {
                Sparkline(points: series, prevClose: prevClose, color: semantic, lineWidth: 1.5)
                    .frame(width: compact ? 84 : 120, height: compact ? 28 : 40)
            }
        }
        .padding(.top, compact ? 12 : 14)
        .padding(.bottom, footnote == nil ? (compact ? 12 : 14) : 6)
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
            .font(.system(size: 13).monospacedDigit())
            .lineLimit(1)
            .padding(.bottom, compact ? 12 : 10)
        }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(symbol) \(priceText), \(change >= 0 ? "up" : "down") \(String(format: "%.2f", abs(change))) percent\(footnote.map { ". \($0) \(footnoteDetail ?? "")" } ?? "")")
    }
}

#Preview("Rows") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    return VStack(spacing: 0) {
        MarketRow(symbol: "SPY", priceText: "$735.29", change: -2.70, series: MarketPreviewData.spy, prevClose: 755.0)
        Hairline()
        MarketRow(symbol: "BTC", priceText: "$75,699", change: 1.12, series: MarketPreviewData.btc, prevClose: 74_860)
        Hairline()
        MarketRow(symbol: "AAPL", priceText: "$231.10", change: 0.00)
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
