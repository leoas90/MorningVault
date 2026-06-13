import SwiftUI
import Security

struct SettingsView: View {
    @AppStorage("briefing_time") private var briefingTimeSeconds: Double = 7 * 3600  // default 7 AM
    @AppStorage("health_enabled") private var healthEnabled = true
    @AppStorage("calendar_enabled") private var calendarEnabled = true
    @AppStorage("weather_enabled") private var weatherEnabled = true
    @AppStorage("headlines_enabled") private var headlinesEnabled = true
    @AppStorage("local_only") private var localOnly = false
    @AppStorage("theme") private var themeRaw: String = AppTheme.system.rawValue
    @AppStorage("appearance") private var appearanceRaw: String = "warm"
    @AppStorage("user_name") private var userName: String = ""
    @State private var showingPrivacyPolicy = false
    @State private var hasAppeared = false
    @FocusState private var isNameFieldFocused: Bool
    @State private var showingAPIKeyAlert = false
    @State private var apiKeySaveMessage: String = ""

    private let healthService = HealthKitService.shared
    private let calendarService = CalendarService.shared
    private let alarmService = AlarmService.shared

    private var currentTheme: AppTheme {
        get { AppTheme(rawValue: themeRaw) ?? .system }
        set { themeRaw = newValue.rawValue }
    }

    private var briefingTimeBinding: Binding<Date> {
        Binding(
            get: {
                let totalSeconds = Int(briefingTimeSeconds)
                let hour = totalSeconds / 3600
                let minute = totalSeconds % 3600 / 60
                return DateComponents(hour: hour, minute: minute).date ?? Date()
            },
            set: { newDate in
                let cal = Calendar.current
                let components = cal.dateComponents([.hour, .minute], from: newDate)
                let hour = components.hour ?? 7
                let minute = components.minute ?? 0
                briefingTimeSeconds = Double(hour * 3600 + minute * 60)
            }
        )
    }

    private var themeDescription: String {
        switch currentTheme {
        case .system: return "Adapts to your device's light/dark setting"
        case .light: return "Always light mode"
        case .dark: return "Premium dark — always dark mode"
        }
    }

    private var appearanceDescription: String {
        let appearance = ColorAppearance(rawValue: appearanceRaw) ?? .warm
        switch appearance {
        case .cool: return "Cool gray-blue tones — calm and focused"
        case .warm: return "Soft cream tones — warm and energizing"
        case .calm: return "Soft sage green tones — calm and balanced"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Personalization
                personalizationSection

                // MARK: - Alarm Time
                alarmSection

                // MARK: - Appearance
                appearanceSection

                // MARK: - Voice
                voiceSection

                // MARK: - Data Sources
                dataSourcesSection

                // MARK: - Privacy
                privacySection

                // MARK: - Permissions
                permissionsSection

                // MARK: - About
                aboutSection
            }
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 12)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if !UIAccessibility.isReduceMotionEnabled {
                    withAnimation(.easeOut(duration: 0.35)) {
                        hasAppeared = true
                    }
                } else {
                    hasAppeared = true
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isNameFieldFocused {
                    Button("Done") {
                        isNameFieldFocused = false
                    }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(uiColor: .systemBackground))
                }
            }
            .cardEntrance(delay: 0.0)
        }
    }

    // MARK: - Personalization

    private var personalizationSection: some View {
        Section("Personalization") {
            TextField("Your Name", text: $userName)
                .textInputAutocapitalization(.words)
                .focused($isNameFieldFocused)
            Text("Used for the greeting in your morning briefing.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Alarm

    private var alarmSection: some View {
        Section("Alarm") {
            DatePicker(
                "Briefing Time",
                selection: briefingTimeBinding,
                displayedComponents: .hourAndMinute
            )
            .onChange(of: briefingTimeSeconds) { _, seconds in
                let hour = Int(seconds) / 3600
                let minute = Int(seconds) % 3600 / 60
                Task { await AlarmService.shared.scheduleBriefing(hour: hour, minute: minute) }
            }
            Text("Your morning briefing will be ready at this time.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Send Test Notification") {
                Task { await AlarmService.shared.scheduleTest(seconds: 5) }
            }
            .foregroundStyle(.blue)
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Group {
            Section("Theme") {
                Picker("Theme", selection: $themeRaw) {
                    ForEach(AppTheme.allCases) { theme in
                        Label(theme.displayName, systemImage: theme.icon)
                            .tag(theme.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("Appearance") {
                Picker("Appearance", selection: $appearanceRaw) {
                    ForEach(ColorAppearance.allCases) { appearance in
                        Label(appearance.displayName, systemImage: appearance.icon)
                            .tag(appearance.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                Text(appearanceDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Voice

    private var voiceSection: some View {
        Section("Voice") {
            Toggle(isOn: Binding(
                get: { UserDefaults.standard.bool(forKey: "voice_briefing_enabled") },
                set: { UserDefaults.standard.set($0, forKey: "voice_briefing_enabled") }
            )) {
                Label("Voice Briefing", systemImage: "speaker.wave.2")
            }
            .tint(Color.warmPrimaryAccent)

            if UserDefaults.standard.bool(forKey: "voice_briefing_enabled") {
                Text("Tap the 🔊 Listen button in the briefing view to hear your morning update.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Data Sources

    private var dataSourcesSection: some View {
        Section("Data Sources") {
            AnimatedToggle(isOn: $healthEnabled, icon: "heart.fill", label: "Health")
                .disabled(localOnly)

            AnimatedToggle(isOn: $calendarEnabled, icon: "calendar", label: "Calendar")
                .disabled(localOnly)

            AnimatedToggle(isOn: $weatherEnabled, icon: "cloud.sun", label: "Weather")
                .disabled(localOnly)

            AnimatedToggle(isOn: $headlinesEnabled, icon: "newspaper", label: "Headlines")
                .disabled(localOnly)
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        Section("Privacy") {
            AnimatedToggle(isOn: $localOnly, icon: "lock.fill", label: "Local-Only Mode")

            NavigationLink {
                PrivacyPolicyView()
            } label: {
                Label("Privacy Policy", systemImage: "hand.raised")
            }

            HStack {
                Label("Location Precision", systemImage: "location.slash")
                Spacer()
                Text("Approximate only")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label("Network Activity", systemImage: "network")
                Spacer()
                Text(localOnly ? "All Local" : "External")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        Section("Permissions") {
            Button {
                Task { await healthService.requestAuthorization() }
            } label: {
                HStack {
                    Label("HealthKit", systemImage: "heart.text.square")
                    Spacer()
                    Image(systemName: healthService.isAuthorized ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(healthService.isAuthorized ? .green : .orange)
                }
            }

            Button {
                Task { await calendarService.requestAuthorization() }
            } label: {
                HStack {
                    Label("Calendar", systemImage: "calendar")
                    Spacer()
                    Image(systemName: calendarService.isAuthorized ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(calendarService.isAuthorized ? .green : .orange)
                }
            }

            // Alarm status
            HStack {
                Label("Alarm", systemImage: "alarm")
                Spacer()
                if alarmService.activeAlarms.isEmpty {
                    Text("Not scheduled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(alarmService.activeAlarms.count) alarm(s) active")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            if let error = alarmService.lastError {
                Text("Last error: \(error)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text(getMarketingVersion())
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Build")
                Spacer()
                Text(getBuildNumber())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func getBuildNumber() -> String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private func getMarketingVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}

// MARK: - Animated Toggle

struct AnimatedToggle: View {
    @Binding var isOn: Bool
    let icon: String
    let label: String
    @State private var scale: CGFloat = 1.0
    @State private var slideOffset: CGFloat = 0

    var body: some View {
        Toggle(isOn: $isOn) {
            Label(label, systemImage: icon)
        }
        .tint(Color.warmPrimaryAccent)
        .scaleEffect(scale)
        .onChange(of: isOn) { _, _ in
            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(isOn ? .success : .warning)

            // Scale bounce
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                scale = 0.95
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.1)) {
                scale = 1.0
            }
        }
    }
}

#Preview {
    SettingsView()
}