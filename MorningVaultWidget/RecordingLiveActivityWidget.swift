import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// Live Activity while a meeting is being recorded: elapsed time on the Lock Screen and in
// the Dynamic Island, with a Stop button. Stop is `StopRecordingIntent`, a
// LiveActivityIntent, so it performs inside the app (in the background if need be) and
// stops the recorder there; the widget never touches audio or the store.

struct RecordingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            RecordingBannerView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        RecordingDot(isPaused: context.state.isPaused)
                        Text(context.state.isPaused ? "Paused" : "Recording")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedText(state: context.state)
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .frame(maxWidth: 80, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.displayTitle)
                        .font(.subheadline)
                        .lineLimit(1)
                        .privacySensitive()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    StopButton()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
            } compactLeading: {
                RecordingDot(isPaused: context.state.isPaused)
                    .padding(.leading, 2)
            } compactTrailing: {
                ElapsedText(state: context.state)
                    .font(.caption.monospacedDigit())
                    .frame(maxWidth: 48, alignment: .trailing)
            } minimal: {
                RecordingDot(isPaused: context.state.isPaused)
            }
            .widgetURL(MeetingsDeepLink.meetings.url)
        }
    }
}

/// The Lock Screen / banner presentation.
private struct RecordingBannerView: View {
    let context: ActivityViewContext<RecordingActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    RecordingDot(isPaused: context.state.isPaused)
                    Text(context.state.isPaused ? "Paused" : "Recording")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(context.attributes.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .privacySensitive()
                ElapsedText(state: context.state)
                    .font(.title2.monospacedDigit().weight(.semibold))
            }
            Spacer(minLength: 8)
            StopButton()
        }
        .padding(16)
        .widgetURL(MeetingsDeepLink.meetings.url)
    }
}

/// Elapsed recording time; frozen while paused.
private struct ElapsedText: View {
    let state: RecordingActivityAttributes.ContentState

    var body: some View {
        Text(timerInterval: state.timerRange, pauseTime: state.isPaused ? (state.pausedAt ?? Date()) : nil, countsDown: false)
    }
}

private struct RecordingDot: View {
    let isPaused: Bool

    var body: some View {
        Image(systemName: isPaused ? "pause.circle.fill" : "record.circle.fill")
            .foregroundStyle(isPaused ? Color.orange : Color.red)
            .font(.caption)
    }
}

private struct StopButton: View {
    var body: some View {
        Button(intent: StopRecordingIntent()) {
            Label("Stop", systemImage: "stop.fill")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .accessibilityLabel("Stop recording")
    }
}
