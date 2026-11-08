import Foundation
import SwiftUI

/// Records about thirty seconds of the user's voice and turns it into the
/// voice profile. The audio is kept in memory only; the recorder's file is
/// deleted as soon as the embedding exists. The clip lives under its own
/// `Enrollment/` root, never among the meetings, and the launch sweep clears
/// anything a crash left there.
@MainActor
final class VoiceEnrollmentSession: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording
        case processing
        case done
        case failed(UserMessage)
    }

    /// Target length of the reading.
    static let targetSeconds: TimeInterval = 30
    /// Shortest clip accepted.
    static let minimumSeconds: TimeInterval = 8

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var level: Double = 0
    @Published private(set) var profile: VoiceProfile?
    @Published var learnsFromRenames = true {
        didSet { persistToggle() }
    }

    let recorder = AudioRecorder()
    private var samples: [Float] = []
    private var sessionID = UUID()

    init() {
        profile = VoiceProfileStore.load()
        learnsFromRenames = profile?.learnsFromRenames ?? true
        recorder.onChunk = { [weak self] chunk in
            self?.collect(chunk)
        }
        recorder.onLevel = { [weak self] value in
            self?.level = value
        }
        recorder.onElapsed = { [weak self] value in
            guard let self else { return }
            self.elapsed = value
            if value >= Self.targetSeconds, self.phase == .recording {
                Task { await self.finish() }
            }
        }
    }

    var isEnrolled: Bool { profile != nil }

    var canFinish: Bool { phase == .recording && elapsed >= Self.minimumSeconds }

    func start() async {
        guard phase == .idle || phase == .done || isFailed else { return }
        guard SpeakerDiarizer.isAvailable else {
            phase = .failed(UserMessage("Speaker models are not available in this build."))
            return
        }
        guard await RecordingPermissions.requestMicrophone() else {
            phase = .failed(UserMessage(RecorderError.microphoneDenied.localizedDescription))
            return
        }
        samples = []
        elapsed = 0
        sessionID = UUID()
        do {
            try MeetingNotesStore.ensureEnrollmentFolder(for: sessionID)
            try await recorder.start(fileURL: MeetingNotesStore.enrollmentAudioURL(for: sessionID))
            phase = .recording
        } catch {
            phase = .failed(UserMessage.from(error, context: "The recording could not start."))
            deleteRecording()
        }
    }

    func finish() async {
        guard phase == .recording else { return }
        phase = .processing
        _ = await recorder.stop()
        deleteRecording()
        let clip = samples
        samples = []
        guard Double(clip.count) / AudioFileSamples.targetSampleRate >= Self.minimumSeconds else {
            phase = .failed(UserMessage("That was too short. Read for at least \(Int(Self.minimumSeconds)) seconds."))
            return
        }
        let toggle = learnsFromRenames
        let outcome: Result<[Float], Error> = await Task.detached(priority: .userInitiated) {
            do {
                return .success(try await SpeakerDiarizer.shared.embedding(of: clip))
            } catch {
                return .failure(error)
            }
        }.value
        switch outcome {
        case .success(let embedding):
            let saved = VoiceProfile(embedding: embedding, learnsFromRenames: toggle)
            do {
                try VoiceProfileStore.save(saved)
                profile = saved
                phase = .done
            } catch {
                phase = .failed(UserMessage.from(error, context: "The voice profile could not be saved."))
            }
        case .failure(let error):
            phase = .failed(UserMessage.from(error, context: "Your voice could not be analyzed."))
        }
    }

    func cancel() async {
        if phase == .recording {
            await recorder.cancel()
        }
        deleteRecording()
        samples = []
        phase = .idle
        elapsed = 0
    }

    func deleteProfile() {
        VoiceProfileStore.delete()
        profile = nil
        phase = .idle
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    private func collect(_ chunk: AudioChunk) {
        guard phase == .recording else { return }
        samples.append(contentsOf: AudioFileSamples.resample(chunk.samples, from: chunk.sampleRate))
    }

    private func deleteRecording() {
        let folder = MeetingNotesStore.enrollmentFolder(for: sessionID)
        try? FileManager.default.removeItem(at: folder)
    }

    private func persistToggle() {
        guard var profile, profile.learnsFromRenames != learnsFromRenames else { return }
        profile.learnsFromRenames = learnsFromRenames
        try? VoiceProfileStore.save(profile)
        self.profile = profile
    }
}

/// The "Your voice" screen: read a paragraph, get recognised as "You".
public struct VoiceEnrollmentScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.meetingsTheme) private var theme
    @StateObject private var session = VoiceEnrollmentSession()
    @State private var confirmDelete = false

    public init() {}

    static let paragraph = """
    Thanks for taking the time today. Before we go through the agenda, I want to \
    make sure everyone has seen the latest numbers. The plan is to review the \
    budget first, then the timeline, and leave the last ten minutes for \
    questions. If anything is unclear, stop me and we can go over it again. \
    I'll send a short recap this afternoon with the decisions and who owns what.
    """

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Your voice")
                        .font(MeetingsType.pageTitle)
                        .foregroundStyle(theme.ink)
                        .accessibilityAddTraits(.isHeader)

                    status
                        .padding(.top, MeetingsSpace.label)

                    Text("Read this out loud in your normal voice, about 30 seconds. The recording stays in memory and is thrown away; only a small voice fingerprint is kept on this phone.")
                        .font(MeetingsType.secondary)
                        .lineSpacing(3)
                        .foregroundStyle(theme.inkSoft)
                        .padding(.top, 12)

                    readingCard
                        .padding(.top, 20)

                    if case .failed(let message) = session.phase {
                        BannerView(message, symbol: "exclamationmark.triangle")
                            .padding(.top, MeetingsSpace.cardGap)
                    }

                    controls
                        .padding(.top, MeetingsSpace.cardGap)

                    Hairline()
                        .padding(.top, MeetingsSpace.sectionGap)

                    Toggle(isOn: $session.learnsFromRenames) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Learn from corrections")
                                .font(MeetingsType.rowTitle)
                                .foregroundStyle(theme.ink)
                            Text("When you mark a speaker as You in a meeting, the fingerprint is updated with that voice.")
                                .font(MeetingsType.meta)
                                .lineSpacing(2)
                                .foregroundStyle(theme.inkSoft)
                        }
                    }
                    .tint(theme.accentColor)
                    .padding(.vertical, 14)

                    if session.isEnrolled {
                        Hairline()
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("Delete voice profile", systemImage: "trash")
                                .font(MeetingsType.secondary)
                                .foregroundStyle(theme.negativeColor)
                                .frame(minHeight: MeetingsSpace.target)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, MeetingsSpace.margin)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .themedPageBackground()
            .navigationTitle("")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Task {
                            if session.phase == .recording { await session.cancel() }
                            dismiss()
                        }
                    }
                }
            }
            .confirmationDialog("Delete your voice profile?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { session.deleteProfile() }
                Button("Keep", role: .cancel) {}
            } message: {
                Text("Meetings will no longer label your turns as You until you enroll again.")
            }
            .interactiveDismissDisabled(session.phase == .recording || session.phase == .processing)
        }
    }

    /// The paragraph to read, with the thin accent progress bar while recording.
    private var readingCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if session.phase == .recording {
                    BreathingDot(color: theme.negativeColor)
                    Eyebrow("Recording \(ElapsedTimeLabel.text(for: session.elapsed))", color: theme.negativeColor)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                } else {
                    Eyebrow("Read this")
                }
                Spacer(minLength: 8)
                if session.phase == .recording {
                    Text("\(Int(min(session.elapsed, VoiceEnrollmentSession.targetSeconds)))s of \(Int(VoiceEnrollmentSession.targetSeconds))s")
                        .font(MeetingsType.metaMono)
                        .foregroundStyle(theme.inkSoft)
                        .monospacedDigit()
                }
            }
            Text(Self.paragraph)
                .font(MeetingsType.body)
                .lineSpacing(6)
                .foregroundStyle(theme.ink)
                .padding(.top, 12)
            if session.phase == .recording {
                EnrollmentProgressBar(
                    progress: min(session.elapsed / VoiceEnrollmentSession.targetSeconds, 1),
                    level: session.level
                )
                .padding(.top, 16)
            }
        }
        .primaryCard()
    }

    @ViewBuilder
    private var status: some View {
        switch session.phase {
        case .idle, .failed:
            if let profile = session.profile {
                Eyebrow("Enrolled \(profile.updatedAt.formatted(date: .abbreviated, time: .shortened)) · \(MetaLine.count(profile.sampleCount, "sample", "samples"))")
            } else {
                Eyebrow("Not enrolled yet")
            }
        case .recording:
            Eyebrow("Keep reading")
        case .processing:
            WorkingLine("Building your voice fingerprint on device…")
        case .done:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("Your voice is saved. Meetings will label you as You.")
                    .font(MeetingsType.metaMedium)
            }
            .foregroundStyle(theme.positiveColor)
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch session.phase {
        case .recording:
            HStack(spacing: 12) {
                MeetingsButton(title: "Cancel", role: .secondary) {
                    Task { await session.cancel() }
                }
                MeetingsButton(title: "Finish", systemImage: "checkmark", role: .primary) {
                    Task { await session.finish() }
                }
                .disabled(!session.canFinish)
            }
        case .processing:
            EmptyView()
        case .idle, .done, .failed:
            MeetingsButton(
                title: session.isEnrolled ? "Record again" : "Start reading",
                systemImage: "mic.fill",
                role: .primary
            ) {
                Task { await session.start() }
            }
        }
    }
}

/// Thin accent bar for the 30 second reading, with a faint level tint behind it.
struct EnrollmentProgressBar: View {
    @Environment(\.meetingsTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let progress: Double
    let level: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.hairlineColor)
                Capsule()
                    .fill(theme.accentColor.opacity(0.25 + 0.5 * level))
                    .frame(width: max(4, proxy.size.width * progress))
                    .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: progress)
            }
        }
        .frame(height: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reading progress")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

// MARK: - Previews

#Preview("Enrollment · light") {
    VoiceEnrollmentScreen()
        .meetingsTheme(MeetingPreviewData.warmTheme(.light))
        .preferredColorScheme(.light)
}

#Preview("Enrollment · dark") {
    VoiceEnrollmentScreen()
        .meetingsTheme(MeetingPreviewData.warmTheme(.dark))
        .preferredColorScheme(.dark)
}
