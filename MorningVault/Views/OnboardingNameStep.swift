import SwiftUI

struct OnboardingNameStep: View {
    @AppStorage("user_name") private var userName: String = ""
    @FocusState private var isTextFieldFocused: Bool

    private let suggestedNames: [String] = ["Alex", "Jordan", "Morgan", "Taylor", "Casey", "Riley"]

    @State private var hasAppeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Masthead on the time-of-day wash (same as the Brief hero).
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "Welcome", color: Color.inkSecondary)
                    Text("Good morning.")
                        .font(.display(40))
                        .foregroundStyle(Color.inkPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text("Your briefing, written each morning from your calendar, weather, health and markets. What should we call you?")
                        .font(.lede)
                        .lineSpacing(4)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 28)
                .background {
                    ZStack(alignment: .bottom) {
                        TimeOfDayGradient(hour: 7)
                        LinearGradient(colors: [.clear, Color.backgroundColor], startPoint: .center, endPoint: .bottom)
                            .frame(height: 80)
                    }
                    .ignoresSafeArea(edges: .top)
                }
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 8)

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "Your name")
                        TextField("First name", text: $userName, prompt: Text("First name").foregroundStyle(Color.inkSecondary))
                            .font(.display(24, weight: .regular))
                            .foregroundStyle(Color.inkPrimary)
                            .textInputAutocapitalization(.words)
                            .textContentType(.givenName)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color.inkPrimary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(isTextFieldFocused ? Color.appAccentColor : Color.inkPrimary.opacity(0.14), lineWidth: isTextFieldFocused ? 1.5 : 1)
                            )
                            .focused($isTextFieldFocused)

                        if userName.isEmpty {
                            FlowLayout(spacing: 8, alignment: .leading) {
                                ForEach(suggestedNames, id: \.self) { name in
                                    Button {
                                        userName = name
                                    } label: {
                                        Text(name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(Color.appAccentColor)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 11)
                                            .background(Color.appAccentColor.opacity(0.12), in: Capsule())
                                            .overlay(Capsule().strokeBorder(Color.appAccentColor.opacity(0.25), lineWidth: 1))
                                            .fixedSize()
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Use the name \(name)")
                                }
                            }
                            .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .editorialCard()

                    VStack(alignment: .leading, spacing: 6) {
                        Label("Your name stays on this device", systemImage: "lock.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color.inkPrimary)
                        Text("Tap a suggestion or type a name, then tap Next. You can leave it blank.")
                            .font(.footnote)
                            .foregroundStyle(Color.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 18)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 8)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.backgroundColor)
        .animation(.easeInOut(duration: 0.2), value: userName.isEmpty)
        .onTapGesture {
            isTextFieldFocused = false
        }
        .onAppear {
            guard !UIAccessibility.isReduceMotionEnabled else {
                hasAppeared = true
                return
            }
            withAnimation(.easeOut(duration: 0.45)) {
                hasAppeared = true
            }
        }
    }
}

#Preview("Name step") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    return OnboardingView()
}
