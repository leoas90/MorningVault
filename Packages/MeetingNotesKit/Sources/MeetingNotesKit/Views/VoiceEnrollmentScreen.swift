import Foundation
import SwiftUI

/// Records about thirty seconds of the user's voice and turns it into the
/// voice profile. The audio is kept in memory only; the recorder's file is
/// deleted as soon as the embedding exists.
@MainActor
final class VoiceEnrollmentSession: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording
        case processing
        case done
        case failed(String)
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
            phase = .failed("Speaker models are not available in this build.")
            return
        }
        guard await RecordingPermissions.requestMicrophone() else {
            phase = .failed(RecorderError.microphoneDenied.localizedDescription)
            return
        }
        samples = []
        elapsed = 0
        sessionID = UUID()
        do {
            try await recorder.start(meetingID: sessionID)
            phase = .recording
        } catch {
            phase = .failed(error.localizedDescription)
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
            phase = .failed("That was too short. Read for at least \(Int(Self.minimumSeconds)) seconds.")
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
                phase = .failed("The voice profile could not be saved: \(error.localizedDescription)")
            }
        case .failure(let error):
            phase = .failed(error.localizedDescription)
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
        let folder = MeetingNotesStore.audioFolder(for: sessionID)
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
                VStack(alignment: .leading, spacing: 20) {
                    status
                    Text("Read this out loud in your normal voice, about 30 seconds. The recording stays in memory and is thrown away; only a small voice fingerprint is kept on this phone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(Self.paragraph)
                        .font(.body)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    controls
                    Toggle(isOn: $session.learnsFromRenames) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Learn from corrections")
                            Text("When you mark a speaker as You in a meeting, the fingerprint is updated with that voice.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if session.isEnrolled {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("Delete voice profile", systemImage: "trash")
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Your voice")
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

    @ViewBuilder
    private var status: some View {
        switch session.phase {
        case .idle:
            if let profile = session.profile {
                Label(
                    "Enrolled \(profile.updatedAt.formatted(date: .abbreviated, time: .shortened)) · \(profile.sampleCount) sample\(profile.sampleCount == 1 ? "" : "s")",
                    systemImage: "checkmark.seal.fill"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else {
                Label("Not enrolled yet", systemImage: "person.crop.circle.badge.questionmark")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .recording:
            HStack(spacing: 10) {
                RecordingStatusPill(mode: .recording, elapsed: session.elapsed)
                ProgressView(value: min(session.elapsed, VoiceEnrollmentSession.targetSeconds), total: VoiceEnrollmentSession.targetSeconds)
            }
        case .processing:
            HStack(spacing: 8) {
                ProgressView()
                Text("Building your voice fingerprint on device…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .done:
            Label("Your voice is saved. Meetings will label you as You.", systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(Color.accentColor)
        case .failed(let message):
            BannerView(message: message, symbol: "exclamationmark.triangle.fill")
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch session.phase {
        case .recording:
            HStack(spacing: 16) {
                Button {
                    Task { await session.cancel() }
                } label: {
                    Text("Cancel").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                Button {
                    Task { await session.finish() }
                } label: {
                    Text("Finish").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!session.canFinish)
            }
        case .processing:
            EmptyView()
        case .idle, .done, .failed:
            Button {
                Task { await session.start() }
            } label: {
                Label(session.isEnrolled ? "Record again" : "Start reading", systemImage: "mic.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}
