import SwiftUI

/// The water tracker screen: a hairline progress ring with the remaining amount, quick-add
/// pills, a custom amount, Undo last, today's log as hairline rows, and the Quiet today
/// switch. No containers; everything sits on the 20 pt margin grid.
struct WaterTrackerView: View {
    @ObservedObject var model: WaterViewModel
    @State private var customText = ""
    @State private var showCustom = false
    @FocusState private var customFocused: Bool
    @AppStorage(WaterSettings.Key.enabled) private var waterEnabled = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Grid4.section) {
                ring
                quickAdd
                if showCustom { customAmount }
                logList
                quietSwitch
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color.backgroundColor.ignoresSafeArea())
        .navigationTitle("Water")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    WaterSettingsView(model: model)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Water settings")
            }
        }
        .task { await model.load() }
        .onReceive(NotificationCenter.default.publisher(for: .waterChangedExternally)) { _ in Task { await model.reloadAfterExternalChange() } }
        .onReceive(NotificationCenter.default.publisher(for: .appBecameActive)) { _ in Task { await model.load() } }
    }

    // MARK: Ring

    private var ring: some View {
        HStack(alignment: .center, spacing: 24) {
            WaterRing(progress: model.progress, lineWidth: 10)
                .frame(width: 132, height: 132)
                .accessibilityLabel("\(model.summaryLine), \(model.remainingLine)")
            VStack(alignment: .leading, spacing: 4) {
                Text(model.isGoalMet ? "Done" : model.units.formatVolumeNumber(ml: model.remaining))
                    .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.inkPrimary)
                    .contentTransition(.numericText())
                Text(model.isGoalMet ? "Goal met" : "\(model.units.volumeUnitLabel) to go")
                    .font(.secondaryText)
                    .foregroundStyle(Color.inkSecondary)
                Text(model.summaryLine)
                    .font(.metaText.monospacedDigit())
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .animation(.easeOut(duration: 0.3), value: model.logged)
    }

    // MARK: Quick add

    private var quickAdd: some View {
        VStack(alignment: .leading, spacing: Grid4.label) {
            Eyebrow(text: "Add")
            FlowLayout(spacing: 8, alignment: .leading) {
                ForEach(model.tracker.quickAmounts, id: \.self) { ml in
                    PillButton(title: model.units.formatVolume(ml: ml), systemImage: "plus", prominent: ml == model.tracker.quickAmounts.first) {
                        Task { await model.log(ml: ml) }
                    }
                }
                PillButton(title: "Custom", systemImage: "number", isActive: showCustom) {
                    withAnimation(.easeOut(duration: 0.2)) { showCustom.toggle() }
                    customFocused = showCustom
                }
                if model.canUndo {
                    PillButton(title: "Undo last", systemImage: "arrow.uturn.backward") {
                        Task { await model.undoLast() }
                    }
                }
            }
        }
    }

    private var customAmount: some View {
        HStack(spacing: 12) {
            FormField(isFocused: customFocused) {
                TextField("Amount in \(model.units.volumeUnitLabel)", text: $customText)
                    .keyboardType(.numberPad)
                    .focused($customFocused)
                    .onSubmit(addCustom)
            }
            PillButton(title: "Add", systemImage: "plus", prominent: true, action: addCustom)
                .disabled(Double(customText) == nil)
        }
    }

    private func addCustom() {
        guard let value = Double(customText), value > 0 else { return }
        let ml = model.units.ml(fromVolume: value)
        customText = ""
        customFocused = false
        withAnimation(.easeOut(duration: 0.2)) { showCustom = false }
        Task { await model.log(ml: ml) }
    }

    // MARK: Log

    private var logList: some View {
        VStack(alignment: .leading, spacing: Grid4.label) {
            Eyebrow(text: "Today")
            if !model.hasLoaded {
                SkeletonLine(width: 180, height: 14)
            } else if model.todayEntries.isEmpty {
                Text("Nothing logged yet.")
                    .font(.secondaryText)
                    .foregroundStyle(Color.inkSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.todayEntries) { entry in
                        HStack(spacing: 12) {
                            Text(entry.ts.formatted(date: .omitted, time: .shortened))
                                .font(.metaText.monospacedDigit())
                                .foregroundStyle(Color.inkSecondary)
                                .frame(width: 72, alignment: .leading)
                            Text(model.units.formatVolume(ml: entry.ml))
                                .font(.bodyText.monospacedDigit())
                                .foregroundStyle(Color.inkPrimary)
                            Spacer()
                            if entry.source == .health {
                                Image(systemName: "heart")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.inkSecondary)
                                    .accessibilityLabel("From Health")
                            }
                        }
                        .frame(minHeight: 44)
                        Hairline()
                    }
                }
            }
        }
    }

    // MARK: Quiet

    private var quietSwitch: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { model.tracker.quietToday }, set: { v in Task { await model.setQuietToday(v) } })) {
                Label("Quiet today", systemImage: "moon")
                    .font(.bodyText)
                    .foregroundStyle(Color.inkPrimary)
            }
            .tint(Color.appAccentColor)
            Text("No water reminders for the rest of today. Logging still counts.")
                .font(.metaText)
                .foregroundStyle(Color.inkSecondary)
        }
    }
}

// MARK: - Ring

/// Hairline track with an accent arc. A checkmark when complete.
struct WaterRing: View {
    var progress: Double
    var lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle().stroke(Color.hairline, lineWidth: 1)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(Color.appAccentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.35), value: progress)
            if progress >= 1 {
                Image(systemName: "checkmark")
                    .font(.system(size: lineWidth * 2.6, weight: .bold))
                    .foregroundStyle(Color.appAccentColor)
            }
        }
        .padding(lineWidth / 2)
    }
}

// MARK: - Brief row

/// One hairline row in the Brief: "Water  500 of 2,000 mL  1,500 to go" with a quick-add
/// pill inline. Tap opens the tracker.
struct WaterBriefRow: View {
    @ObservedObject var model: WaterViewModel
    @State private var showTracker = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    showTracker = true
                } label: {
                    HStack(spacing: 12) {
                        WaterRing(progress: model.progress, lineWidth: 3)
                            .frame(width: 22, height: 22)
                        Text("Water")
                            .font(.bodyText)
                            .foregroundStyle(Color.inkPrimary)
                        Text(model.summaryLine)
                            .font(.metaText.monospacedDigit())
                            .foregroundStyle(Color.inkSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(model.remainingLine)
                            .font(.metaText.monospacedDigit())
                            .foregroundStyle(model.isBehind ? Color.appAccentColor : Color.inkSecondary)
                            .lineLimit(1)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Water, \(model.summaryLine), \(model.remainingLine)")
                .accessibilityHint("Opens the water tracker")

                if !model.isGoalMet, let first = model.tracker.quickAmounts.first {
                    Button {
                        Task { await model.log(ml: first) }
                    } label: {
                        Text("+\(model.units.formatVolumeNumber(ml: first))")
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Color.inkPrimary)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 32)
                            .background(Color.surfaceColor, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Log \(model.units.formatVolume(ml: first))")
                }
            }
            Hairline()
        }
        .task { await model.load() }
        .onReceive(NotificationCenter.default.publisher(for: .waterChangedExternally)) { _ in Task { await model.reloadAfterExternalChange() } }
        .onReceive(NotificationCenter.default.publisher(for: .appBecameActive)) { _ in Task { await model.load() } }
        .onReceive(NotificationCenter.default.publisher(for: .openWaterTracker)) { _ in showTracker = true }
        .sheet(isPresented: $showTracker) {
            NavigationStack { WaterTrackerView(model: model) }
        }
    }
}

// MARK: - Previews

#Preview("Tracker") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    return NavigationStack { WaterTrackerView(model: .preview()) }
}

#Preview("Tracker, empty") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    return NavigationStack { WaterTrackerView(model: .previewEmpty()) }
}

#Preview("Tracker, done, dark") {
    ThemeStore.shared.themeRaw = AppTheme.dark.rawValue
    return NavigationStack { WaterTrackerView(model: .previewDone()) }
}

#Preview("Brief row") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    return VStack(spacing: 24) {
        WaterBriefRow(model: .preview())
        WaterBriefRow(model: .previewEmpty())
        WaterBriefRow(model: .previewDone())
    }
    .padding(20)
    .background(Color.backgroundColor)
}
