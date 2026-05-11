import SwiftUI

/// Audio player controls overlay for briefing playback.
/// Appears as a floating mini-player or expanded view.
struct AudioPlayerView: View {
    @ObservedObject var audioService: AudioBriefingService
    let onDismiss: () -> Void

    @State private var isExpanded = false
    @State private var showRatePicker = false

    private var formattedTimeRemaining: String {
        let minutes = audioService.estimatedSecondsRemaining / 60
        let seconds = audioService.estimatedSecondsRemaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                expandedPlayer
            } else {
                miniPlayer
            }
        }
        .background(Color.warmCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 20 : 16))
        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 4)
        .padding(.horizontal, 16)
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                isExpanded.toggle()
            }
        }
    }

    // MARK: - Mini Player

    private var miniPlayer: some View {
        HStack(spacing: 12) {
            // Play/Pause
            Button {
                if audioService.isPlaying {
                    audioService.pause()
                } else {
                    audioService.play()
                }
            } label: {
                Image(systemName: audioService.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.warmPrimaryAccent)
                    .frame(width: 36, height: 36)
                    .background(Color.warmPrimaryAccent.opacity(0.12))
                    .clipShape(Circle())
            }

            // Section info
            VStack(alignment: .leading, spacing: 2) {
                Text(audioService.currentSectionTitle)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.warmTextPrimary)
                    .lineLimit(1)
                Text("\(audioService.currentSectionIndex + 1) of \(audioService.totalSections)")
                    .font(.caption2)
                    .foregroundStyle(Color.warmTextSecondary)
            }

            Spacer()

            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.warmDivider.opacity(0.4), lineWidth: 3)
                    .frame(width: 36, height: 36)
                Circle()
                    .trim(from: 0, to: audioService.progress)
                    .stroke(Color.warmPrimaryAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 36, height: 36)
                    .rotationEffect(.degrees(-90))
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.warmPrimaryAccent)
            }

            // Close
            Button {
                audioService.stop()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.warmTextSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Expanded Player

    private var expandedPlayer: some View {
        VStack(spacing: 20) {
            // Handle
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.warmTextSecondary.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Now Playing")
                        .font(.caption2)
                        .foregroundStyle(Color.warmTextSecondary)
                    Text(audioService.currentSectionTitle)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.warmTextPrimary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    audioService.stop()
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.warmTextSecondary)
                }
            }
            .padding(.horizontal, 20)

            // Progress bar
            VStack(spacing: 8) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.warmDivider.opacity(0.3))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.warmPrimaryAccent)
                            .frame(width: geometry.size.width * audioService.progress, height: 6)
                    }
                }
                .frame(height: 6)

                HStack {
                    Text("\(audioService.currentSectionIndex + 1)/\(audioService.totalSections)")
                        .font(.caption2)
                        .foregroundStyle(Color.warmTextSecondary)
                    Spacer()
                    Text(formattedTimeRemaining + " left")
                        .font(.caption2)
                        .foregroundStyle(Color.warmTextSecondary)
                }
            }
            .padding(.horizontal, 20)

            // Main controls
            HStack(spacing: 32) {
                Button { audioService.previousSection() } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.warmTextPrimary)
                }

                Button {
                    if audioService.isPlaying {
                        audioService.pause()
                    } else {
                        audioService.play()
                    }
                } label: {
                    Image(systemName: audioService.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.warmPrimaryAccent)
                }

                Button { audioService.nextSection() } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.warmTextPrimary)
                }
            }

            // Rate control
            HStack(spacing: 12) {
                Text("Speed")
                    .font(.caption)
                    .foregroundStyle(Color.warmTextSecondary)

                ForEach(audioService.ratePresets, id: \.label) { preset in
                    Button {
                        audioService.setRate(preset.value)
                    } label: {
                        Text(preset.label)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(
                                abs(audioService.rate - preset.value) < 0.01
                                    ? Color.warmPrimaryAccent
                                    : Color.warmTextSecondary
                            )
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                abs(audioService.rate - preset.value) < 0.01
                                    ? Color.warmPrimaryAccent.opacity(0.15)
                                    : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Audio FAB Button

/// Floating action button to start audio briefing.
struct AudioPlayButton: View {
    let sections: [BriefingSection]
    let onTap: (AudioBriefingService) -> Void

    @State private var showPlayer = false
    @StateObject private var audioService = AudioBriefingService.shared

    var body: some View {
        Button {
            if sections.isEmpty { return }
            audioService.load(sections: sections)
            onTap(audioService)
            showPlayer = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("Listen")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color.warmPrimaryAccent)
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .disabled(sections.isEmpty)
    }
}