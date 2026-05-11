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
                    // Icon
                    Image(systemName: "person.2.wave.2")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.warmPrimaryAccent)
                        .frame(width: 32, height: 32)
                        .background(Color.warmPrimaryAccent.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Meeting Prep")
                            .font(.caption)
                            .foregroundStyle(Color.warmTextSecondary)
                            .textCase(.uppercase)

                        Text(prep.meetingTitle)
                            .font(.headline)
                            .foregroundStyle(Color.warmTextPrimary)
                            .lineLimit(prep.isExpanded ? 2 : 1)

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

            // Expanded content
            if prep.isExpanded {
                Divider()

                // Attendees
                if !prep.attendees.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ATTENDEES")
                            .font(.caption2)
                            .foregroundStyle(Color.warmTextSecondary)
                        Text(prep.attendees.joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundStyle(Color.warmTextPrimary)
                    }
                }

                // Agenda
                if let agenda = prep.agenda, !agenda.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AGENDA")
                            .font(.caption2)
                            .foregroundStyle(Color.warmTextSecondary)
                        Text(agenda)
                            .font(.subheadline)
                            .foregroundStyle(Color.warmTextPrimary)
                    }
                }

                // Talking Points
                if !prep.talkingPoints.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TALKING POINTS")
                            .font(.caption2)
                            .foregroundStyle(Color.warmTextSecondary)

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
                        Text("YOUR PAST POSITIONS")
                            .font(.caption2)
                            .foregroundStyle(Color.warmTextSecondary)

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
        .padding(16)
        .background(Color.warmCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.warmPrimaryAccent.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
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