import SwiftUI

/// What the Meetings tab does, and why it will ask for the microphone and speech
/// recognition. Permissions are requested later, when the first meeting is recorded.
struct OnboardingMeetingsStep: View {
    @State private var hasAppeared = false

    private let points: [(icon: String, title: String, text: String)] = [
        ("mic.fill", "Record a meeting", "One tap from the Brief or the Meetings tab. Audio stays on this device."),
        ("waveform", "Transcribed on device", "Live transcript, speakers labeled, a summary and action items — nothing leaves the phone."),
        ("checklist", "Action items you can send", "Open items show on the next morning's Brief and can go to Reminders."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(Color.warmPrimaryAccent)
                    .padding(.bottom, 4)
                Text("Meetings")
                    .font(.display(32))
                    .foregroundStyle(Color.inkPrimary)
                Text("Notes that write themselves, kept on your phone.")
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 48)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : -12)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: point.icon)
                                .font(.title3)
                                .foregroundStyle(Color.warmPrimaryAccent)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(point.title)
                                    .font(.body.weight(.semibold))
                                Text(point.text)
                                    .font(.caption)
                                    .foregroundStyle(Color.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color.warmSurface)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 16)
                        .animation(.easeOut(duration: 0.3).delay(Double(index) * 0.06), value: hasAppeared)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Label("Microphone and speech recognition", systemImage: "hand.raised")
                            .font(.caption.weight(.semibold))
                        Text("The first time you record, iOS asks for the microphone and for on-device speech recognition. Both are needed for a transcript; neither sends audio anywhere.")
                            .font(.caption)
                            .foregroundStyle(Color.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Set up your voice later in Meetings › Your voice, so you are labeled as You.")
                            .font(.caption)
                            .foregroundStyle(Color.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
                    .opacity(hasAppeared ? 1 : 0)
                }
                .padding(.horizontal, 16)
            }
        }
        .onAppear {
            guard !UIAccessibility.isReduceMotionEnabled else {
                hasAppeared = true
                return
            }
            withAnimation(.easeOut(duration: 0.4)) {
                hasAppeared = true
            }
        }
    }
}

#Preview {
    OnboardingMeetingsStep()
}
