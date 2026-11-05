import Foundation
import SwiftData

/// Sample meetings used by previews and by the picture mode of the host app.
@MainActor
public enum MeetingPreviewData {
    /// Adds a few sample meetings to a context.
    public static func insertSampleMeetings(into context: ModelContext) {
        let samples: [(String, String, [String], String, String, [ActionItem])] = [
            (
                "Product weekly",
                "10:00",
                ["Ana", "Ben", "Chi"],
                "We went through the release checklist. The beta build is done and the app store review is booked for Friday. Ben will finish the migration notes.",
                "Ask Ana for the final screenshots before Friday.",
                [
                    ActionItem(text: "Send the beta build to the test group", owner: "Ben", due: "Thursday"),
                    ActionItem(text: "Write the release notes", owner: "Ana", due: "Friday")
                ]
            ),
            (
                "Design review",
                "14:30",
                ["Ana", "Dee"],
                "Dee walked through the new navigation. The team liked the simpler tab bar. One question is still open about the empty states on iPad.",
                "Remember to send Dee the icon grid.",
                [
                    ActionItem(text: "Share the icon grid with Dee", owner: "Ana", due: nil)
                ]
            )
        ]

        for (index, sample) in samples.enumerated() {
            let meeting = Meeting(
                title: sample.0,
                startedAt: Date().addingTimeInterval(Double(-index) * 86_400 - 3_600),
                duration: 1_240 + Double(index) * 300,
                scratchpad: sample.4,
                transcript: sample.3,
                attendeeNames: sample.2
            )
            context.insert(meeting)

            for item in sample.5 {
                context.insert(
                    ActionItemRecord(
                        meetingID: meeting.id,
                        text: item.text,
                        owner: item.owner,
                        due: item.due.flatMap { DueFormatter.date(from: $0) },
                        createdAt: meeting.startedAt
                    )
                )
            }
        }
        try? context.save()
    }

    /// The sample text used by the picture mode of the host app.
    public static let sampleTranscript = """
    Ana opened the meeting and asked where the release checklist stands. \
    Ben said the beta build is done and the app store review is booked for Friday. \
    Chi asked about the migration notes and Ben promised to finish them today. \
    They agreed to ship the beta on Friday and to send the test group a build on Thursday.
    """

    /// The sample notes used by the picture mode of the host app.
    public static let sampleScratchpad = """
    Ship the beta on Friday.

    - Test group build Thursday
    - Migration notes: Ben
    - Ask Ana for screenshots
    """

    /// A calm, looping waveform used by the picture mode of the host app.
    public static func waveform(phase: Double, count: Int = 48) -> [Double] {
        (0..<count).map { index in
            let x = Double(index) * 0.42 + phase
            let wave = abs(sin(x)) * (0.55 + 0.45 * abs(sin(x * 0.37)))
            return min(1, max(0.06, 0.18 + 0.72 * wave))
        }
    }
}
