import SwiftUI

struct SettingsView: View {
    @AppStorage("briefing_time") private var briefingTimeSeconds: Double = 7 * 3600  // default 7 AM
    @AppStorage("health_enabled") private var healthEnabled = true
    @AppStorage("calendar_enabled") private var calendarEnabled = true
    @AppStorage("weather_enabled") private var weatherEnabled = true
    @AppStorage("headlines_enabled") private var headlinesEnabled = true
    @AppStorage("local_only") private var localOnly = false
    @AppStorage("theme") private var themeRaw: String = AppTheme.system.rawValue
    @AppStorage("user_name") private var userName: String = ""
    @StateObject private var healthService = HealthKitService.shared
    @StateObject private var calendarService = CalendarService.shared
    @State private var showingPrivacyPolicy = false
    @FocusState private var isNameFieldFocused: Bool

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
        case .warm: return "Soft cream tones — warm and energizing"
        case .cool: return "Cool gray-blue — calm and focused"
        case .dark: return "Premium dark — always dark mode"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Personalization
                Section("Personalization") {
                    TextField("Your Name", text: $userName)
                        .textInputAutocapitalization(.words)
                        .focused($isNameFieldFocused)
                    Text("Used for the greeting in your morning briefing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: - Alarm Time
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

                // MARK: - Appearance
                Section("Appearance") {
                    Picker("Theme", selection: $themeRaw) {
                        ForEach(AppTheme.allCases) { theme in
                            Label(theme.displayName, systemImage: theme.icon)
                                .tag(theme.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()

                    Text(themeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: - Data Sources
                Section("Data Sources") {
                    Toggle(isOn: $healthEnabled) {
                        Label("Health", systemImage: "heart.fill")
                    }
                    .disabled(localOnly)

                    Toggle(isOn: $calendarEnabled) {
                        Label("Calendar", systemImage: "calendar")
                    }
                    .disabled(localOnly)

                    Toggle(isOn: $weatherEnabled) {
                        Label("Weather", systemImage: "cloud.sun")
                    }
                    .disabled(localOnly)

                    Toggle(isOn: $headlinesEnabled) {
                        Label("Headlines", systemImage: "newspaper")
                    }
                    .disabled(localOnly)
                }

                // MARK: - Privacy
                Section("Privacy") {
                    Toggle(isOn: $localOnly) {
                        Label("Local-Only Mode", systemImage: "lock.fill")
                    }

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

                // MARK: - Permissions
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
                }

                // MARK: - About
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Build")
                        Spacer()
                        Text("1")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
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
        }
    }
}

#Preview {
    SettingsView()
}