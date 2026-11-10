import SwiftUI

/// Settings > Trackers > Water settings: goal, active window, the user's cups (up to five,
/// the first one is the primary) and the opt-in for urgent reminders. The first visit shows the one-time "Set from weight"
/// sheet (35 mL per kilogram, editable, 2,000 mL fallback).
struct WaterSettingsView: View {
    @ObservedObject var model: WaterViewModel
    @AppStorage(WaterSettings.Key.goalML) private var goalML: Int = WaterTracker.defaultGoalML
    @AppStorage(WaterSettings.Key.windowStart) private var windowStartMinutes: Int = WaterSettings.defaultWindowStartMinutes()
    @AppStorage(WaterSettings.Key.windowEnd) private var windowEndMinutes: Int = WaterTracker.defaultWindowEndMinutes
    @AppStorage(WaterSettings.Key.urgentEnabled) private var urgentEnabled = false
    @AppStorage(WaterSettings.Key.goalSheetShown) private var goalSheetShown = false
    @State private var showWeightSheet = false
    @State private var goalText = ""
    @State private var cups: [WaterCup] = []
    @State private var editingCup: WaterCup?
    @FocusState private var goalFocused: Bool

    private var units: UnitsPreference { model.units }

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
                ForEach(cups) { cup in
                    Button {
                        editingCup = cup
                    } label: {
                        HStack(spacing: 12) {
                            Text(cup.name)
                                .font(.bodyText)
                                .foregroundStyle(Color.inkPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(units.formatVolume(ml: cup.ml))
                                .font(.secondaryText.monospacedDigit())
                                .foregroundStyle(Color.inkSecondary)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .deleteDisabled(cups.count <= 1)
                    .accessibilityLabel("\(cup.name), \(units.formatVolume(ml: cup.ml))")
                    .accessibilityHint("Edits this cup")
                }
                .onDelete(perform: deleteCups)
                .onMove(perform: moveCups)

                Button(action: addCup) {
                    Label("Add a cup", systemImage: "plus")
                }
                .disabled(cups.count >= WaterCup.maxCount)
            } header: {
                Text("My cups")
            } footer: {
                Text("Up to five cups. Drag to reorder. The first cup is the one the widget, Siri and reminders log.")
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
        .toolbar { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
        .onAppear {
            cups = WaterSettings.cups()
            goalText = units.formatVolumeNumber(ml: goalML).replacingOccurrences(of: ",", with: "")
            if !goalSheetShown {
                goalSheetShown = true
                showWeightSheet = true
            }
        }
        .onChange(of: [windowStartMinutes, windowEndMinutes]) { _, _ in
            if windowEndMinutes <= windowStartMinutes { windowEndMinutes = min(24 * 60 - 1, windowStartMinutes + 60) }
            Task { await model.settingsChanged() }
        }
        .onChange(of: urgentEnabled) { _, _ in Task { await model.settingsChanged() } }
        .onChange(of: goalML) { _, _ in Task { await model.settingsChanged() } }
        .sheet(item: $editingCup) { cup in
            WaterCupEditorSheet(units: units, cup: cup) { updated in
                if let index = cups.firstIndex(where: { $0.id == updated.id }) {
                    cups[index] = updated
                } else {
                    cups.append(updated)
                }
                persistCups()
            }
            .presentationDetents([.medium])
        }
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

    // MARK: Cups

    private func addCup() {
        guard cups.count < WaterCup.maxCount else { return }
        let cup = WaterCup(name: "", ml: WaterGlass.ml)
        cups.append(cup)
        persistCups()
        editingCup = cup
    }

    private func deleteCups(at offsets: IndexSet) {
        var next = cups
        next.remove(atOffsets: offsets)
        guard !next.isEmpty else { return }   // at least one cup always stays
        cups = next
        persistCups()
    }

    private func moveCups(from source: IndexSet, to destination: Int) {
        cups.move(fromOffsets: source, toOffset: destination)
        persistCups()
    }

    private func persistCups() {
        cups = WaterSettings.saveCups(cups)
        Task { await model.settingsChanged() }
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

// MARK: - Cup editor

/// Name and size for one cup. The size is typed in the user's unit and stored as millilitres.
struct WaterCupEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let units: UnitsPreference
    let cup: WaterCup
    let onSave: (WaterCup) -> Void

    @State private var name = ""
    @State private var sizeText = ""
    @FocusState private var focus: Field?

    private enum Field { case name, size }

    private var sizeML: Int? {
        guard let value = Double(sizeText.replacingOccurrences(of: ",", with: ".")), value > 0 else { return nil }
        return WaterTracker.clampAmount(units.ml(fromVolume: value))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Grid4.section) {
                Text("Give the cup a name and its size. Tapping it on the water screen logs that amount.")
                    .font(.secondaryText)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                EditorBlock(label: "Name") {
                    FormField(isFocused: focus == .name) {
                        TextField("My cup", text: $name)
                            .focused($focus, equals: .name)
                            .onChange(of: name) { _, new in
                                if new.count > WaterCup.maxNameLength { name = String(new.prefix(WaterCup.maxNameLength)) }
                            }
                    }
                }

                EditorBlock(label: "Size", trailing: units.volumeUnitLabel) {
                    FormField(isFocused: focus == .size) {
                        TextField("\(units.volumeValue(ml: WaterGlass.ml))", text: $sizeText)
                            .keyboardType(.numberPad)
                            .focused($focus, equals: .size)
                    }
                }

                Text(sizeML == nil
                     ? "Between \(units.formatVolume(ml: 50)) and \(units.formatVolume(ml: 2000))."
                     : "Logs \(units.formatVolume(ml: sizeML ?? 0)) a tap.")
                    .font(.metaText)
                    .foregroundStyle(Color.inkSecondary)

                Spacer()
            }
            .padding(20)
            .background(Color.backgroundColor.ignoresSafeArea())
            .navigationTitle("Cup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let ml = sizeML ?? cup.ml
                        onSave(WaterCup(id: cup.id, name: name, ml: ml))
                        dismiss()
                    }
                }
            }
            .onAppear {
                name = cup.name
                sizeText = String(units.volumeValue(ml: cup.ml))
                focus = .name
            }
        }
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

#Preview("Water settings, five cups") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    UserDefaults.standard.set(true, forKey: WaterSettings.Key.goalSheetShown)
    WaterSettings.saveCups([WaterCup(name: "Glass", ml: 250),
                            WaterCup(name: "Bottle", ml: 500),
                            WaterCup(name: "Travel mug", ml: 350),
                            WaterCup(name: "Large bottle", ml: 750),
                            WaterCup(name: "Espresso cup", ml: 60)])
    return NavigationStack { WaterSettingsView(model: .preview()) }
}

#Preview("Cup editor") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    return WaterCupEditorSheet(units: .metric, cup: WaterCup(name: "Travel mug", ml: 350)) { _ in }
}

#Preview("Set from weight") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    return WaterGoalFromWeightSheet(units: .metric, currentGoalML: 2000) { _ in }
}
