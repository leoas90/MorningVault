import SwiftUI

struct OnboardingSourcesStep: View {
    @State private var selectedSources: Set<NewsSource> = []
    @State private var hasAppeared = false
    @AppStorage(WaterSettings.Key.enabled) private var waterEnabled = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Stay informed")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.inkPrimary)
                Text("Choose your news sources. You can change them later in Settings › Data sources › Edit sources.")
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 48)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : -12)

            // Source list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(NewsSource.allCases.enumerated()), id: \.element.id) { index, source in
                        SourceSelectionRow(
                            name: source.displayName,
                            description: source.description,
                            icon: source.icon,
                            isSelected: selectedSources.contains(source),
                            delay: Double(index) * 0.06
                        ) {
                            toggleSource(source)
                        }
                    }

                    // Trackers: water is off by default; the goal sheet comes later in Settings.
                    SourceSelectionRow(
                        name: "Water",
                        description: "Track glasses, see a row in the Brief. Saved to Health.",
                        icon: "drop",
                        isSelected: waterEnabled,
                        delay: Double(NewsSource.allCases.count) * 0.06
                    ) {
                        waterEnabled.toggle()
                        WaterSettings.mirrorToAppGroup()
                        BriefSectionPrefs.mirrorToAppGroup()
                        if waterEnabled { Task { await WaterViewModel.shared.trackerEnabled() } }
                    }
                }
                .padding(.horizontal, 16)
            }

        }
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

    private func toggleSource(_ source: NewsSource) {
        if selectedSources.contains(source) {
            selectedSources.remove(source)
        } else {
            selectedSources.insert(source)
        }
        saveSources()
    }

    private func saveSources() {
        saveSelectedSources(Array(selectedSources))
    }
}

// MARK: - Source Selection Row

struct SourceSelectionRow: View {
    let name: String
    let description: String
    let icon: String
    let isSelected: Bool
    let delay: Double
    let onTap: () -> Void

    @State private var hasAppeared = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.warmPrimaryAccent : .secondary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.warmPrimaryAccent : .secondary)
                    .scaleEffect(isSelected ? 1 : 0.85)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color.warmSurface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 16)
        }
        .buttonStyle(.plain)
        .onAppear {
            guard !UIAccessibility.isReduceMotionEnabled else {
                hasAppeared = true
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeOut(duration: 0.3)) {
                    hasAppeared = true
                }
            }
        }
    }
}

#Preview {
    NavigationStack { OnboardingSourcesStep() }
}