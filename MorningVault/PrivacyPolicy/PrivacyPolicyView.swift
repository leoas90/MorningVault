import SwiftUI

/// Privacy Policy view — extracted from SettingsView
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Privacy Policy")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Last updated: May 2026")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Group {
                    Text("Data Collection").font(.headline)
                    Text("MorningVault processes your health, calendar, and location data only to generate your daily briefing. We do not collect, store, or transmit any personally identifiable information.")

                    Text("On-Device Processing").font(.headline)
                    Text("All AI processing happens locally on your device using Apple's FoundationModels framework. Your data never leaves your device.")

                    Text("Location").font(.headline)
                    Text("We use approximate location only (city-level) to fetch weather data. Your precise GPS coordinates are never stored or transmitted.")

                    Text("Health Data").font(.headline)
                    Text("HealthKit data is read-only and never leaves your device. We do not share any health data with third parties.")

                    Text("Calendar").font(.headline)
                    Text("Calendar access is used solely to display your scheduled events in your briefing. No calendar data is stored externally.")

                    Text("Analytics").font(.headline)
                    Text("We do not use any analytics, telemetry, or tracking. There are no third-party SDKs that collect user data.")

                    Text("Contact").font(.headline)
                    Text("For privacy concerns, contact yeziddr@gmail.com")
                }
            }
            .padding()
        }
        .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}