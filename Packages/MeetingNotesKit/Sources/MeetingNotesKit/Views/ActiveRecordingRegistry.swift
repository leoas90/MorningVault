import Foundation
import SwiftData

/// The one recording that is running right now, reachable from outside the view that
/// owns it: the Live Activity's Stop button (an App Intent that performs in the app
/// process, even in the background) stops the meeting through here.
@MainActor
public final class ActiveRecordingRegistry {
    public static let shared = ActiveRecordingRegistry()

    /// The running session, if any.
    public private(set) weak var session: RecordingSession?
    private var stopAction: (@MainActor () async -> Void)?

    private init() {}

    /// Called by `RecordingSession` when the microphone is running.
    func register(_ session: RecordingSession, stop: @escaping @MainActor () async -> Void) {
        self.session = session
        stopAction = stop
    }

    /// Called by the session when it stops or is discarded.
    func unregister(_ session: RecordingSession) {
        guard self.session === session || self.session == nil else { return }
        self.session = nil
        stopAction = nil
    }

    /// True while a recording is running (or paused).
    public var isRecording: Bool {
        session?.isRecording ?? false
    }

    /// Stops and saves the running recording. Does nothing when none is running.
    public func stop() async {
        guard let stopAction else { return }
        await stopAction()
    }
}
