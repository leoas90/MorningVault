import SwiftUI
import EventKit
import MeetingNotesKit

struct SettingsView: View {
    @AppStorage("briefing_time") private var briefingTimeSeconds: Double = 7 * 3600  // default 7 AM
    @AppStorage("health_enabled") private var healthEnabled = true
    @AppStorage("calendar_enabled") private var calendarEnabled = true
    @AppStorage("weather_enabled") private var weatherEnabled = true
    @AppStorage("headlines_enabled") private var headlinesEnabled = true
    @AppStorage("local_only") private var localOnly = false
    @AppStorage("ai_private_cloud") private var privateCloud = false
    @AppStorage(AlarmService.weekdaysOnlyKey) private var weekdaysOnly = true
    @AppStorage("user_name") private var userName: String = ""
    @State private var showAdvanced = false
    @State private var showAlarmErrorDetails = false
    /// Theme/Appearance live here so a change re-renders in place (no tab-view rebuild).
    @Bindable private var themeStore = ThemeStore.shared
    @AppStorage(UnitsPreference.storageKey) private var unitsRaw: String = UnitsPreference.automatic.rawValue
    @AppStorage("voice_briefing_enabled") private var voiceBriefingEnabled = false
    @AppStorage(NaturalVoiceGuard.enabledKey) private var naturalVoiceEnabled = true
    @AppStorage(VoiceBriefingService.fullBriefingKey) private var fullVoiceBriefing = false
    @State private var hasAppeared = false
    @FocusState private var isNameFieldFocused: Bool
    // Meetings tab permissions (microphone, speech, reminders); refreshed on appear and after each tap.
    @State private var microphoneGranted = RecordingPermissions.microphone == .granted
    @State private var speechGranted = RecordingPermissions.speech == .granted
    @State private var remindersGranted = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess

    private let healthService = HealthKitService.shared
    private let calendarService = CalendarService.shared
    @ObservedObject private var weatherService = WeatherService.shared
    @StateObject private var alarmService = AlarmService.shared

    private var currentTheme: AppTheme { themeStore.theme }

    private var briefingTimeBinding: Binding<Date> {
        Binding(
            get: {
                let totalSeconds = Int(briefingTimeSeconds)
                let hour = totalSeconds / 3600
                let minute = totalSeconds % 3600 / 60
                // Anchor to today's date for a stable, valid Date object the picker can manipulate reliably
                let cal = Calendar.current
                let today = cal.startOfDay(for: Date())
                var comps = DateComponents()
                comps.hour = hour
                comps.minute = minute
                return cal.date(byAdding: comps, to: today) ?? Date()
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
        switch themeStore.appearance {
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

                // MARK: - Units
                unitsSection

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

                // MARK: - Advanced (collapsed)
                advancedSection
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
                // Auto-refresh alarm status on appear (feature request)
                Task {
                    await alarmService.refreshPendingAlarms()
                    await alarmService.refreshAuthorizationState()
                }
                refreshMeetingPermissions()
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
            TextField("Your name", text: $userName)
                .textContentType(.givenName)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .focused($isNameFieldFocused)
            Text("Used for the greeting in your morning briefing. Your name stays on this device.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Alarm

    private func applyAlarm() {
        let totalSeconds = Int(briefingTimeSeconds)
        Task {
            await alarmService.scheduleBriefing(hour: totalSeconds / 3600, minute: totalSeconds % 3600 / 60,
                                                weekdaysOnly: weekdaysOnly)
        }
    }

    /// Time picker + Weekdays-only toggle; both apply as soon as they change.
    private var alarmSection: some View {
        Section {
            DatePicker(
                "Briefing time",
                selection: briefingTimeBinding,
                displayedComponents: .hourAndMinute
            )
            .onChange(of: briefingTimeSeconds) { _, _ in applyAlarm() }

            Toggle("Weekdays only", isOn: $weekdaysOnly)
                .tint(Color.warmPrimaryAccent)
                .onChange(of: weekdaysOnly) { _, _ in applyAlarm() }

            if let err = alarmService.lastError {
                VStack(alignment: .leading, spacing: 6) {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Color.warmNegative)
                    if alarmService.authorizationState != .authorized {
                        Button("Allow notifications") {
                            Task {
                                await alarmService.requestAuthorization()
                                applyAlarm()
                            }
                        }
                        .font(.caption.weight(.semibold))
                    }
                    if let details = alarmService.lastErrorDetails, !details.isEmpty {
                        DisclosureGroup("Details", isExpanded: $showAlarmErrorDetails) {
                            Text(details)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Alarm")
        } footer: {
            if let next = alarmService.nextAlarmText {
                Text("Next alarm: \(next)")
            } else if alarmService.lastError == nil {
                Text("Your briefing notification fires at this time.")
            }
        }
    }

    /// Debug-leaning controls, collapsed by default.
    private var advancedSection: some View {
        Section {
            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                Button {
                    Task { await alarmService.scheduleTest(seconds: 5) }
                } label: {
                    HStack {
                        Text("Send a test notification")
                        if alarmService.isScheduling {
                            Spacer()
                            ProgressView().scaleEffect(0.8)
                        }
                    }
                }
                .disabled(alarmService.isScheduling)

                Button("Cancel all alarms", role: .destructive) {
                    Task { await alarmService.cancelBriefingAlarm() }
                }
                .disabled(alarmService.isScheduling || alarmService.activeAlarms.isEmpty)

                Button("Refresh alarm status") {
                    Task { await alarmService.refreshPendingAlarms() }
                }
                .disabled(alarmService.isScheduling)

                LabeledContent("Scheduled days", value: alarmService.activeAlarms.isEmpty ? "None" : (weekdaysOnly ? "Mon–Fri" : "Every day"))
                    .font(.caption)
                LabeledContent("Market proxy", value: MarketBackendService.baseURL)
                    .font(.caption)
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Group {
            Section("Theme") {
                Picker("Theme", selection: $themeStore.themeRaw) {
                    ForEach(AppTheme.allCases) { theme in
                        Label(theme.displayName, systemImage: theme.icon)
                            .tag(theme.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("Appearance") {
                Picker("Appearance", selection: $themeStore.appearanceRaw) {
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

    // MARK: - Units

    private var unitsDescription: String {
        let pref = UnitsPreference(rawValue: unitsRaw) ?? .automatic
        switch pref {
        case .automatic:
            let resolved = pref.usesImperial ? "Imperial (°F, mph)" : "Metric (°C, km/h)"
            return "Follows your iPhone's region: \(resolved)."
        case .metric: return "Celsius, kilometres, km/h."
        case .imperial: return "Fahrenheit, miles, mph."
        }
    }

    private var unitsSection: some View {
        Section("Units") {
            Picker("Units", selection: $unitsRaw) {
                ForEach(UnitsPreference.allCases) { pref in
                    Text(pref.displayName).tag(pref.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: unitsRaw) { _, _ in
                // Widget and Siri read the App Group copy; the briefing text is rebuilt.
                UnitsPreference.mirrorToAppGroup()
                BriefingWidgetReloader.reload()
                NotificationCenter.default.post(name: .unitsChanged, object: nil)
            }

            Text(unitsDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Voice

    private var naturalVoiceFooter: String {
        if naturalVoiceEnabled && NaturalVoiceGuard.trippedOnThisOS {
            return "The natural voice stopped unexpectedly on this iOS version, so the system voice is reading for now. Turn Natural voice off and on to try it again."
        }
        if naturalVoiceEnabled {
            return "Short reads the weather, your calendar and the day summary; Full reads every card. Emma's voice is generated on this iPhone; nothing is sent anywhere."
        }
        return "Tap the Listen button on the Brief to hear your morning update in the system voice."
    }

    private var voiceSection: some View {
        Section("Voice") {
            Toggle(isOn: $voiceBriefingEnabled) {
                Label("Voice briefing", systemImage: "speaker.wave.2")
            }
            .tint(Color.warmPrimaryAccent)

            if voiceBriefingEnabled {
                Toggle(isOn: $naturalVoiceEnabled) {
                    Label("Natural voice", systemImage: "waveform")
                }
                .tint(Color.warmPrimaryAccent)
                .onChange(of: naturalVoiceEnabled) { _, on in
                    if on { NaturalVoiceGuard.reset() }
                }

                Picker("Length", selection: $fullVoiceBriefing) {
                    Text("Short").tag(false)
                    Text("Full").tag(true)
                }
                .pickerStyle(.segmented)

                Text(naturalVoiceFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Data Sources

    private var dataSourcesSection: some View {
        Section {
            // Health and Calendar are on-device; Local-only mode leaves them alone.
            AnimatedToggle(isOn: $healthEnabled, icon: "heart.fill", label: "Health")

            AnimatedToggle(isOn: $calendarEnabled, icon: "calendar", label: "Calendar")

            AnimatedToggle(isOn: $weatherEnabled, icon: "cloud.sun", label: "Weather")
                .disabled(localOnly)

            AnimatedToggle(isOn: $headlinesEnabled, icon: "newspaper", label: "Headlines")
                .disabled(localOnly)

            NavigationLink {
                SourcesView()
            } label: {
                Label("Edit sources", systemImage: "list.bullet")
            }
            .disabled(localOnly || !headlinesEnabled)
        } header: {
            Text("Data sources")
        } footer: {
            if localOnly {
                Text("Local-only mode keeps Weather and Headlines off. Health and Calendar stay on your device.")
            }
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        Section {
            AnimatedToggle(isOn: $localOnly, icon: "lock.fill", label: "Local-only mode")
            #if PCC_ENABLED
            if #available(iOS 27.0, *) {
                AnimatedToggle(isOn: $privateCloud, icon: "lock.icloud", label: "Private Cloud on busy mornings")
            }
            #endif

            NavigationLink {
                PrivacyPolicyView()
            } label: {
                Label("Privacy policy", systemImage: "hand.raised")
            }

            HStack {
                Label("Location precision", systemImage: "location.slash")
                Spacer()
                Text("Approximate only")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label("Network activity", systemImage: "network")
                Spacer()
                Text(localOnly ? "All local" : "External")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Privacy")
        } footer: {
            #if PCC_ENABLED
            Text("Your summary is written on your iPhone. With Private Cloud on, a morning too long for the phone is summarized by Apple's Private Cloud Compute, which keeps nothing. Health numbers are never sent.")
            #else
            Text("Your summary and headline lines are written on your iPhone. Nothing is sent to an AI service.")
            #endif
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

            Button {
                weatherService.requestAuthorization()
                weatherService.syncAuthorizationFromManager()
            } label: {
                HStack {
                    Label("Location (Weather)", systemImage: "location")
                    Spacer()
                    Image(systemName: weatherService.isAuthorized ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(weatherService.isAuthorized ? .green : .orange)
                }
            }

            Button {
                Task {
                    await alarmService.requestAuthorization()
                    await alarmService.refreshAuthorizationState()
                }
            } label: {
                HStack {
                    Label("Notifications", systemImage: "bell")
                    Spacer()
                    Image(systemName: alarmService.authorizationState == .authorized ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(alarmService.authorizationState == .authorized ? .green : .orange)
                }
            }

            // Meetings tab: recording, on-device transcription, action items → Reminders
            Button {
                Task {
                    if RecordingPermissions.microphone == .undetermined {
                        _ = await RecordingPermissions.requestMicrophone()
                    } else {
                        RecordingPermissions.openSettings()
                    }
                    refreshMeetingPermissions()
                }
            } label: {
                permissionRow("Microphone (Meetings)", icon: "mic", granted: microphoneGranted)
            }

            Button {
                Task {
                    if RecordingPermissions.speech == .undetermined {
                        _ = await RecordingPermissions.requestSpeech()
                    } else {
                        RecordingPermissions.openSettings()
                    }
                    refreshMeetingPermissions()
                }
            } label: {
                permissionRow("Speech recognition (Meetings)", icon: "waveform", granted: speechGranted)
            }

            Button {
                Task {
                    if EKEventStore.authorizationStatus(for: .reminder) == .notDetermined {
                        _ = try? await EKEventStore().requestFullAccessToReminders()
                    } else {
                        RecordingPermissions.openSettings()
                    }
                    refreshMeetingPermissions()
                }
            } label: {
                permissionRow("Reminders (Meeting action items)", icon: "list.bullet.clipboard", granted: remindersGranted)
            }

        }
    }

    private func permissionRow(_ title: String, icon: String, granted: Bool) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? .green : .orange)
        }
    }

    private func refreshMeetingPermissions() {
        microphoneGranted = RecordingPermissions.microphone == .granted
        speechGranted = RecordingPermissions.speech == .granted
        remindersGranted = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
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