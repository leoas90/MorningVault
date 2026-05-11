import SwiftUI

/// Smart Calendar view with conflict detection and action items.
struct SmartCalendarView: View {
    let events: [CalendarEvent]
    @State private var summary: CalendarDaySummary?
    @State private var showConflicts = false
    @State private var showActionItems = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let summary = summary {
                    // Summary header
                    summaryHeader(summary)

                    // Conflicts section
                    if summary.hasConflicts {
                        conflictSection(summary.conflicts)
                    }

                    // Action items section
                    if !summary.actionItems.isEmpty {
                        actionItemsSection(summary.actionItems)
                    }

                    // Free time
                    if summary.hasFreeTime {
                        freeTimeSection(summary.freeBlocks)
                    }

                    // Timeline
                    timelineSection
                } else {
                    Text("Loading calendar...")
                        .foregroundStyle(Color.warmTextSecondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(Color.warmBackground.ignoresSafeArea())
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.large)
        .task {
            loadSummary()
        }
    }

    // MARK: - Summary Header

    private func summaryHeader(_ summary: CalendarDaySummary) -> some View {
        HStack(spacing: 16) {
            CalendarStatCard(
                icon: "calendar",
                value: "\(summary.totalEvents)",
                label: "Events",
                color: .warmPrimaryAccent
            )
            CalendarStatCard(
                icon: summary.hasConflicts ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                value: "\(summary.conflictCount)",
                label: "Conflicts",
                color: summary.hasConflicts ? .red : .green
            )
            CalendarStatCard(
                icon: "checklist",
                value: "\(summary.actionItemCount)",
                label: "Tasks",
                color: Color.warmAISummary
            )
            CalendarStatCard(
                icon: "cup.and.saucer.fill",
                value: "\(summary.freeBlocks.count)",
                label: "Free",
                color: .blue
            )
        }
    }

    // MARK: - Conflict Section

    private func conflictSection(_ conflicts: [CalendarConflict]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Schedule Conflicts")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.warmTextPrimary)
                Spacer()
                Button {
                    withAnimation { showConflicts.toggle() }
                } label: {
                    Image(systemName: showConflicts ? "chevron.up" : "chevron.down")
                        .foregroundStyle(Color.warmTextSecondary)
                }
            }

            if showConflicts {
                ForEach(conflicts) { conflict in
                    ConflictCard(conflict: conflict)
                }
            }
        }
        .padding(16)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Action Items Section

    private func actionItemsSection(_ items: [ActionItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checklist")
                    .foregroundStyle(Color.warmAISummary)
                Text("Action Items")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.warmTextPrimary)
                Spacer()
                Button {
                    withAnimation { showActionItems.toggle() }
                } label: {
                    Image(systemName: showActionItems ? "chevron.up" : "chevron.down")
                        .foregroundStyle(Color.warmTextSecondary)
                }
            }

            if showActionItems {
                ForEach(items) { item in
                    ActionItemRow(item: item)
                }
            }
        }
        .padding(16)
        .background(Color.warmAISummary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Free Time Section

    private func freeTimeSection(_ blocks: [FreeTimeBlock]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "cup.and.saucer.fill")
                    .foregroundStyle(.blue)
                Text("Free Time")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.warmTextPrimary)
            }

            ForEach(blocks) { block in
                HStack {
                    Circle()
                        .fill(Color.blue.opacity(0.3))
                        .frame(width: 8, height: 8)
                    Text(block.formatted)
                        .font(.subheadline)
                        .foregroundStyle(Color.warmTextSecondary)
                    Spacer()
                    Text("\(block.minutesFree / 60)h")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(16)
        .background(Color.blue.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Timeline

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Schedule")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.warmTextPrimary)

            ForEach(sortedTimedEvents, id: \.id) { event in
                TimelineEventRow(event: event, hasConflict: hasConflict(event))
            }
        }
    }

    private var sortedTimedEvents: [CalendarEvent] {
        events.filter { !$0.isAllDay }.sorted { $0.startDate < $1.startDate }
    }

    private func hasConflict(_ event: CalendarEvent) -> Bool {
        guard let summary = summary else { return false }
        return summary.conflicts.contains { $0.eventA.id == event.id || $0.eventB.id == event.id }
    }

    // MARK: - Helpers

    private func loadSummary() {
        summary = CalendarService.shared.generateDaySummary(events: events)
    }
}

// MARK: - Stat Card

struct CalendarStatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Color.warmTextPrimary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.warmTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Conflict Card

struct ConflictCard: View {
    let conflict: CalendarConflict

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "arrow.triangle.merge")
                    .foregroundStyle(.orange)
                Text(conflict.eventA.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.warmTextPrimary)
            }
            HStack {
                Image(systemName: "arrow.triangle.swap")
                    .foregroundStyle(.orange)
                Text(conflict.eventB.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.warmTextPrimary)
            }
            HStack {
                Image(systemName: "clock")
                    .foregroundStyle(.orange)
                Text("\(conflict.overlapMinutes) minutes overlapping")
                    .font(.caption)
                    .foregroundStyle(Color.warmTextSecondary)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Action Item Row

struct ActionItemRow: View {
    let item: ActionItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.priorityIcon)
                .foregroundStyle(priorityColor)
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.description)
                    .font(.subheadline)
                    .foregroundStyle(Color.warmTextPrimary)
                    .lineLimit(2)
                Text("From: \(item.sourceEvent)")
                    .font(.caption2)
                    .foregroundStyle(Color.warmTextSecondary)
            }

            Spacer()

            if item.dueTime > Date() {
                Text(item.dueTime, style: .time)
                    .font(.caption)
                    .foregroundStyle(Color.warmTextSecondary)
            }
        }
        .padding(10)
        .background(priorityColor.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var priorityColor: Color {
        switch item.priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .green
        }
    }
}

// MARK: - Timeline Event Row

struct TimelineEventRow: View {
    let event: CalendarEvent
    let hasConflict: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Time column
            VStack(alignment: .trailing, spacing: 2) {
                Text(event.startDate, style: .time)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.warmTextPrimary)
                Text(event.durationFormatted)
                    .font(.caption2)
                    .foregroundStyle(Color.warmTextSecondary)
            }
            .frame(width: 52)

            // Timeline dot
            VStack(spacing: 0) {
                Circle()
                    .fill(hasConflict ? Color.orange : Color.warmPrimaryAccent)
                    .frame(width: 10, height: 10)
                Rectangle()
                    .fill(Color.warmDivider.opacity(0.5))
                    .frame(width: 2)
            }

            // Event details
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.warmTextPrimary)
                        .lineLimit(1)
                    if hasConflict {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                if let location = event.location, !location.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin")
                            .font(.caption2)
                        Text(location)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color.warmTextSecondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}