import SwiftUI

struct OnboardingNameStep: View {
    @AppStorage("user_name") private var userName: String = ""
    @FocusState private var isTextFieldFocused: Bool

    private let suggestedNames = ["Alex", "Jordan", "Morgan", "Taylor", "Casey", "Riley"]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            Image(systemName: "hand.wave.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 24)

            // Title
            Text("Good Morning")
                .font(.largeTitle.bold())
                .padding(.bottom, 8)

            Text("What should we call you?")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.bottom, 40)

            // Text field
            VStack(spacing: 16) {
                TextField("Your first name", text: $userName)
                    .font(.title2)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.words)
                    .padding(.vertical, 14)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .focused($isTextFieldFocused)

                // Suggestion chips
                if userName.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(suggestedNames, id: \.self) { name in
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
                            }
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

            // Page indicator
            OnboardingPageIndicator(total: 3, current: 0)
                .padding(.bottom, 16)

            Spacer()
        }
        .onTapGesture {
            // Tap anywhere to dismiss keyboard
            isTextFieldFocused = false
        }
    }
}

#Preview {
    OnboardingNameStep()
}