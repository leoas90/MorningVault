import SwiftUI

/// The big round button that starts and stops a recording.
public struct RecordButton: View {
    private let isRecording: Bool
    private let isPaused: Bool
    private let action: () -> Void

    public init(isRecording: Bool, isPaused: Bool = false, action: @escaping () -> Void) {
        self.isRecording = isRecording
        self.isPaused = isPaused
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.16))
                    .frame(width: 104, height: 104)
                Circle()
                    .strokeBorder(Color.red.opacity(0.35), lineWidth: 1)
                    .frame(width: 88, height: 88)
                if isRecording && !isPaused {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.red)
                        .frame(width: 34, height: 34)
                } else if isPaused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Color.red)
                } else {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 62, height: 62)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
    }
}

/// A row of bars that shows the microphone level over time.
public struct LevelMeter: View {
    private let history: [Double]
    private let tint: Color

    public init(history: [Double], tint: Color = .accentColor) {
        self.history = history
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { proxy in
            let bars = max(1, min(Int(proxy.size.width / 7), max(history.count, 1)))
            let values = Array(history.suffix(bars))
            HStack(alignment: .center, spacing: 3) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    Capsule()
                        .fill(tint.opacity(0.35 + 0.65 * value))
                        .frame(width: 4, height: max(4, 44 * value))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 48)
        .accessibilityLabel("Microphone level")
    }
}

/// The elapsed time, shown in a monospaced font.
public struct ElapsedTimeLabel: View {
    private let elapsed: TimeInterval

    public init(elapsed: TimeInterval) {
        self.elapsed = elapsed
    }

    public var body: some View {
        Text(Self.text(for: elapsed))
            .font(.system(.title2, design: .monospaced).weight(.medium))
            .contentTransition(.numericText())
            .accessibilityLabel("Recorded for \(Int(elapsed)) seconds")
    }

    /// `12:07` or `1:02:07`.
    public static func text(for elapsed: TimeInterval) -> String {
        let total = max(0, Int(elapsed))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

/// A short message shown above the content, for example after a phone call.
public struct BannerView: View {
    private let message: String
    private let onDismiss: (() -> Void)?

    public init(message: String, onDismiss: (() -> Void)? = nil) {
        self.message = message
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.tint)
            Text(message)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

/// A calm placeholder for lists that have nothing in them yet.
public struct EmptyStateView: View {
    private let symbol: String
    private let title: String
    private let message: String

    public init(symbol: String, title: String, message: String) {
        self.symbol = symbol
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

/// A small label used for section titles.
public struct SectionHeader: View {
    private let title: String
    private let systemImage: String

    public init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    public var body: some View {
        Label(title, systemImage: systemImage)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
    }
}
