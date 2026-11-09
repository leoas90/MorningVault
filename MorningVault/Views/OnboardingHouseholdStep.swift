import SwiftUI

/// Onboarding, after Sources: "Anything you do every morning?" The same starter chips as the
/// editor; tapping one adds it and turns the household checklist on. Skipping is fine, the
/// step never blocks Next. Role-based copy, no names.
struct OnboardingHouseholdStep: View {
    @ObservedObject var model: ChecklistViewModel
    @AppStorage(BriefSectionPrefs.householdEnabledKey) private var householdEnabled = false
    @State private var added: Set<String> = []
    @State private var hasAppeared = false

    init(model: ChecklistViewModel = .shared) {
        self.model = model
    }

    private var templates: [ChecklistTemplate] {
        ChecklistTemplate.all + ChecklistTemplate.timeWithChildren(members: model.members)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(Color.appAccentColor)
                    .padding(.bottom, 4)
                Text("Anything you do every morning?")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.inkPrimary)
                    .multilineTextAlignment(.center)
                Text("A short household list in the Brief: lunches, meds, a walk. Tap to add; skip if not for you.")
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 48)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : -12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FlowLayout(spacing: 8, alignment: .leading) {
                        ForEach(templates) { template in
                            let isAdded = added.contains(template.id)
                            ChoiceChip(title: template.title, systemImage: isAdded ? "checkmark" : "plus", isSelected: isAdded) {
                                Task { await add(template) }
                            }
                            .disabled(isAdded || (!model.canAddItem && !isAdded))
                        }
                    }
                    Text(added.isEmpty
                         ? "Everything can be changed later under Settings › Trackers."
                         : "\(added.count) added. Edit, reorder or remove them under Settings › Trackers.")
                        .font(.metaText)
                        .foregroundStyle(Color.inkSecondary)
                }
                .padding(.horizontal, 20)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 16)
            }
        }
        .task { await model.load() }
        .onAppear {
            guard !UIAccessibility.isReduceMotionEnabled else {
                hasAppeared = true
                return
            }
            withAnimation(.easeOut(duration: 0.4)) {
                hasAppeared = true
            }
        }
    }

    private func add(_ template: ChecklistTemplate) async {
        let child = model.members.first { $0.role == .child && template.title == "Time with \($0.name)" }
        if await model.save(template.makeItem(order: model.nextOrder, forMember: child?.id)) {
            added.insert(template.id)
            if !householdEnabled {
                householdEnabled = true
                BriefSectionPrefs.mirrorToAppGroup()
            }
        }
    }
}

#Preview("Onboarding household") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    return OnboardingHouseholdStep(model: ChecklistViewModel.previewEmpty())
        .background(Color.backgroundColor)
}
