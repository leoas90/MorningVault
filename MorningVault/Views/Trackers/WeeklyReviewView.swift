import SwiftUI

// MARK: - Weekly checklist review
//
// Two surfaces over `ChecklistWeeklyReview`: the Monday "Your week" block in the Brief and
// the full screen under Settings > Trackers > Household. Editorial rules apply: eyebrow plus
// hairline rows, no rounded-rectangle containers, sentence case, SF Symbols only.

/// Monday's block in the Brief: last week in a few hairline rows.
struct WeeklyReviewBriefBlock: View {
    @ObservedObject var model: ChecklistViewModel

    var body: some View {
        let review = model.lastWeekReview
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: "Your week")
                Spacer()
                Text(review.countText)
                    .font(.metaText.monospacedDigit())
                    .foregroundStyle(Color.inkSecondary)
            }
            .padding(.bottom, 6)

            if let delta = review.deltaText {
                Text(delta)
                    .font(.secondaryText)
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.bottom, 8)
            }

            WeeklyReviewLists(review: review, compact: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your week. \(review.countText).")
    }
}

/// Achieved and work-on, shared by the Brief block and the screen.
struct WeeklyReviewLists: View {
    let review: ChecklistWeeklyReview
    /// The Brief block shows fewer achieved rows than the screen.
    var compact: Bool = false

    private var achievedShown: [ChecklistWeeklyReview.ItemReview] {
        compact ? Array(review.achieved.prefix(3)) : review.achieved
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !achievedShown.isEmpty {
                Text("Achieved")
                    .font(.metaText)
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.top, 4)
                    .padding(.bottom, 2)
                    .accessibilityAddTraits(.isHeader)
                ForEach(achievedShown) { item in
                    Hairline()
                    achievedRow(item)
                }
            }

            if !review.workOn.isEmpty {
                Text("Work on")
                    .font(.metaText)
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.top, 12)
                    .padding(.bottom, 2)
                    .accessibilityAddTraits(.isHeader)
                ForEach(review.workOn) { entry in
                    Hairline()
                    workOnRow(entry)
                }
            }

            if achievedShown.isEmpty, review.workOn.isEmpty, review.hasAnythingScheduled {
                Hairline()
                Text("A middling week. Nothing stood out either way.")
                    .font(.bodyText)
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.vertical, 10)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let streak = review.itemWithLongestStreak, streak.streak >= 3 {
                Hairline()
                metaRow(icon: "flame", text: "\(streak.title): \(streak.streak) day streak")
            }

            if !review.members.isEmpty {
                Hairline()
                metaRow(icon: "person.2", text: memberText(review.members))
            }
        }
    }

    private func achievedRow(_ item: ChecklistWeeklyReview.ItemReview) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.appAccentColor)
                .frame(width: 16)
            Text(item.title)
                .font(.bodyText)
                .foregroundStyle(Color.inkPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(item.isPerfect ? "every time" : item.countText)
                .font(.metaText.monospacedDigit())
                .foregroundStyle(Color.inkSecondary)
                .lineLimit(1)
        }
        .frame(minHeight: 40)
        .accessibilityElement(children: .combine)
    }

    private func workOnRow(_ entry: ChecklistWeeklyReview.WorkOnItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.up.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.inkSecondary)
                .frame(width: 16)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.item.title)
                    .font(.bodyText)
                    .foregroundStyle(Color.inkPrimary)
                    .lineLimit(1)
                Text(entry.reason)
                    .font(.metaText)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private func metaRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.inkSecondary)
                .frame(width: 16)
            Text(text)
                .font(.metaText)
                .foregroundStyle(Color.inkSecondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 36)
        .accessibilityElement(children: .combine)
    }

    private func memberText(_ members: [ChecklistWeeklyReview.MemberLine]) -> String {
        members.prefix(4).map { "\($0.name) \($0.done)" }.joined(separator: ", ")
    }
}

// MARK: - Screen

/// Settings > Trackers > Household > Weekly review: last full week and the week so far.
struct WeeklyReviewView: View {
    @ObservedObject var model: ChecklistViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Grid4.section) {
                week(model.lastWeekReview, title: "Last week")
                week(model.thisWeekReview, title: "This week so far")
            }
            .padding(.horizontal, Grid4.margin)
            .padding(.vertical, 20)
        }
        .background(Color.backgroundColor.ignoresSafeArea())
        .navigationTitle("Weekly review")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }

    @ViewBuilder
    private func week(_ review: ChecklistWeeklyReview, title: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: title)
                Spacer()
                if review.hasAnythingScheduled {
                    Text(review.countText)
                        .font(.metaText.monospacedDigit())
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            Text(review.rangeText(calendar: model.calendar))
                .font(.metaText)
                .foregroundStyle(Color.inkSecondary)
                .padding(.top, 2)

            if !review.hasAnythingScheduled {
                Text("Nothing was scheduled this week.")
                    .font(.bodyText)
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.top, 10)
            } else {
                if let delta = review.deltaText {
                    Text(delta)
                        .font(.secondaryText)
                        .foregroundStyle(Color.inkSecondary)
                        .padding(.top, 6)
                }
                WeeklyReviewLists(review: review)
                    .padding(.top, 6)

                Text("Items")
                    .font(.metaText)
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.top, 16)
                    .padding(.bottom, 2)
                    .accessibilityAddTraits(.isHeader)
                ForEach(review.items) { item in
                    Hairline()
                    WeeklyReviewItemRow(item: item)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One item row on the screen: title, done of scheduled, and a seven-dot week.
struct WeeklyReviewItemRow: View {
    let item: ChecklistWeeklyReview.ItemReview

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.inkSecondary)
                .frame(width: 18)
            Text(item.title)
                .font(.bodyText)
                .foregroundStyle(Color.inkPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(item.countText)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.inkSecondary)
                .frame(width: 56, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            WeekDotsRow(days: item.days)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.countText)")
    }
}

/// Monday to Sunday as seven dots: done filled, partial half, missed a hairline ring,
/// skipped a secondary ring, not scheduled nothing at all.
struct WeekDotsRow: View {
    let days: [ChecklistWeeklyReview.DayState]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                dot(day)
            }
        }
        .frame(width: 7 * 5 + 6 * 3, alignment: .trailing)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func dot(_ day: ChecklistWeeklyReview.DayState) -> some View {
        switch day {
        case .done:
            Circle().fill(Color.inkPrimary).frame(width: 5, height: 5)
        case .partial:
            Circle().fill(Color.inkSecondary).frame(width: 5, height: 5)
        case .missed:
            Circle().strokeBorder(Color.inkSecondary.opacity(0.7), lineWidth: 1).frame(width: 5, height: 5)
        case .skipped:
            Rectangle().fill(Color.inkSecondary).frame(width: 5, height: 1)
        case .notScheduled:
            Color.clear.frame(width: 5, height: 5)
        }
    }
}

// MARK: - Previews

/// Monday 9 Nov 2026, 09:00 UTC, so the preview block always has a finished week behind it.
private let weeklyReviewPreviewNow = Date(timeIntervalSince1970: 1_794_214_800)

#Preview("Your week, Brief block") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    return ScrollView {
        WeeklyReviewBriefBlock(model: ChecklistViewModel.preview(now: weeklyReviewPreviewNow))
            .padding(20)
    }
    .background(Color.backgroundColor)
}

#Preview("Weekly review screen") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    return NavigationStack {
        WeeklyReviewView(model: ChecklistViewModel.preview(now: weeklyReviewPreviewNow))
    }
}

#Preview("Weekly review screen, dark") {
    ThemeStore.shared.themeRaw = AppTheme.dark.rawValue
    return NavigationStack {
        WeeklyReviewView(model: ChecklistViewModel.preview(now: weeklyReviewPreviewNow))
    }
    .preferredColorScheme(.dark)
}
