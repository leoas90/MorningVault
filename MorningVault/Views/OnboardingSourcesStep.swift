import SwiftUI

struct OnboardingSourcesStep: View {
    @State private var selectedSources: Set<NewsSource> = []
    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Stay Informed")
                    .font(.largeTitle.bold())
                Text("Choose your news sources. You can change these later.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
                }
                .padding(.horizontal, 16)
            }

            // Page indicator
            OnboardingPageIndicator(total: 3, current: 1)
                .padding(.vertical, 16)

            Spacer()
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
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .scaleEffect(isSelected ? 1 : 0.85)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
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