import SwiftUI

struct OnboardingNameStep: View {
    @AppStorage("user_name") private var userName: String = ""
    @FocusState private var isTextFieldFocused: Bool

    private let suggestedNames: [String] = ["Alex", "Jordan", "Morgan", "Taylor", "Casey", "Riley"]

    @State private var hasAppeared = false
    @Environment(\.colorScheme) private var colorScheme

    /// Ink on the light dawn sky, white on the dark one.
    private var sceneInk: Color {
        SkyStyle.resolve(hour: 7, condition: nil, colorScheme: colorScheme).usesLightText ? Color.white : Color.inkPrimary
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // The sky scene (time of day only, a clear morning) with the greeting over it —
                // the same object the Brief opens with.
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "Welcome", color: sceneInk.opacity(0.7))
                    Spacer(minLength: 24)
                    Text("Good morning.")
                        .font(.display(40, weight: .medium))
                        .foregroundStyle(sceneInk)
                        .accessibilityAddTraits(.isHeader)
                    Text("Your briefing, written each morning from your calendar, weather, health and markets. What should we call you?")
                        .font(.lede)
                        .lineSpacing(5)
                        .foregroundStyle(sceneInk.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 300, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 32)
                .frame(minHeight: 300, alignment: .bottom)
                .background {
                    ZStack(alignment: .bottom) {
                        SkyScene(hour: 7, condition: nil)
                        LinearGradient(colors: [Color.backgroundColor.opacity(0), Color.backgroundColor], startPoint: .top, endPoint: .bottom)
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
                            .font(.system(size: 22, weight: .regular))
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
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(Color.inkPrimary)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 11)
                                            .background(Color.surfaceColor, in: Capsule())
                                            .overlay(Capsule().strokeBorder(Color.inkPrimary.opacity(0.18), lineWidth: 1))
                                            .fixedSize()
                                    }
                                    .buttonStyle(.pressable)
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
