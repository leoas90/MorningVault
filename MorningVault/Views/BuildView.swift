import SwiftUI

struct BuildView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Build status header
                    VStack(spacing: 8) {
                        Image(systemName: "hammer.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.accentColor)
                        Text("Morning Vault")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Build \(getBuildNumber())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)

                    Divider()
                        .padding(.horizontal)

                    // Version info
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Version", systemImage: "info.circle") .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(getMarketingVersion()) (Build \(getBuildNumber()))")
                            .font(.body)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                    Divider()
                        .padding(.horizontal)

                    // Privacy note
                    VStack(spacing: 12) {
                        Image(systemName: "lock.shield")
                            .font(.title)
                            .foregroundStyle(Color.positiveColor)
                        Text("Privacy First")
                            .font(.headline)
                        Text("All data stays on your device.\nNo accounts, no tracking, no cloud.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()

                    Spacer()
                }
            }
            .navigationTitle("Build")
        }
    }

    private func getBuildNumber() -> String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private func getMarketingVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}

#Preview {
    BuildView()
}