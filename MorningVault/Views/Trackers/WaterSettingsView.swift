import SwiftUI

/// Settings > Trackers > Water settings: goal, active window, the three quick amounts and
/// the opt-in for urgent reminders. The first visit shows the one-time "Set from weight"
/// sheet (35 mL per kilogram, editable, 2,000 mL fallback).
struct WaterSettingsView: View {
    @ObservedObject var model: WaterViewModel
    @AppStorage(WaterSettings.Key.goalML) private var goalML: Int = WaterTracker.defaultGoalML
    @AppStorage(WaterSettings.Key.windowStart) private var windowStartMinutes: Int = WaterSettings.defaultWindowStartMinutes()
    @AppStorage(WaterSettings.Key.windowEnd) private var windowEndMinutes: Int = WaterTracker.defaultWindowEndMinutes
    @AppStorage(WaterSettings.Key.quick1) private var quick1: Int = WaterTracker.defaultQuickAmounts[0]
    @AppStorage(WaterSettings.Key.quick2) private var quick2: Int = WaterTracker.defaultQuickAmounts[1]
    @AppStorage(WaterSettings.Key.quick3) private var quick3: Int = WaterTracker.defaultQuickAmounts[2]
    @AppStorage(WaterSettings.Key.urgentEnabled) private var urgentEnabled = false
    @AppStorage(WaterSettings.Key.goalSheetShown) private var goalSheetShown = false
    @State private var showWeightSheet = false
    @State private var goalText = ""
    @FocusState private var goalFocused: Bool

    private var units: UnitsPreference { model.units }
    private var step: Int { units.usesImperial ? 59 : 50 }   // 2 oz or 50 mL

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Text("Daily goal")
                        .font(.bodyText)
                        .foregroundStyle(Color.inkPrimary)
                    Spacer()
                    TextField("", text: $goalText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .font(.bodyText.monospacedDigit())
                        .foregroundStyle(Color.inkPrimary)
                        .frame(width: 80)
                        .focused($goalFocused)
                        .onChange(of: goalFocused) { _, focused in if !focused { commitGoal() } }
                        .onSubmit(commitGoal)
                    Text(units.volumeUnitLabel)
                        .font(.secondaryText)
                        .foregroundStyle(Color.inkSecondary)
                }
                Button {
                    showWeightSheet = true
                } label: {
                    Label("Set from weight", systemImage: "scalemass")
                }
            } header: {
                Text("Goal")
            } footer: {
                Text("35 mL per kilogram of body weight is the usual suggestion. Health and Watch entries count toward it.")
            }
            .listRowBackground(Color.surfaceColor)

            Section {
                DatePicker("First glass", selection: minutesBinding($windowStartMinutes), displayedComponents: .hourAndMinute)
                DatePicker("Last glass", selection: minutesBinding($windowEndMinutes), displayedComponents: .hourAndMinute)
            } header: {
                Text("Active hours")
            } footer: {
                Text("Reminders fire only between these times. The first glass defaults to your alarm time.")
            }
            .listRowBackground(Color.surfaceColor)

            Section {
                amountStepper("Quick add 1", value: $quick1)
                amountStepper("Quick add 2", value: $quick2)
                amountStepper("Quick add 3", value: $quick3)
            } header: {
                Text("Quick amounts")
            }
            .listRowBackground(Color.surfaceColor)

            Section {
                HStack {
                    AnimatedToggle(isOn: $urgentEnabled, icon: "bell.badge", label: "Urgent reminders can break through Focus")
                    if !ProGate.isUnlocked { ProLockCaption() }
                }
                .disabled(!ProGate.isUnlocked)
            } header: {
                Text("Reminders")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Only when you are more than two glasses behind, or nothing is logged by noon. At most three a day. Off: those reminders use the normal level.")
                    Text(ProGate.isUnlocked
                         ? "Reminders follow how far behind you are. Gentle: a glass behind, no sound. Normal: two glasses behind, sound, at most every 45 minutes. Must do: further behind, up to three a day. One last reminder an hour before your last glass. Nothing after it."
                         : "Reminders come with Pro. Logging and the Brief row are free.")
                }
            }
            .listRowBackground(Color.surfaceColor)
        }
        .scrollContentBackground(.hidden)
        .background(Color.backgroundColor.ignoresSafeArea())
        .navigationTitle("Water settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            goalText = units.formatVolumeNumber(ml: goalML).replacingOccurrences(of: ",", with: "")
            if !goalSheetShown {
                goalSheetShown = true
                showWeightSheet = true
            }
        }
        .onChange(of: [windowStartMinutes, windowEndMinutes, quick1, quick2, quick3]) { _, _ in
            if windowEndMinutes <= windowStartMinutes { windowEndMinutes = min(24 * 60 - 1, windowStartMinutes + 60) }
            Task { await model.settingsChanged() }
        }
        .onChange(of: urgentEnabled) { _, _ in Task { await model.settingsChanged() } }
        .onChange(of: goalML) { _, _ in Task { await model.settingsChanged() } }
        .sheet(isPresented: $showWeightSheet) {
            WaterGoalFromWeightSheet(units: units, currentGoalML: goalML) { ml in
                goalML = WaterTracker.clampGoal(ml)
                goalText = units.formatVolumeNumber(ml: goalML).replacingOccurrences(of: ",", with: "")
            }
            .presentationDetents([.medium])
        }
    }

    private func commitGoal() {
        guard let value = Double(goalText.replacingOccurrences(of: ",", with: "")), value > 0 else {
            goalText = units.formatVolumeNumber(ml: goalML).replacingOccurrences(of: ",", with: "")
            return
        }
        goalML = WaterTracker.clampGoal(units.ml(fromVolume: value))
        goalText = units.formatVolumeNumber(ml: goalML).replacingOccurrences(of: ",", with: "")
    }

    private func amountStepper(_ title: String, value: Binding<Int>) -> some View {
        Stepper(value: Binding(get: { value.wrappedValue },
                               set: { value.wrappedValue = WaterTracker.clampAmount($0) }),
                in: 50...2000, step: step) {
            HStack {
                Text(title)
                    .font(.bodyText)
                    .foregroundStyle(Color.inkPrimary)
                Spacer()
                Text(units.formatVolume(ml: value.wrappedValue))
                    .font(.secondaryText.monospacedDigit())
                    .foregroundStyle(Color.inkSecondary)
            }
        }
    }

    /// Minutes after midnight as a Date on today, for the hour-and-minute picker.
    private func minutesBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(minutes.wrappedValue * 60)) },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            })
    }
}

// MARK: - Weight sheet

/// One-time sheet: weight in the user's unit, 35 mL per kilogram, editable result.
struct WaterGoalFromWeightSheet: View {
    @Environment(\.dismiss) private var dismiss
    let units: UnitsPreference
    let currentGoalML: Int
    let onSave: (Int) -> Void

    @State private var weightText = ""
    @State private var goalText = ""
    @FocusState private var focus: Field?

    private enum Field { case weight, goal }

    private var suggestedML: Int? {
        guard let w = Double(weightText), w > 0 else { return nil }
        return WaterTracker.suggestedGoal(kg: units.kg(fromWeight: w))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Grid4.section) {
                Text("Your weight sets a starting goal: \(WaterTracker.mlPerKilogram) mL per kilogram, rounded. Change it any time. Nothing is saved but the goal.")
                    .font(.secondaryText)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                EditorBlock(label: "Weight", trailing: units.weightUnitLabel) {
                    FormField(isFocused: focus == .weight) {
                        TextField("Optional", text: $weightText)
                            .keyboardType(.decimalPad)
                            .focused($focus, equals: .weight)
                    }
                }
                .onChange(of: weightText) { _, _ in
                    if let s = suggestedML { goalText = String(units.volumeValue(ml: s)) }
                }

                EditorBlock(label: "Daily goal", trailing: units.volumeUnitLabel) {
                    FormField(isFocused: focus == .goal) {
                        TextField("\(units.volumeValue(ml: WaterTracker.defaultGoalML))", text: $goalText)
                            .keyboardType(.numberPad)
                            .focused($focus, equals: .goal)
                    }
                }

                Text(suggestedML == nil
                     ? "Without a weight the goal is \(units.formatVolume(ml: WaterTracker.defaultGoalML))."
                     : "Suggested: \(units.formatVolume(ml: suggestedML ?? 0)).")
                    .font(.metaText)
                    .foregroundStyle(Color.inkSecondary)

                Spacer()
            }
            .padding(20)
            .background(Color.backgroundColor.ignoresSafeArea())
            .navigationTitle("Set your goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let ml = Double(goalText).map { units.ml(fromVolume: $0) } ?? suggestedML ?? WaterTracker.defaultGoalML
                        onSave(ml)
                        dismiss()
                    }
                }
            }
            .onAppear {
                goalText = String(units.volumeValue(ml: currentGoalML))
                focus = .weight
            }
        }
    }
}

// MARK: - Previews

#Preview("Water settings") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    UserDefaults.standard.set(true, forKey: WaterSettings.Key.goalSheetShown)
    return NavigationStack { WaterSettingsView(model: .preview()) }
}

#Preview("Set from weight") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    return WaterGoalFromWeightSheet(units: .metric, currentGoalML: 2000) { _ in }
}
