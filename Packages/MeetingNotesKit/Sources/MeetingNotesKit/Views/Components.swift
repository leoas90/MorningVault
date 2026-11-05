import SwiftUI

/// The round red record control: a white circle when idle, a white square
/// (stop) while recording.
public struct RecordButton: View {
    private let isRecording: Bool
    private let isPaused: Bool
    private let size: CGFloat
    private let action: () -> Void

    public init(isRecording: Bool, isPaused: Bool = false, size: CGFloat = 72, action: @escaping () -> Void) {
        self.isRecording = isRecording
        self.isPaused = isPaused
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: size, height: size)
                    .shadow(color: Color.red.opacity(0.25), radius: 10, y: 4)
                if isRecording {
                    RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                        .fill(Color.white)
                        .frame(width: size * 0.34, height: size * 0.34)
                } else {
                    Circle()
                        .fill(Color.white)
                        .frame(width: size * 0.4, height: size * 0.4)
                }
            }
            .contentShape(Circle())
            .animation(.snappy, value: isRecording)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
        .accessibilityHint(isPaused ? "Recording is paused" : "")
    }
}

/// A small capsule that says what the recorder is doing: "Recording 00:42".
public struct RecordingStatusPill: View {
    public enum Mode: Equatable, Sendable {
        case idle
        case starting
        case recording
        case paused
        case saved
    }

    private let mode: Mode
    private let elapsed: TimeInterval

    public init(mode: Mode, elapsed: TimeInterval) {
        self.mode = mode
        self.elapsed = elapsed
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(dotColor)
                .symbolEffect(.pulse, options: .repeating, isActive: mode == .recording)
            Text(label)
                .font(.footnote.weight(.medium).monospacedDigit())
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.05), in: Capsule())
        .foregroundStyle(mode == .idle ? .secondary : .primary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var dotColor: Color {
        switch mode {
        case .recording: return .red
        case .paused: return .orange
        case .starting: return .secondary
        case .saved: return .green
        case .idle: return .secondary
        }
    }

    private var label: String {
        switch mode {
        case .idle: return "Not recording"
        case .starting: return "Starting…"
        case .recording: return "Recording \(ElapsedTimeLabel.text(for: elapsed))"
        case .paused: return "Paused \(ElapsedTimeLabel.text(for: elapsed))"
        case .saved: return "Saved · \(ElapsedTimeLabel.text(for: elapsed))"
        }
    }

    private var accessibilityText: String {
        switch mode {
        case .idle: return "Not recording"
        case .starting: return "Starting the recording"
        case .recording: return "Recording, \(Int(elapsed)) seconds"
        case .paused: return "Paused at \(Int(elapsed)) seconds"
        case .saved: return "Saved, \(Int(elapsed)) seconds long"
        }
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
///
/// `details` is the raw framework text behind a collapsed "Details" disclosure, so the
/// message itself can stay a plain sentence.
public struct BannerView: View {
    @Environment(\.meetingsTheme) private var theme
    @State private var showDetails = false
    private let message: String
    private let details: String?
    private let symbol: String
    private let actionTitle: String?
    private let action: (() -> Void)?
    private let onDismiss: (() -> Void)?

    public init(
        message: String,
        details: String? = nil,
        symbol: String = "info.circle.fill",
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.message = message
        self.details = details
        self.symbol = symbol
        self.actionTitle = actionTitle
        self.action = action
        self.onDismiss = onDismiss
    }

    /// Splits a `UserMessage.plain(...)`-style pair: plain sentence + raw details.
    public init(
        _ text: UserMessage,
        symbol: String = "info.circle.fill",
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.init(message: text.message, details: text.details, symbol: symbol,
                  actionTitle: actionTitle, action: action, onDismiss: onDismiss)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: symbol)
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
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            if let details, !details.isEmpty {
                DisclosureGroup("Details", isExpanded: $showDetails) {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(theme.surfaceColor, in: RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

/// A sentence a person can read, plus the raw error text for a Details disclosure.
public struct UserMessage: Equatable, Sendable {
    public var message: String
    public var details: String?

    public init(_ message: String, details: String? = nil) {
        self.message = message
        self.details = details
    }

    /// Maps a framework error to a plain sentence; the `localizedDescription` goes to `details`.
    public static func from(_ error: Error, context: String) -> UserMessage {
        let raw = error.localizedDescription
        let detail = raw.isEmpty ? nil : raw
        if let recorder = error as? RecorderError {
            switch recorder {
            case .microphoneDenied, .noInputAvailable:
                return UserMessage(recorder.localizedDescription, details: nil)
            case .audioSessionFailed(let reason):
                return UserMessage("The audio session could not be started.", details: reason)
            case .couldNotCreateFile(let reason):
                return UserMessage("The recording file could not be created.", details: reason)
            case .engineFailed(let reason):
                return UserMessage("The microphone could not be started.", details: reason)
            }
        }
        if let urlError = error as? URLError, urlError.code == .notConnectedToInternet {
            return UserMessage("\(context) It needs a connection.", details: detail)
        }
        return UserMessage(context, details: detail)
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

/// The light, rounded card every block of content sits on.
struct CardBackground: ViewModifier {
    @Environment(\.meetingsTheme) private var theme

    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surfaceColor, in: RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous))
    }
}

extension View {
    func card() -> some View {
        modifier(CardBackground())
    }

    /// Inline navigation title where the platform supports it.
    @ViewBuilder
    func inlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Sentence capitalisation on the software keyboard where there is one.
    @ViewBuilder
    func sentenceCapitalization() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.sentences)
        #else
        self
        #endif
    }
}
