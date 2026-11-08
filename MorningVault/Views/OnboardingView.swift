import SwiftUI

struct OnboardingView: View {
    @AppStorage("user_name") private var userName: String = ""
    @AppStorage("has_completed_onboarding") private var hasCompletedOnboarding = false

    @State private var currentPage = 0
    private let pageCount = 4

    var body: some View {
        ZStack {
            Color.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    OnboardingNameStep()
                        .tag(0)

                    OnboardingSourcesStep()
                        .tag(1)

                    OnboardingMeetingsStep()
                        .tag(2)

                    OnboardingSymbolsStep(onComplete: completeOnboarding)
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)

                // Every page advances with a real button; swiping still works.
                VStack(spacing: 14) {
                    OnboardingPageIndicator(total: pageCount, current: currentPage)
                    if currentPage < pageCount - 1 {
                        Button {
                            withAnimation(.easeInOut) { currentPage += 1 }
                        } label: {
                            Text("Next")
                                .font(.headline)
                                .foregroundStyle(Color.onAccent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.appAccentColor, in: RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Goes to the next step")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 24)
                .background(Color.backgroundColor)
            }
        }
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
    }
}

// MARK: - Page Indicator

struct OnboardingPageIndicator: View {
    let total: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Color.appAccentColor : Color.inkSecondary.opacity(0.5))
                    .frame(width: index == current ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: current)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(total)")
    }
}

#Preview {
    OnboardingView()
}
