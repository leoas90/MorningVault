import MeetingNotesKit
import SwiftUI

/// Collapsible card showing meeting prep: title, time, talking points, and past positions.
/// Collapsed by default, expands on tap.
struct MeetingPrepCard: View {
    @Binding var prep: MeetingPrep

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header — always visible
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    prep.isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: "Meeting prep")

                        Text(prep.meetingTitle)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.warmTextPrimary)
                            .lineLimit(prep.isExpanded ? 3 : 2)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text(prep.formattedStartTime)
                                .font(.caption)
                        }
                        .foregroundStyle(Color.warmTextSecondary)
                    }

                    Spacer()

                    // Expand/collapse chevron
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.warmTextSecondary)
                        .rotationEffect(.degrees(prep.isExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Meeting prep: \(prep.meetingTitle), \(prep.isExpanded ? "expanded" : "collapsed")")

            // Record: same flow as the Meetings tab and the widget — the router switches to
            // Meetings and starts the recording there, filed under this calendar event.
            // `prep.attendees` is a location proxy, so the Meetings home fills real attendees
            // from the event itself.
            if prep.startTime.timeIntervalSinceNow > -4 * 3600 {
                MeetingRecordButton(calendarEventID: prep.calendarEventID, title: prep.meetingTitle)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
            }

            // Expanded content
            if prep.isExpanded {
                Hairline()

                // Attendees
                if !prep.attendees.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow(text: "Attendees")
                        Text(prep.attendees.joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundStyle(Color.warmTextPrimary)
                    }
                }

                // Agenda
                if let agenda = prep.agenda, !agenda.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow(text: "Agenda")
                        Text(agenda)
                            .font(.subheadline)
                            .foregroundStyle(Color.warmTextPrimary)
                    }
                }

                // Talking Points
                if !prep.talkingPoints.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: "Talking points")

                        ForEach(prep.talkingPoints, id: \.self) { point in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(Color.warmPrimaryAccent)
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 5)
                                Text(point)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.warmTextPrimary)
                            }
                        }
                    }
                }

                // Past Positions
                if !prep.yourPastPositions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: "Your past positions")

                        ForEach(prep.yourPastPositions, id: \.self) { position in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "arrow.uturn.left")
                                    .font(.caption2)
                                    .foregroundStyle(Color.warmAISummary)
                                    .padding(.top, 3)
                                Text(position)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.warmTextPrimary)
                            }
                        }
                    }
                }

                // No data states
                if prep.talkingPoints.isEmpty && prep.yourPastPositions.isEmpty {
                    Text("No talking points yet — check back closer to your meeting.")
                        .font(.caption)
                        .foregroundStyle(Color.warmTextSecondary)
                        .italic()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .editorialCard()
    }
}

#Preview {
    MeetingPrepCard(prep: .constant(MeetingPrep(
        meetingTitle: "Q2 Planning Review",
        startTime: Date().addingTimeInterval(3600),
        attendees: ["Sarah Chen", "Mike Ross", "Emma Davis"],
        agenda: "Review Q1 results and align on Q2 priorities",
        talkingPoints: [
            "What's the projected growth for the new product line?",
            "How do we handle the budget reallocation request?",
            "Any risks from the supply chain issues we discussed last quarter?"
        ],
        yourPastPositions: [
            "Advocated for increasing marketing spend by 15% in Q1",
            "Pushed back on the timeline for the product launch"
        ],
        isExpanded: false
    )))
    .padding()
    .background(Color.warmBackground)
}