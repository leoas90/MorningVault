import SwiftUI

struct OnboardingNameStep: View {
    @AppStorage("user_name") private var userName: String = ""
    @FocusState private var isTextFieldFocused: Bool

    private let suggestedNames = ["Alex", "Jordan", "Morgan", "Taylor", "Casey", "Riley"]

    @State private var iconOffset: CGFloat = 0
    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon with gentle float animation
            Image(systemName: "hand.wave.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.accentColor)
                .offset(y: iconOffset)
                .onAppear {
                    guard !UIAccessibility.isReduceMotionEnabled else { return }
                    withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                        iconOffset = -8
                    }
                }

            // Title with slide-up entrance
            Text("Good Morning")
                .font(.largeTitle.bold())
                .padding(.bottom, 8)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 16)

            Text("What should we call you?")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.bottom, 40)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 16)

            // Text field with scale entrance
            VStack(spacing: 16) {
                TextField("Your first name", text: $userName)
                    .font(.title2)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.words)
                    .padding(.vertical, 14)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .focused($isTextFieldFocused)
                    .scaleEffect(hasAppeared ? 1 : 0.95)
                    .opacity(hasAppeared ? 1 : 0)

                // Suggestion chips with staggered bounce-in
                if userName.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(suggestedNames.enumerated()), id: \.element) { index, name in
                            Button {
                                userName = name
                            } label: {
                                Text(name)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Color.accentColor.opacity(0.1))
                                    .clipShape(Capsule())
                                    .scaleEffect(hasAppeared ? 1 : 0)
                            }
                            .animation(
                                .spring(response: 0.35, dampingFraction: 0.7)
                                    .delay(Double(index) * 0.08 + 0.3),
                                value: hasAppeared
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)

            // Navigation hint
            Text("Tap a suggestion or enter your name to continue")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 24)
                .opacity(hasAppeared ? 1 : 0)

            // Page indicator
            OnboardingPageIndicator(total: 3, current: 0)
                .padding(.bottom, 16)

            Spacer()
        }
        .dismissKeyboardOnTap()
        .onTapGesture {
            isTextFieldFocused = false
        }
        .onAppear {
            guard !UIAccessibility.isReduceMotionEnabled else {
                hasAppeared = true
                return
            }
            withAnimation(.easeOut(duration: 0.5)) {
                hasAppeared = true
            }
        }
    }
}

#Preview {
    OnboardingNameStep()
}