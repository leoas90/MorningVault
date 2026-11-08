import Foundation
import SwiftData
import SwiftUI

/// Sample meetings used by previews and by the picture mode of the host app.
@MainActor
public enum MeetingPreviewData {
    /// Adds a few sample meetings to a context: the first one is fully enhanced (summary,
    /// action items, speaker-labelled transcript), the others are plain recordings.
    public static func insertSampleMeetings(into context: ModelContext) {
        let samples: [(String, Double, [String], String, String, [ActionItem])] = [
            (
                "Product weekly",
                -3_600,
                ["Ana", "Ben", "Chi"],
                sampleTranscript,
                sampleScratchpad,
                [
                    ActionItem(text: "Finish the migration notes", owner: "Ben", due: "today"),
                    ActionItem(text: "Send the beta build to the test group", owner: "Ben", due: "Thursday"),
                    ActionItem(text: "Write the release notes", owner: "Ana", due: "Friday"),
                    ActionItem(text: "Book the App Store review slot", owner: "Chi", due: nil)
                ]
            ),
            (
                "Design review",
                -86_400 - 14_400,
                ["Ana", "Dee"],
                "Dee walked through the new navigation. The team liked the simpler tab bar. One question is still open about the empty states on iPad.",
                "Remember to send Dee the icon grid.",
                [
                    ActionItem(text: "Share the icon grid with Dee", owner: "Ana", due: nil)
                ]
            ),
            (
                "1:1 with Sam",
                -3 * 86_400 - 7_200,
                ["Sam"],
                "Sam is happy with the new on-call rotation. Wants to pick up the accessibility audit next sprint.",
                "",
                []
            )
        ]

        for (index, sample) in samples.enumerated() {
            let meeting = Meeting(
                title: sample.0,
                startedAt: Date().addingTimeInterval(sample.1),
                duration: index == 0 ? 1_535 : 1_240 + Double(index) * 300,
                scratchpad: sample.4,
                transcript: sample.3,
                attendeeNames: sample.2
            )
            if index == 0 {
                meeting.summaryJSON = sampleSummaryJSON
                meeting.speakerLabels = sampleSpeakerLabels
            }
            context.insert(meeting)

            for (itemIndex, item) in sample.5.enumerated() {
                context.insert(
                    ActionItemRecord(
                        meetingID: meeting.id,
                        text: item.text,
                        owner: item.owner,
                        due: item.due.flatMap { DueFormatter.date(from: $0) },
                        isDone: index == 0 && item.owner == "Chi",
                        createdAt: meeting.startedAt.addingTimeInterval(Double(itemIndex))
                    )
                )
            }
            if index == 0 {
                for (segmentIndex, segment) in sampleSegments.enumerated() {
                    context.insert(
                        TranscriptSegment(
                            meetingID: meeting.id,
                            index: segmentIndex,
                            text: segment.text,
                            startTime: segment.start,
                            endTime: segment.end,
                            speakerKey: segment.key
                        )
                    )
                }
            }
        }
        try? context.save()
    }

    /// The enhanced meeting inserted by `insertSampleMeetings`, if any.
    public static func sampleMeeting(in context: ModelContext) -> Meeting? {
        var descriptor = FetchDescriptor<Meeting>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// An in-memory container with the sample meetings, for previews.
    public static func previewContainer(empty: Bool = false) -> ModelContainer {
        // A preview with no store would show nothing; crashing here points at the schema.
        let container = try! MeetingNotesStore.modelContainer(inMemory: true) // swiftlint:disable:this force_try
        if !empty {
            insertSampleMeetings(into: container.mainContext)
        }
        return container
    }

    /// The sample summary stored on the first meeting.
    public static let sampleSummary = MeetingSummary(
        title: "Product weekly",
        summary: "The beta build is done and the App Store review is booked for Friday. Ben finishes the migration notes today; Ana owns the release notes. The team agreed to ship the beta on Friday and to send the test group a build on Thursday.",
        keyPoints: [
            "Beta build passed the release checklist",
            "App Store review slot is booked for Friday",
            "Migration notes are the last open item before the test group build"
        ],
        decisions: [
            "Ship the beta on Friday",
            "Send the test group a build on Thursday"
        ],
        actionItems: [
            ActionItem(text: "Finish the migration notes", owner: "Ben", due: "today"),
            ActionItem(text: "Send the beta build to the test group", owner: "Ben", due: "Thursday"),
            ActionItem(text: "Write the release notes", owner: "Ana", due: "Friday"),
            ActionItem(text: "Book the App Store review slot", owner: "Chi", due: nil)
        ],
        followUpQuestions: [
            "Do the iPad empty states ship with the beta or after?"
        ]
    )

    static var sampleSummaryJSON: String? {
        guard let data = try? JSONEncoder().encode(sampleSummary) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static let sampleSpeakerLabels: [SpeakerLabel] = [
        SpeakerLabel(key: "s0", name: "Ana", seconds: 420),
        SpeakerLabel(key: "s1", name: SpeakerLabel.youName, seconds: 610),
        SpeakerLabel(key: "s2", name: "Chi", seconds: 300)
    ]

    static let sampleSegments: [(key: String, text: String, start: TimeInterval, end: TimeInterval)] = [
        ("s0", "Let's start with where the release checklist stands. Anything still red?", 2, 9),
        ("s1", "The beta build is done. Every item on the checklist is green and the App Store review is booked for Friday.", 10, 24),
        ("s2", "What about the migration notes? Support asked for them twice.", 25, 31),
        ("s1", "I'll finish them today, they only need the last two schema changes.", 32, 40),
        ("s0", "Good. Then we ship the beta on Friday and the test group gets a build on Thursday.", 41, 52)
    ]

    /// Transcript rows for previews that have no store.
    static var sampleTranscriptRows: [TranscriptRowModel] {
        sampleSegments.enumerated().map { index, segment in
            TranscriptRowModel(
                id: index,
                speakerKey: segment.key,
                name: sampleSpeakerLabels.first { $0.key == segment.key }?.name,
                start: segment.start,
                text: segment.text
            )
        }
    }

    /// Today's events for previews.
    public static func sampleEvents(now: Date = Date()) -> [CalendarEventInfo] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .minute, value: 25, to: now) ?? now
        let end = calendar.date(byAdding: .minute, value: 55, to: start) ?? start
        return [
            CalendarEventInfo(
                id: "sample-event",
                title: "Roadmap sync",
                start: start,
                end: end,
                attendeeNames: ["Ana", "Ben", "Chi", "Dee"],
                location: "Room 4"
            )
        ]
    }

    /// The recording in progress shown by the home previews: 21 minutes in, mid-sentence.
    static var liveRecording: LiveRecordingState {
        LiveRecordingState(
            elapsed: 1_262,
            title: "Roadmap sync",
            lastLine: "The migration notes go out today.",
            levels: waveform(phase: 1.3),
            attendees: ["Ana", "Ben", "Chi", "Dee"]
        )
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

    /// The theme previews use: MorningVault's Warm palette, resolved for one color scheme
    /// (the package has no dynamic color providers of its own).
    public static func warmTheme(_ scheme: ColorScheme) -> MeetingsTheme {
        let dark = scheme == .dark
        return MeetingsTheme(
            background: Color(hex: dark ? 0x17141B : 0xF6F2EC),
            surface: Color(hex: dark ? 0x211C23 : 0xFFFCF7),
            accent: Color(hex: dark ? 0xE2A060 : 0xB85E24),
            negative: Color(hex: dark ? 0xF07870 : 0xB83A3A),
            cardRadius: 20,
            inkPrimary: Color(hex: dark ? 0xF2ECE4 : 0x1F1A17),
            inkSecondary: Color(hex: dark ? 0xB3A99E : 0x6B625B),
            hairline: Color(hex: dark ? 0xF2ECE4 : 0x1F1A17).opacity(dark ? 0.14 : 0.10),
            positive: Color(hex: dark ? 0x8CCB9A : 0x3B7A4A),
            onAccent: Color(hex: dark ? 0x1F1A17 : 0xFFFFFF)
        )
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
