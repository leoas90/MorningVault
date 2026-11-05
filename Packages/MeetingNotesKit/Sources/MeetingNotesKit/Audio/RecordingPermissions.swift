import AVFoundation
import Foundation
import Speech
#if canImport(UIKit)
import UIKit
#endif

/// Asks for the permissions a recording needs *before* any audio engine starts.
///
/// Starting `AVAudioEngine` without microphone permission does not prompt the
/// user on every OS version and can leave the input node with an empty format,
/// so the kit always goes through here first.
public enum RecordingPermissions {
    public enum Status: Equatable, Sendable {
        case granted
        case denied
        case undetermined
    }

    /// Current microphone permission without prompting.
    public static var microphone: Status {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        case .undetermined: return .undetermined
        @unknown default: return .undetermined
        }
    }

    /// Current speech recognition permission without prompting.
    public static var speech: Status {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .undetermined
        @unknown default: return .undetermined
        }
    }

    /// Asks for microphone access when it has not been decided yet.
    public static func requestMicrophone() async -> Bool {
        switch microphone {
        case .granted: return true
        case .denied: return false
        case .undetermined: return await AVAudioApplication.requestRecordPermission()
        }
    }

    /// Asks for speech recognition access when it has not been decided yet.
    ///
    /// A refusal only switches transcription off; recording still works.
    public static func requestSpeech() async -> Bool {
        switch speech {
        case .granted: return true
        case .denied: return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
    }

    /// Opens the app's page in Settings so the user can switch a permission on.
    @MainActor
    public static func openSettings() {
        #if canImport(UIKit) && !os(watchOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }
}
