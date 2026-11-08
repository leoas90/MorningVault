import SwiftUI

// MARK: - Shared editorial pieces
//
// Every Meetings screen is built from the pieces in this file: the eyebrow, the hairline,
// pills, the checkbox and the 52 pt buttons. The Meetings tab is one flow separated by
// hairlines; the card modifiers below are kept for banners and the voice enrollment sheet
// only. Keep styling here so the screens only describe structure.

/// 11 pt semibold uppercase label with 0.8 tracking, in secondary ink.
struct Eyebrow: View {
    @Environment(\.meetingsTheme) private var theme
    let text: String
    var color: Color?

    init(_ text: String, color: Color? = nil) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(MeetingsType.eyebrow)
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(color ?? theme.inkSoft)
            .lineLimit(1)
    }
}

/// 1 pt rule in the hairline color.
struct Hairline: View {
    @Environment(\.meetingsTheme) private var theme
    var color: Color?

    var body: some View {
        Rectangle()
            .fill(color ?? theme.hairlineColor)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// The one primary card on a screen: radius 28, padding 20, a soft shadow in light mode and
/// a hairline in dark mode.
struct PrimaryCardModifier: ViewModifier {
    @Environment(\.meetingsTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    var padding: CGFloat = 20

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.primaryRadius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surfaceColor, in: shape)
            .overlay(shape.strokeBorder(theme.hairlineColor, lineWidth: colorScheme == .dark ? 1 : 0))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.08), radius: 20, y: 8)
    }
}

/// A secondary, functional card: radius 20, padding 16, lighter shadow / hairline.
struct FunctionalCardModifier: ViewModifier {
    @Environment(\.meetingsTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.functionalRadius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surfaceColor, in: shape)
            .overlay(shape.strokeBorder(theme.hairlineColor, lineWidth: colorScheme == .dark ? 1 : 0))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.05), radius: 12, y: 4)
    }
}

/// Small rounded label on a 6 % tint: owners, due dates, counts.
struct TintPill: View {
    @Environment(\.meetingsTheme) private var theme
    let text: String
    var tint: Color?
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(text)
                .font(MeetingsType.metaMedium)
        }
        .lineLimit(1)
        .foregroundStyle(tint ?? theme.ink)
        .padding(.horizontal, 8)
        .frame(minHeight: 22)
        .background((tint ?? theme.ink).opacity(0.06), in: Capsule())
    }
}

/// 22 pt circle checkbox: hairline ring when open, filled accent with a check when done.
struct CheckCircle: View {
    @Environment(\.meetingsTheme) private var theme
    let isDone: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(isDone ? Color.clear : theme.inkSoft.opacity(0.6), lineWidth: 1.5)
            Circle()
                .fill(isDone ? theme.accentColor : Color.clear)
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(theme.onAccentColor)
                .opacity(isDone ? 1 : 0)
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}

/// The breathing dot next to "Recording". Still under Reduce Motion and when inactive.
struct BreathingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let color: Color
    var isActive = true
    @State private var breathing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .opacity(breathing ? 0.45 : 1)
            .scaleEffect(breathing ? 0.85 : 1)
            .onAppear { update() }
            .onChange(of: isActive) { _, _ in update() }
            .accessibilityHidden(true)
    }

    private func update() {
        if isActive, !reduceMotion {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { breathing = true }
        } else {
            withAnimation(.easeOut(duration: 0.2)) { breathing = false }
        }
    }
}

/// Pressed controls scale to 0.98; a plain fade under Reduce Motion.
struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

/// The 52 pt full-width control. `primary` is the accent (one per screen), `secondary` is a
/// surface with a hairline, `negative` is the Stop control.
struct MeetingsButton: View {
    enum Role { case primary, secondary, negative }

    @Environment(\.meetingsTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    var systemImage: String?
    var role: Role = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(MeetingsType.symbol)
                        .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                }
                Text(title)
                    .font(MeetingsType.button)
                    .contentTransition(reduceMotion ? .opacity : .numericText())
            }
            .lineLimit(1)
            .animation(.smooth(duration: 0.25), value: title)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: MeetingsSpace.control)
            .background(fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(role == .secondary ? theme.ink.opacity(0.14) : Color.clear, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.pressable)
    }

    private var fill: Color {
        switch role {
        case .primary: return theme.accentColor
        case .secondary: return theme.ink.opacity(0.05)
        case .negative: return theme.negativeColor
        }
    }

    private var foreground: Color {
        switch role {
        case .primary, .negative: return theme.onAccentColor
        case .secondary: return theme.ink
        }
    }
}

/// Neutral 44×44 symbol button for toolbars and headers; never accent-coloured.
struct IconButton: View {
    @Environment(\.meetingsTheme) private var theme
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(theme.ink)
                .frame(width: MeetingsSpace.target, height: MeetingsSpace.target)
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
    }
}

/// A 32 pt segmented control drawn in the Meetings language.
struct SegmentedTabs<Item: Hashable>: View {
    @Environment(\.meetingsTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let items: [Item]
    let title: (Item) -> String
    @Binding var selection: Item

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                let selected = item == selection
                Button {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { selection = item }
                } label: {
                    Text(title(item))
                        .font(.system(size: 13, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? theme.ink : theme.inkSoft)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(theme.surfaceColor)
                                    .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.08), radius: 4, y: 1)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(theme.hairlineColor, lineWidth: colorScheme == .dark ? 1 : 0)
                                    )
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(2)
        .frame(height: 32)
        .background(theme.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Joins non-empty parts with " · ".
enum MetaLine {
    static func join(_ parts: [String?]) -> String {
        parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// "3 speakers", "1 speaker".
    static func count(_ n: Int, _ singular: String, _ plural: String) -> String {
        "\(n) \(n == 1 ? singular : plural)"
    }

    /// "26 min", "1 h 05 min", "under a minute": the length of a meeting in a meta line.
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return "under a minute" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : String(format: "%d h %02d min", hours, rest)
    }
}

// MARK: - Public pieces (kept for hosts)

/// The round record control: a white circle when idle, a white square (stop) while recording.
/// Uses the theme accent when idle and the negative color while recording.
public struct RecordButton: View {
    @Environment(\.meetingsTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    .fill(isRecording ? theme.negativeColor : theme.accentColor)
                    .frame(width: size, height: size)
                    .shadow(color: (isRecording ? theme.negativeColor : theme.accentColor).opacity(0.25), radius: 10, y: 4)
                if isRecording {
                    RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                        .fill(theme.onAccentColor)
                        .frame(width: size * 0.34, height: size * 0.34)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: size * 0.36, weight: .medium))
                        .foregroundStyle(theme.onAccentColor)
                }
            }
            .contentShape(Circle())
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: isRecording)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
        .accessibilityHint(isPaused ? "Recording is paused" : "")
    }
}

/// A small status line that says what the recorder is doing: a breathing dot and
/// "Recording 00:42".
public struct RecordingStatusPill: View {
    public enum Mode: Equatable, Sendable {
        case idle
        case starting
        case recording
        case paused
        case saved
    }

    @Environment(\.meetingsTheme) private var theme
    private let mode: Mode
    private let elapsed: TimeInterval

    public init(mode: Mode, elapsed: TimeInterval) {
        self.mode = mode
        self.elapsed = elapsed
    }

    public var body: some View {
        HStack(spacing: 8) {
            BreathingDot(color: dotColor, isActive: mode == .recording)
            Text(label)
                .font(MeetingsType.metaMedium.monospacedDigit())
                .contentTransition(.numericText())
                .foregroundStyle(mode == .idle ? theme.inkSoft : theme.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var dotColor: Color {
        switch mode {
        case .recording: return theme.negativeColor
        case .paused: return theme.inkSoft
        case .starting: return theme.inkSoft
        case .saved: return theme.positiveColor
        case .idle: return theme.inkSoft.opacity(0.5)
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

/// Microphone level over time, drawn as a row of bars in a `Canvas`. With no history the
/// meter shows a quiet "listening" pulse instead of an empty box.
public struct LevelMeter: View {
    @Environment(\.meetingsTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let history: [Double]
    private let tint: Color?
    private let isActive: Bool
    @State private var pulse = false

    public init(history: [Double], tint: Color = .accentColor) {
        self.history = history
        self.tint = tint
        self.isActive = true
    }

    /// Package initialiser: theme-tinted, `isActive` drives the idle pulse.
    init(history: [Double], isActive: Bool, themed: Bool) {
        self.history = history
        self.tint = nil
        self.isActive = isActive
    }

    public var body: some View {
        let color = tint ?? theme.ink
        Canvas { context, size in
            let barWidth: CGFloat = 3
            let gap: CGFloat = 3
            let count = max(1, Int((size.width + gap) / (barWidth + gap)))
            let values = Self.resample(history, to: count)
            let midY = size.height / 2
            for (index, value) in values.enumerated() {
                let x = CGFloat(index) * (barWidth + gap)
                let height = max(3, size.height * CGFloat(value) * 0.92)
                let rect = CGRect(x: x, y: midY - height / 2, width: barWidth, height: height)
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                let alpha = history.isEmpty ? (pulse ? 0.45 : 0.22) : 0.25 + 0.6 * value
                context.fill(path, with: .color(color.opacity(alpha)))
            }
        }
        .frame(height: 44)
        .onAppear { updatePulse() }
        .onChange(of: isActive) { _, _ in updatePulse() }
        .onChange(of: history.isEmpty) { _, _ in updatePulse() }
        .accessibilityLabel("Microphone level")
    }

    private func updatePulse() {
        if isActive, history.isEmpty, !reduceMotion {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
        } else {
            withAnimation(.easeOut(duration: 0.2)) { pulse = false }
        }
    }

    /// Stretches or trims `values` to `count` bars; an empty history becomes a flat line.
    static func resample(_ values: [Double], to count: Int) -> [Double] {
        guard count > 0 else { return [] }
        guard !values.isEmpty else { return Array(repeating: 0.08, count: count) }
        if values.count >= count { return Array(values.suffix(count)) }
        let padding = Array(repeating: 0.06, count: count - values.count)
        return padding + values
    }
}

/// The elapsed time, shown as the hero of the recording screen.
public struct ElapsedTimeLabel: View {
    @Environment(\.meetingsTheme) private var theme
    private let elapsed: TimeInterval

    public init(elapsed: TimeInterval) {
        self.elapsed = elapsed
    }

    public var body: some View {
        Text(Self.text(for: elapsed))
            .font(MeetingsType.heroTimer)
            .foregroundStyle(theme.ink)
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
        symbol: String = "info.circle",
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
        symbol: String = "info.circle",
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
                    .font(MeetingsType.symbol)
                    .foregroundStyle(theme.inkSoft)
                Text(message)
                    .font(MeetingsType.secondary)
                    .lineSpacing(3)
                    .foregroundStyle(theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.inkSoft)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                }
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(MeetingsType.metaMedium)
                    .foregroundStyle(theme.accentColor)
                    .buttonStyle(.plain)
            }
            if let details, !details.isEmpty {
                DisclosureGroup("Details", isExpanded: $showDetails) {
                    Text(details)
                        .font(MeetingsType.meta)
                        .foregroundStyle(theme.inkSoft)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .font(MeetingsType.metaMedium)
                .foregroundStyle(theme.inkSoft)
            }
        }
        .functionalCard()
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

/// A calm placeholder for lists that have nothing in them yet: no illustration, one line.
public struct EmptyStateView: View {
    @Environment(\.meetingsTheme) private var theme
    private let symbol: String
    private let title: String
    private let message: String

    public init(symbol: String, title: String, message: String) {
        self.symbol = symbol
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(MeetingsType.rowTitle)
                .foregroundStyle(theme.ink)
            Text(message)
                .font(MeetingsType.secondary)
                .lineSpacing(3)
                .foregroundStyle(theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 20)
    }
}

/// A small label used for section titles. Drawn as an eyebrow; the symbol is kept for
/// source compatibility and not shown.
public struct SectionHeader: View {
    private let title: String
    private let systemImage: String

    public init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    public var body: some View {
        Eyebrow(title)
    }
}

extension View {
    /// The one primary card on a screen.
    func primaryCard(padding: CGFloat = 20) -> some View {
        modifier(PrimaryCardModifier(padding: padding))
    }

    /// A secondary, functional card.
    func functionalCard(padding: CGFloat = 16) -> some View {
        modifier(FunctionalCardModifier(padding: padding))
    }

    /// Earlier name of `functionalCard()`.
    func card() -> some View {
        functionalCard()
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

    /// Hides the navigation bar on iOS (the screen draws its own title).
    @ViewBuilder
    func hiddenNavigationBar() -> some View {
        #if os(iOS)
        toolbar(.hidden, for: .navigationBar)
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
