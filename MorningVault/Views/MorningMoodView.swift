import SwiftUI

// MARK: - Morning Mood System View

struct MorningMoodView: View {
    @Binding var selectedMood: MoodType?
    @State private var hasAppeared = false
    @State private var animateGradient = false
    @Environment(\.dismiss) private var dismiss

    private var sunriseGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.sunriseOrange,
                Color.sunrisePink,
                Color.sunriseGold,
                Color.sunriseLavender
            ],
            startPoint: animateGradient ? .topLeading : .bottomLeading,
            endPoint: animateGradient ? .bottomTrailing : .topTrailing
        )
    }

    var body: some View {
        ZStack {
            // Dynamic sunrise background
            sunriseGradient
                .ignoresSafeArea()
                .opacity(0.9)

            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("How are you feeling this morning?")
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(.white)

                    Text("Select your mood to personalize your briefing")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.top, 40)

                // Mood Grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(MoodType.allCases, id: \.self) { mood in
                        MoodButton(
                            mood: mood,
                            isSelected: selectedMood == mood,
                            onSelect: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedMood = mood
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 24)

                Spacer()

                // Continue button
                if selectedMood != nil {
                    Button {
                        dismiss()
                    } label: {
                        Text("Continue")
                            .font(.headline)
                            .foregroundStyle(Color.sunriseOrange)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.bottom, 40)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                animateGradient = true
            }
        }
    }
}

// MARK: - Mood Button

struct MoodButton: View {
    let mood: MoodType
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var hasAppeared = false
    @State private var isPressed = false

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                Text(mood.emoji)
                    .font(.system(size: 32))

                Text(mood.label)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.white.opacity(0.3) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.white : Color.white.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
            .scaleEffect(isSelected ? 1.05 : (isPressed ? 0.95 : 1.0))
        }
        .buttonStyle(.plain)
        .onAppear {
            hasAppeared = true
        }
        .onChange(of: hasAppeared) { _, appeared in
            if appeared && !UIAccessibility.isReduceMotionEnabled {
                // Stagger animation handled by parent
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
        )
    }
}

// MARK: - Sunrise Theme Colors

extension Color {
    // Sunrise palette
    static var sunriseOrange: Color { Color(hex: "FF6B35") }
    static var sunrisePink: Color { Color(hex: "F7567C") }
    static var sunriseGold: Color { Color(hex: "FFB347") }
    static var sunriseLavender: Color { Color(hex: "C3A6FF") }
    static var sunriseCream: Color { Color(hex: "FFF8E7") }

    // Mood-specific sunrise colors
    static func moodColor(_ mood: MoodType) -> Color {
        switch mood {
        case .inspired: return Color.sunriseGold
        case .focused: return Color.sunriseOrange
        case .alert: return Color.sunrisePink
        case .calm: return Color.sunriseLavender
        case .energetic: return Color(hex: "FF4444")
        case .reflective: return Color(hex: "7E8EA8")
        case .motivated: return Color.sunriseOrange
        case .neutral: return Color.sunriseCream
        }
    }
}

// MARK: - Sunrise Theme Card Modifier

struct SunriseThemeCard: ViewModifier {
    let mood: MoodType?
    @State private var hasAppeared = false

    private var gradientColors: [Color] {
        guard let mood = mood else {
            return [Color.sunriseOrange, Color.sunrisePink, Color.sunriseGold]
        }
        switch mood {
        case .inspired:
            return [Color.sunriseGold, Color.sunriseOrange]
        case .focused:
            return [Color.sunriseOrange, Color.sunrisePink]
        case .alert:
            return [Color.sunrisePink, Color.sunriseLavender]
        case .calm:
            return [Color.sunriseLavender, Color.sunriseCream]
        case .energetic:
            return [Color.sunriseOrange, Color(hex: "FF4444")]
        case .reflective:
            return [Color(hex: "7E8EA8"), Color.sunriseLavender]
        case .motivated:
            return [Color.sunriseOrange, Color.sunriseGold]
        case .neutral:
            return [Color.sunriseCream, Color.sunriseGold]
        }
    }

    func body(content: Content) -> some View {
        content
            .background(
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: Color.sunriseOrange.opacity(0.2), radius: 8, x: 0, y: 4)
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 10)
            .onAppear {
                if !UIAccessibility.isReduceMotionEnabled {
                    withAnimation(.easeOut(duration: 0.4)) {
                        hasAppeared = true
                    }
                } else {
                    hasAppeared = true
                }
            }
    }
}

extension View {
    func sunriseCard(mood: MoodType?) -> some View {
        modifier(SunriseThemeCard(mood: mood))
    }
}

// MARK: - Mood Trend View

struct MoodTrendView: View {
    let moodEntries: [MoodEntry]
    @State private var hasAppeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mood Trend")
                .font(.headline)
                .foregroundStyle(Color.warmTextPrimary)

            if moodEntries.isEmpty {
                Text("No mood data yet. Start tracking your mornings!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(moodEntries.enumerated()), id: \.offset) { index, entry in
                            MoodTrendDot(entry: entry, dayIndex: index)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color.warmSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 10)
        .onAppear {
            if !UIAccessibility.isReduceMotionEnabled {
                withAnimation(.easeOut(duration: 0.4)) {
                    hasAppeared = true
                }
            } else {
                hasAppeared = true
            }
        }
    }
}

struct MoodTrendDot: View {
    let entry: MoodEntry
    let dayIndex: Int

    @State private var hasAppeared = false

    private var dayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: entry.date)
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(entry.mood.emoji)
                .font(.system(size: 24))
                .background(
                    Circle()
                        .fill(Color.moodColor(entry.mood).opacity(0.2))
                        .frame(width: 44, height: 44)
                )

            Text(dayLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .scaleEffect(hasAppeared ? 1 : 0)
        .onAppear {
            if !UIAccessibility.isReduceMotionEnabled {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(dayIndex) * 0.05) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        hasAppeared = true
                    }
                }
            } else {
                hasAppeared = true
            }
        }
    }
}

#Preview {
    MorningMoodView(selectedMood: .constant(.energetic))
}