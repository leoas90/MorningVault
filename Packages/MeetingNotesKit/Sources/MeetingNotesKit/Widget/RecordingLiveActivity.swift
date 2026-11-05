import Foundation

#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

/// Drives the "Recording" Live Activity (Lock Screen banner and Dynamic Island) for one
/// `RecordingSession`. Every call is safe when Live Activities are off or unavailable:
/// the recording never depends on it.
///
/// `Activity` is not `Sendable`, so only its `id` is kept here; each update looks the
/// activity up again inside the task that talks to ActivityKit.
@MainActor
final class RecordingLiveActivity {
    private var activityID: String?

    init() {}

    /// Whether the user allows Live Activities for this app.
    static var isAvailable: Bool {
        #if canImport(ActivityKit) && os(iOS)
        return ActivityAuthorizationInfo().areActivitiesEnabled
        #else
        return false
        #endif
    }

    /// Shows the activity. `startedAt` is when the timer should count from.
    func start(title: String, startedAt: Date) {
        #if canImport(ActivityKit) && os(iOS)
        guard Self.isAvailable else { return }
        end()
        let state = RecordingActivityAttributes.ContentState(startedAt: startedAt)
        activityID = Self.request(title: title, state: state)
        #endif
    }

    /// Freezes the timer.
    func pause(at date: Date = Date()) {
        #if canImport(ActivityKit) && os(iOS)
        guard let id = activityID else { return }
        Task.detached {
            guard let activity = Self.activity(id: id) else { return }
            var state = activity.content.state
            state.isPaused = true
            state.pausedAt = date
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
        #endif
    }

    /// Resumes the timer so it shows `elapsed` seconds right now.
    func resume(elapsed: TimeInterval, now: Date = Date()) {
        #if canImport(ActivityKit) && os(iOS)
        guard let id = activityID else { return }
        let state = RecordingActivityAttributes.ContentState(startedAt: now.addingTimeInterval(-elapsed))
        Task.detached {
            guard let activity = Self.activity(id: id) else { return }
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
        #endif
    }

    /// Updates the title shown in the activity.
    ///
    /// Attributes are fixed for the life of an activity, so a title change restarts it
    /// with the same timer state; the Lock Screen keeps the elapsed time.
    func setTitle(_ title: String) {
        #if canImport(ActivityKit) && os(iOS)
        guard let id = activityID, let current = Self.activity(id: id),
              current.attributes.meetingTitle != title
        else { return }
        let state = current.content.state
        end()
        activityID = Self.request(title: title, state: state)
        #endif
    }

    /// Removes the activity right away.
    func end() {
        #if canImport(ActivityKit) && os(iOS)
        guard let id = activityID else { return }
        activityID = nil
        Task.detached {
            guard let activity = Self.activity(id: id) else { return }
            await activity.end(activity.content, dismissalPolicy: .immediate)
        }
        #endif
    }

    /// Ends every activity of this kind, including ones left over from a crash.
    static func endAll() {
        #if canImport(ActivityKit) && os(iOS)
        Task.detached {
            for activity in Activity<RecordingActivityAttributes>.activities {
                await activity.end(activity.content, dismissalPolicy: .immediate)
            }
        }
        #endif
    }

    #if canImport(ActivityKit) && os(iOS)
    private static func request(title: String, state: RecordingActivityAttributes.ContentState) -> String? {
        let activity = try? Activity.request(
            attributes: RecordingActivityAttributes(meetingTitle: title),
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )
        return activity?.id
    }

    private nonisolated static func activity(id: String) -> Activity<RecordingActivityAttributes>? {
        Activity<RecordingActivityAttributes>.activities.first { $0.id == id }
    }
    #endif
}
