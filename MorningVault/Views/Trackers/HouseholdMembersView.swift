import SwiftUI

/// Settings > Trackers > Who's in your household? Add, edit and remove members. Nothing is
/// pre-filled except "Me" from the greeting name; the user types every other name.
struct HouseholdMembersView: View {
    @ObservedObject var model: ChecklistViewModel
    @State private var editing: MemberDraft?

    var body: some View {
        List {
            Section {
                if model.members.isEmpty {
                    Text("Add the people this list is for. Items can be tagged for one of them.")
                        .font(.secondaryText)
                        .foregroundStyle(Color.inkSecondary)
                        .listRowSeparator(.hidden)
                }
                ForEach(model.members) { member in
                    Button {
                        editing = MemberDraft(member: member)
                    } label: {
                        memberRow(member)
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await model.deleteMember(member) }
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
                Button {
                    editing = MemberDraft(member: HouseholdMember(name: "", role: model.me == nil ? .me : .child))
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 22)
                        Text("Add a person").font(.bodyText)
                        Spacer()
                    }
                    .foregroundStyle(Color.inkPrimary)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            } header: {
                Eyebrow(text: "Who's in your household?")
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            } footer: {
                Text("Names stay on this device. Removing a person keeps their items, untagged.")
                    .font(.metaText)
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.horizontal, 20)
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.backgroundColor.ignoresSafeArea())
        .navigationTitle("Household")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { draft in
            MemberEditorSheet(draft: draft, existingRoles: Set(model.members.filter { $0.id != draft.member.id }.map(\.role))) { member in
                Task { await model.saveMember(member) }
            }
            .presentationDetents([.medium])
        }
        .task { await model.load() }
    }

    private func memberRow(_ member: HouseholdMember) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                MemberInitialChip(initial: member.initial)
                Text(member.name.isEmpty ? "Unnamed" : member.name)
                    .font(.bodyText)
                    .foregroundStyle(Color.inkPrimary)
                Spacer()
                Text(member.role.label)
                    .font(.metaText)
                    .foregroundStyle(Color.inkSecondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.inkSecondary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            Hairline()
        }
    }
}

/// Sheet payload: a copy of the member being edited (or a blank one).
struct MemberDraft: Identifiable {
    var member: HouseholdMember
    var id: UUID { member.id }
}

/// Role chips plus a 52 pt name field.
struct MemberEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var role: HouseholdMember.Role
    @FocusState private var nameFocused: Bool
    private let id: UUID
    private let isNew: Bool
    private let existingRoles: Set<HouseholdMember.Role>
    let onSave: (HouseholdMember) -> Void

    init(draft: MemberDraft, existingRoles: Set<HouseholdMember.Role>, onSave: @escaping (HouseholdMember) -> Void) {
        _name = State(initialValue: draft.member.name)
        _role = State(initialValue: draft.member.role)
        id = draft.member.id
        isNew = draft.member.name.isEmpty
        self.existingRoles = existingRoles
        self.onSave = onSave
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Grid4.section) {
                    EditorBlock(label: "Role") {
                        FlowLayout(spacing: 8, alignment: .leading) {
                            ForEach(HouseholdMember.Role.allCases, id: \.self) { candidate in
                                // One "Me" per household.
                                let taken = candidate == .me && existingRoles.contains(.me) && role != .me
                                ChoiceChip(title: candidate.label, isSelected: role == candidate) { role = candidate }
                                    .disabled(taken)
                                    .opacity(taken ? 0.4 : 1)
                            }
                        }
                    }
                    EditorBlock(label: "Name") {
                        FormField(isFocused: nameFocused) {
                            TextField("Name", text: $name)
                                .focused($nameFocused)
                                .textInputAutocapitalization(.words)
                                .submitLabel(.done)
                                .onSubmit { if canSave { save() } }
                        }
                    }
                    PrimaryButton(title: isNew ? "Add" : "Save", isEnabled: canSave) { save() }
                }
                .padding(.horizontal, Grid4.margin)
                .padding(.top, 12)
            }
            .background(Color.backgroundColor.ignoresSafeArea())
            .navigationTitle(isNew ? "Add a person" : "Edit person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { if isNew { nameFocused = true } }
        }
    }

    private func save() {
        onSave(HouseholdMember(id: id, name: name.trimmingCharacters(in: .whitespaces), role: role))
        dismiss()
    }
}

#Preview("Members") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    return NavigationStack {
        HouseholdMembersView(model: ChecklistViewModel.preview())
    }
}

#Preview("Member editor") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    return MemberEditorSheet(draft: MemberDraft(member: HouseholdMember.sampleChild1), existingRoles: [.me, .partner]) { _ in }
}
