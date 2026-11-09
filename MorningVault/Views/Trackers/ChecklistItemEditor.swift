import SwiftUI

/// Add / edit sheet for one checklist item (plan 3a). Every row optional except the title.
/// The reminder is stored on the item; scheduling it is the next task.
struct ChecklistItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: ChecklistViewModel
    /// Item being edited; nil = new item.
    let existing: ChecklistItem?

    enum RepeatChoice: String, CaseIterable {
        case daily, weekdays, weekends, custom, once, hourly

        var label: String {
            switch self {
            case .daily: return "Daily"
            case .weekdays: return "Weekdays"
            case .weekends: return "Weekends"
            case .custom: return "Custom"
            case .once: return "One time"
            case .hourly: return "Hourly"
            }
        }
    }

    enum ReminderChoice: String, CaseIterable {
        case off, atTime
        var label: String { self == .off ? "Off" : "At time" }
    }

    // Draft state
    @State private var title: String
    @State private var icon: String
    @State private var forMember: UUID?
    @State private var isTimer: Bool
    @State private var timerMinutes: Int
    @State private var repeatChoice: RepeatChoice
    @State private var customDays: Set<Weekday>
    @State private var everyNWeeks: Int
    @State private var monthlyOn: Bool
    @State private var monthlyDay: Int
    @State private var onceDate: Date
    @State private var hourlyEvery: Int
    @State private var hourlyFrom: Date
    @State private var hourlyTo: Date
    @State private var hourlyDays: Set<Weekday>
    @State private var reminderChoice: ReminderChoice
    @State private var reminderTime: Date
    @State private var urgency: ReminderRule.Urgency
    @State private var notes: String
    @State private var saveError: String?
    @State private var showMustDoHint = false
    @FocusState private var focus: Field?

    private enum Field { case title, notes }

    private let proUnlocked = ProGate.isUnlocked

    init(model: ChecklistViewModel, item: ChecklistItem? = nil) {
        self.model = model
        self.existing = item
        let cal = model.calendar
        let now = model.now
        let item = item ?? ChecklistItem(title: "", icon: "star")
        _title = State(initialValue: item.title)
        _icon = State(initialValue: item.icon)
        _forMember = State(initialValue: item.forMember)
        if case .timer(let minutes) = item.kind {
            _isTimer = State(initialValue: true)
            _timerMinutes = State(initialValue: minutes)
        } else {
            _isTimer = State(initialValue: false)
            _timerMinutes = State(initialValue: 15)
        }
        _notes = State(initialValue: item.notes)

        // Recurrence -> editor fields
        var choice: RepeatChoice = .daily
        var days = Weekday.all
        var n = 1
        var monthly = false
        var monthDay = cal.component(.day, from: now)
        var once = now
        var hEvery = 2
        var hFrom = cal.date(bySettingHour: 8, minute: 0, second: 0, of: now) ?? now
        var hTo = cal.date(bySettingHour: 20, minute: 0, second: 0, of: now) ?? now
        var hDays = Weekday.all
        switch item.recurrence {
        case .daily:
            choice = .daily
        case .weekdays(let set):
            if set == Weekday.weekdays { choice = .weekdays } else if set == Weekday.weekends { choice = .weekends } else { choice = .custom; days = set }
        case .everyNWeeks(let weeks, let set, _):
            choice = .custom; days = set; n = weeks
        case .monthly(let day):
            choice = .custom; monthly = true; monthDay = day
        case .once(let date):
            choice = .once; once = date
        case .hourly(let every, let from, let to, let set):
            choice = .hourly; hEvery = every; hDays = set
            hFrom = cal.date(bySettingHour: from.hour ?? 8, minute: from.minute ?? 0, second: 0, of: now) ?? hFrom
            hTo = cal.date(bySettingHour: to.hour ?? 20, minute: to.minute ?? 0, second: 0, of: now) ?? hTo
        }
        _repeatChoice = State(initialValue: choice)
        _customDays = State(initialValue: days)
        _everyNWeeks = State(initialValue: n)
        _monthlyOn = State(initialValue: monthly)
        _monthlyDay = State(initialValue: monthDay)
        _onceDate = State(initialValue: once)
        _hourlyEvery = State(initialValue: hEvery)
        _hourlyFrom = State(initialValue: hFrom)
        _hourlyTo = State(initialValue: hTo)
        _hourlyDays = State(initialValue: hDays)

        if let reminder = item.reminder {
            _reminderChoice = State(initialValue: .atTime)
            _reminderTime = State(initialValue: cal.date(bySettingHour: reminder.time.hour ?? 7, minute: reminder.time.minute ?? 0, second: 0, of: now) ?? now)
            _urgency = State(initialValue: reminder.urgency)
        } else {
            _reminderChoice = State(initialValue: .off)
            _reminderTime = State(initialValue: cal.date(bySettingHour: 7, minute: 30, second: 0, of: now) ?? now)
            _urgency = State(initialValue: .normal)
        }
    }

    private var isNew: Bool { existing == nil }
    private var canSave: Bool {
        ChecklistItem.isValidTitle(title) && (isNew ? model.canAddItem : true)
            && (repeatChoice != .custom || monthlyOn || !customDays.isEmpty)
            && (repeatChoice != .hourly || (!hourlyDays.isEmpty && hourlyTo >= hourlyFrom))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Grid4.section) {
                    titleBlock
                    iconBlock
                    forBlock
                    doneByBlock
                    repeatsBlock
                    reminderBlock
                    notesBlock
                    if let saveError {
                        Text(saveError).font(.metaText).foregroundStyle(Color.negativeColor)
                    } else if isNew, !model.canAddItem {
                        Text("Twelve items is the limit. Archive one to add another.")
                            .font(.metaText).foregroundStyle(Color.inkSecondary)
                    }
                    PrimaryButton(title: isNew ? "Add" : "Save", isEnabled: canSave) { Task { await save() } }
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, Grid4.margin)
                .padding(.top, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.backgroundColor.ignoresSafeArea())
            .navigationTitle(isNew ? "New item" : "Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear { if isNew { focus = .title } }
            .onChange(of: urgency) { _, level in
                guard level == .mustDo, !UserDefaults.standard.bool(forKey: HouseholdPhoneSettings.mustDoHintShownKey) else { return }
                Task {
                    // First time only, and only while Time Sensitive is off for the app.
                    if await !TrackerNotificationService.timeSensitiveAllowed() {
                        showMustDoHint = true
                        UserDefaults.standard.set(true, forKey: HouseholdPhoneSettings.mustDoHintShownKey)
                    }
                }
            }
        }
    }

    // MARK: Blocks

    private var titleBlock: some View {
        EditorBlock(label: "Title", trailing: "\(title.count)/\(ChecklistItem.titleLimit)") {
            FormField(isFocused: focus == .title) {
                TextField("What gets done", text: $title)
                    .focused($focus, equals: .title)
                    .submitLabel(.done)
                    .onChange(of: title) { _, new in
                        if new.count > ChecklistItem.titleLimit { title = String(new.prefix(ChecklistItem.titleLimit)) }
                    }
            }
        }
    }

    private var iconBlock: some View {
        EditorBlock(label: "Icon") {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(ChecklistItem.icons, id: \.self) { symbol in
                    Button { icon = symbol } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 18, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(icon == symbol ? Color.onAccent : Color.inkPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(icon == symbol ? Color.appAccentColor : Color.surfaceColor, in: Circle())
                            .overlay(Circle().strokeBorder(icon == symbol ? Color.clear : Color.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(symbol.replacingOccurrences(of: ".", with: " "))
                    .accessibilityAddTraits(icon == symbol ? .isSelected : [])
                }
            }
        }
    }

    private var forBlock: some View {
        EditorBlock(label: "For") {
            FlowLayout(spacing: 8, alignment: .leading) {
                ChoiceChip(title: "Household", systemImage: "house", isSelected: forMember == nil) { forMember = nil }
                ForEach(model.members) { member in
                    ChoiceChip(title: member.name.isEmpty ? member.role.label : member.name, isSelected: forMember == member.id) {
                        forMember = member.id
                    }
                }
            }
        }
    }

    private var doneByBlock: some View {
        EditorBlock(label: "Done by") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Done by", selection: $isTimer) {
                    Text("Check").tag(false)
                    Text("Timer").tag(true)
                }
                .pickerStyle(.segmented)
                if isTimer {
                    Stepper(value: $timerMinutes, in: 5...60, step: 5) {
                        Text("\(timerMinutes) min").font(.bodyText).foregroundStyle(Color.inkPrimary)
                    }
                    Text("The item checks itself when the timer ends.")
                        .font(.metaText).foregroundStyle(Color.inkSecondary)
                }
            }
        }
    }

    private var repeatsBlock: some View {
        EditorBlock(label: "Repeats") {
            VStack(alignment: .leading, spacing: 12) {
                FlowLayout(spacing: 8, alignment: .leading) {
                    ForEach(RepeatChoice.allCases, id: \.self) { choice in
                        ChoiceChip(title: choice.label, isSelected: repeatChoice == choice) { repeatChoice = choice }
                    }
                }
                switch repeatChoice {
                case .daily, .weekdays, .weekends:
                    EmptyView()
                case .custom:
                    customRepeat
                case .once:
                    DatePicker("Date", selection: $onceDate, displayedComponents: .date)
                        .font(.bodyText)
                        .tint(Color.appAccentColor)
                case .hourly:
                    hourlyRepeat
                }
                Hairline()
                Text(recurrenceSummary)
                    .font(.metaText).foregroundStyle(Color.inkSecondary)
            }
        }
    }

    private var customRepeat: some View {
        VStack(alignment: .leading, spacing: 12) {
            dayChips($customDays)
                .disabled(monthlyOn)
                .opacity(monthlyOn ? 0.4 : 1)
            Stepper(value: $everyNWeeks, in: 1...4) {
                Text(everyNWeeks == 1 ? "Every week" : "Every \(everyNWeeks) weeks")
                    .font(.bodyText).foregroundStyle(Color.inkPrimary)
            }
            .disabled(monthlyOn)
            .opacity(monthlyOn ? 0.4 : 1)
            Toggle(isOn: $monthlyOn) {
                Text("Monthly instead").font(.bodyText).foregroundStyle(Color.inkPrimary)
            }
            .tint(Color.appAccentColor)
            if monthlyOn {
                Stepper(value: $monthlyDay, in: 1...31) {
                    Text("On day \(monthlyDay)").font(.bodyText).foregroundStyle(Color.inkPrimary)
                }
                if monthlyDay > 28 {
                    Text("Shorter months use their last day.")
                        .font(.metaText).foregroundStyle(Color.inkSecondary)
                }
            }
        }
    }

    private var hourlyRepeat: some View {
        VStack(alignment: .leading, spacing: 12) {
            Stepper(value: $hourlyEvery, in: 1...6) {
                Text(hourlyEvery == 1 ? "Every hour" : "Every \(hourlyEvery) hours")
                    .font(.bodyText).foregroundStyle(Color.inkPrimary)
            }
            DatePicker("From", selection: $hourlyFrom, displayedComponents: .hourAndMinute)
                .font(.bodyText).tint(Color.appAccentColor)
            DatePicker("To", selection: $hourlyTo, displayedComponents: .hourAndMinute)
                .font(.bodyText).tint(Color.appAccentColor)
            dayChips($hourlyDays)
            if hourlyTo < hourlyFrom {
                Text("The end time comes before the start.")
                    .font(.metaText).foregroundStyle(Color.negativeColor)
            } else {
                let count = hourlyRecurrence.slots(on: model.now, calendar: model.calendar).count
                Text(count == 1 ? "1 time a day." : "\(count) times a day, up to \(Recurrence.maxSlotsPerDay).")
                    .font(.metaText).foregroundStyle(Color.inkSecondary)
            }
        }
    }

    private func dayChips(_ selection: Binding<Set<Weekday>>) -> some View {
        HStack(spacing: 6) {
            ForEach(Weekday.editorOrder, id: \.self) { day in
                let on = selection.wrappedValue.contains(day)
                Button {
                    if on { selection.wrappedValue.remove(day) } else { selection.wrappedValue.insert(day) }
                } label: {
                    Text(day.letter)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(on ? Color.onAccent : Color.inkPrimary)
                        .frame(width: 36, height: 36)
                        .background(on ? Color.appAccentColor : Color.surfaceColor, in: Circle())
                        .overlay(Circle().strokeBorder(on ? Color.clear : Color.hairline, lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(day.shortLabel)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private var reminderBlock: some View {
        EditorBlock(label: "Reminder") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ForEach(ReminderChoice.allCases, id: \.self) { choice in
                        ChoiceChip(title: choice.label, isSelected: reminderChoice == choice) { reminderChoice = choice }
                    }
                    Spacer()
                    if !proUnlocked { ProLockCaption() }
                }
                .disabled(!proUnlocked)
                .opacity(proUnlocked ? 1 : 0.6)
                if reminderChoice == .atTime, proUnlocked {
                    DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                        .font(.bodyText).tint(Color.appAccentColor)
                    Picker("Urgency", selection: $urgency) {
                        ForEach(ReminderRule.Urgency.allCases, id: \.self) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(urgency.explanation)
                        .font(.metaText).foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if showMustDoHint, urgency == .mustDo {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "bell.badge")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.appAccentColor)
                            Text("Must do uses Time Sensitive notifications, which are off for this app. Allow them under Settings > Notifications to break through Focus.")
                                .font(.metaText).foregroundStyle(Color.inkPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Button("Settings") {
                                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.appAccentColor)
                        }
                    }
                } else if !proUnlocked {
                    Text("Reminders come with Pro. Checking items is always free.")
                        .font(.metaText).foregroundStyle(Color.inkSecondary)
                }
            }
        }
    }

    private var notesBlock: some View {
        EditorBlock(label: "Notes", trailing: notes.isEmpty ? nil : "\(notes.count)/\(ChecklistItem.notesLimit)") {
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            TextField("Optional, shown on long press", text: $notes, axis: .vertical)
                .lineLimit(2...5)
                .font(.bodyText)
                .foregroundStyle(Color.inkPrimary)
                .focused($focus, equals: .notes)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(shape.fill(Color.surfaceColor))
                .overlay(shape.strokeBorder(focus == .notes ? Color.appAccentColor : Color.hairline, lineWidth: focus == .notes ? 2 : 1))
                .onChange(of: notes) { _, new in
                    if new.count > ChecklistItem.notesLimit { notes = String(new.prefix(ChecklistItem.notesLimit)) }
                }
        }
    }

    // MARK: Build

    private var hourlyRecurrence: Recurrence {
        let cal = model.calendar
        return .hourly(
            everyHours: hourlyEvery,
            from: cal.dateComponents([.hour, .minute], from: hourlyFrom),
            to: cal.dateComponents([.hour, .minute], from: hourlyTo),
            on: hourlyDays)
    }

    private var recurrence: Recurrence {
        switch repeatChoice {
        case .daily: return .daily
        case .weekdays: return .weekdays(Weekday.weekdays)
        case .weekends: return .weekdays(Weekday.weekends)
        case .custom:
            if monthlyOn { return .monthly(day: monthlyDay) }
            if everyNWeeks > 1 { return .everyNWeeks(n: everyNWeeks, on: customDays, anchor: model.calendar.startOfDay(for: model.now)) }
            return .weekdays(customDays)
        case .once: return .once(model.calendar.startOfDay(for: onceDate))
        case .hourly: return hourlyRecurrence
        }
    }

    private var recurrenceSummary: String { recurrence.summary }

    private var reminder: ReminderRule? {
        // Without Pro the row is read-only: keep whatever the item already had.
        guard proUnlocked else { return existing?.reminder }
        guard reminderChoice == .atTime else { return nil }
        return ReminderRule(time: model.calendar.dateComponents([.hour, .minute], from: reminderTime), mode: .atTime, urgency: urgency, nagIfUndone: urgency != .gentle)
    }

    private func save() async {
        var item = existing ?? ChecklistItem(title: title, order: model.nextOrder, createdAt: model.now)
        item.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.icon = icon
        item.forMember = forMember
        item.kind = isTimer ? .timer(minutes: timerMinutes) : .check
        item.recurrence = recurrence
        if case .once(let date) = recurrence {
            item.expiresAt = model.calendar.date(byAdding: .day, value: 1, to: model.calendar.startOfDay(for: date))
        } else {
            item.expiresAt = nil
        }
        item.reminder = reminder
        item.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if await model.save(item) {
            dismiss()
        } else {
            saveError = model.lastError
        }
    }
}

#Preview("New item") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    return ChecklistItemEditor(model: ChecklistViewModel.preview())
}

#Preview("Edit hourly") {
    ThemeStore.shared.themeRaw = AppTheme.dark.rawValue
    return ChecklistItemEditor(model: ChecklistViewModel.preview(), item: ChecklistItem.sample[3])
        .preferredColorScheme(.dark)
}
