import AVFoundation
import Foundation

/// Plays back a finished recording.
@MainActor
public final class AudioPlaybackController: NSObject, ObservableObject {
    @Published public private(set) var isPlaying = false
    @Published public private(set) var progress: Double = 0
    @Published public private(set) var errorMessage: String?

    private var player: AVAudioPlayer?

    /// Plays the file at `url`, or pauses it when it is already playing.
    public func toggle(url: URL) {
        if isPlaying {
            pause()
            return
        }
        play(url: url)
    }

    /// Starts playback of the recording.
    public func play(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "The recording file is missing."
            return
        }
        do {
            if player == nil {
                player = try AVAudioPlayer(contentsOf: url)
                player?.delegate = self
            }
            player?.currentTime = 0
            player?.play()
            isPlaying = true
        } catch {
            errorMessage = "Could not play the recording: \(error.localizedDescription)"
        }
    }

    /// Pauses playback.
    public func pause() {
        player?.pause()
        isPlaying = false
    }

    /// Stops playback and rewinds.
    public func stop() {
        player?.stop()
        player?.currentTime = 0
        isPlaying = false
        progress = 0
    }
}

extension AudioPlaybackController: AVAudioPlayerDelegate {
    public nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.progress = 0
        }
    }
}
