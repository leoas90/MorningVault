import SwiftUI

/// Settings > Trackers > Household > Calendars. Which calendars feed the suggestion engine,
/// and whose events they are. Grouped by account. Scopes suggestions only; the Brief's Next
/// block keeps reading every calendar. Stored on this device, never synced.
struct CalendarPickerView: View {
    @ObservedObject var model: ChecklistViewModel
    @ObservedObject private var calendarService = CalendarService.shared
    @State private var prefs: [String: CalendarPreference] = CalendarSelectionStore.load()
    @State private var groups: [(source: String, calendars: [CalendarInfo])] = []

    /// Previews pass fixed groups; the app reads EventKit.
    private let fixedGroups: [(source: String, calendars: [CalendarInfo])]?

    init(model: ChecklistViewModel, groups: [(source: String, calendars: [CalendarInfo])]? = nil) {
        self.model = model
        self.fixedGroups = groups
    }

    var body: some View {
        List {
            if !calendarService.isAuthorized, fixedGroups == nil {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Calendar access is off. Suggestions read your calendars on this phone only.")
                            .font(.secondaryText).foregroundStyle(Color.inkSecondary)
                        PillButton(title: "Allow calendar access", systemImage: "calendar") {
                            Task { _ = await calendarService.requestAuthorization(); reload() }
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                }
                .listRowBackground(Color.clear)
            }
            ForEach(groups, id: \.source) { group in
                Section {
                    ForEach(group.calendars) { calendar in
                        calendarRow(calendar)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    }
                } header: {
                    Eyebrow(text: group.source)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
                .listRowBackground(Color.clear)
            }
            if groups.isEmpty, calendarService.isAuthorized || fixedGroups != nil {
                Text("No calendars found.")
                    .font(.secondaryText).foregroundStyle(Color.inkSecondary)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            Section {
                EmptyView()
            } footer: {
                Text("Checked calendars feed the suggestions in the Brief. Pick a person for a calendar and its events are theirs; otherwise a name in the title decides, then Home. Stays on this phone.")
                    .font(.metaText).foregroundStyle(Color.inkSecondary)
                    .padding(.horizontal, 20)
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.backgroundColor.ignoresSafeArea())
        .navigationTitle("Calendars")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .task { await model.load() }
    }

    private func reload() {
        groups = fixedGroups ?? calendarService.eventCalendarsBySource()
    }

    private func pref(_ id: String) -> CalendarPreference { prefs[id] ?? CalendarPreference() }

    private func update(_ id: String, _ change: (inout CalendarPreference) -> Void) {
        var p = pref(id)
        change(&p)
        prefs[id] = p
        CalendarSelectionStore.save(prefs)
    }

    private func calendarRow(_ calendar: CalendarInfo) -> some View {
        let p = pref(calendar.id)
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    update(calendar.id) { $0.enabled.toggle() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: p.enabled ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(p.enabled ? Color.appAccentColor : Color.inkSecondary)
                        Circle()
                            .fill(Color(UIColor(hex: calendar.colorHex)))
                            .frame(width: 10, height: 10)
                        Text(calendar.title)
                            .font(.bodyText)
                            .foregroundStyle(p.enabled ? Color.inkPrimary : Color.inkSecondary)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(calendar.title)
                .accessibilityValue(p.enabled ? "On" : "Off")
                Spacer(minLength: 8)
                if p.enabled {
                    Menu {
                        Button { update(calendar.id) { $0.member = nil } } label: {
                            Label("Home", systemImage: "house")
                        }
                        ForEach(model.members) { member in
                            Button { update(calendar.id) { $0.member = member.id } } label: {
                                Text(member.name.isEmpty ? member.role.label : member.name)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(memberLabel(p.member))
                                .font(.metaText)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(Color.inkSecondary)
                    }
                    .accessibilityLabel("For \(memberLabel(p.member))")
                }
            }
            .frame(minHeight: 44)
            Hairline()
        }
    }

    private func memberLabel(_ id: UUID?) -> String {
        guard let id, let member = model.member(id) else { return "Home" }
        return member.name.isEmpty ? member.role.label : member.name
    }
}

#Preview("Calendars") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    return NavigationStack {
        CalendarPickerView(model: ChecklistViewModel.preview(), groups: [
            (source: "iCloud", calendars: [
                CalendarInfo(id: "a", title: "Family", source: "iCloud", colorHex: "35568A"),
                CalendarInfo(id: "b", title: "Riley", source: "iCloud", colorHex: "2F6E52"),
            ]),
            (source: "Work", calendars: [
                CalendarInfo(id: "c", title: "Calendar", source: "Work", colorHex: "B85E24"),
            ]),
        ])
    }
}
