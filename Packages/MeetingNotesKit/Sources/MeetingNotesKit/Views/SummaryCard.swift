import SwiftUI

/// Shows the summary the on-device model produced.
struct SummaryCard: View {
    let summary: MeetingSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.tint)
                Text(summary.title.isEmpty ? "Meeting notes" : summary.title)
                    .font(.headline)
            }

            Text(summary.summary)
                .font(.subheadline)
                .foregroundStyle(.primary)

            if !summary.keyPoints.isEmpty {
                block(title: "Key points", symbol: "list.bullet") {
                    ForEach(summary.keyPoints, id: \.self) { point in
                        BulletRow(text: point)
                    }
                }
            }

            if !summary.decisions.isEmpty {
                block(title: "Decisions", symbol: "checkmark.seal") {
                    ForEach(summary.decisions, id: \.self) { decision in
                        BulletRow(text: decision)
                    }
                }
            }

            if !summary.actionItems.isEmpty {
                block(title: "Action items", symbol: "checklist") {
                    ForEach(Array(summary.actionItems.enumerated()), id: \.offset) { _, item in
                        BulletRow(text: itemDetail(item))
                    }
                }
            }

            if !summary.followUpQuestions.isEmpty {
                block(title: "Open questions", symbol: "questionmark.circle") {
                    ForEach(summary.followUpQuestions, id: \.self) { question in
                        BulletRow(text: question)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func block<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title, systemImage: symbol)
            content()
        }
    }

    private func itemDetail(_ item: ActionItem) -> String {
        var text = item.text
        var extras: [String] = []
        if let owner = item.owner, !owner.isEmpty { extras.append(owner) }
        if let due = item.due, !due.isEmpty { extras.append("due \(due)") }
        if !extras.isEmpty {
            text += " — " + extras.joined(separator: ", ")
        }
        return text
    }
}

/// A single bullet line.
struct BulletRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 5, height: 5)
            Text(text)
                .font(.subheadline)
            Spacer(minLength: 0)
        }
    }
}
