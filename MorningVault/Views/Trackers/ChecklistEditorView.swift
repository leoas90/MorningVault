import SwiftUI

/// Settings > Trackers > Edit items. Drag to reorder, swipe to archive, + adds. With no items
/// yet, starter chips add common ones in one tap (role-based, never named).
struct ChecklistEditorView: View {
    @ObservedObject var model: ChecklistViewModel
    @State private var editing: EditorTarget?

    enum EditorTarget: Identifiable {
        case new
        case item(ChecklistItem)
        var id: String {
            switch self {
            case .new: return "new"
            case .item(let item): return item.id.uuidString
            }
        }
    }

    var body: some View {
        List {
            if model.hasLoaded, model.activeItems.isEmpty {
                Section {
                    templates
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                }
                .listRowBackground(Color.clear)
            }

            Section {
                ForEach(model.activeItems) { item in
                    Button { editing = .item(item) } label: { row(item) }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { await model.archive(item) }
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                        }
                }
                .onMove { source, destination in
                    Task { await model.move(from: source, to: destination) }
                }

                Button { editing = .new } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus").font(.system(size: 15, weight: .medium)).frame(width: 22)
                        Text("Add an item").font(.bodyText)
                        Spacer()
                        if !model.canAddItem {
                            Text("12 of 12").font(.metaText).foregroundStyle(Color.inkSecondary)
                        }
                    }
                    .foregroundStyle(model.canAddItem ? Color.inkPrimary : Color.inkSecondary)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!model.canAddItem)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            } header: {
                HStack {
                    Eyebrow(text: "Items")
                    Spacer()
                    if !model.activeItems.isEmpty {
                        Text("\(model.activeItems.count) of \(ChecklistItem.maxItems)")
                            .font(.metaText).foregroundStyle(Color.inkSecondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            } footer: {
                Text("Up to twelve. Swipe to archive; history stays. Drag to reorder.")
                    .font(.metaText).foregroundStyle(Color.inkSecondary)
                    .padding(.horizontal, 20)
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.backgroundColor.ignoresSafeArea())
        .toolbar { ToolbarItem(placement: .primaryAction) { EditButton().tint(Color.appAccentColor) } }
        .navigationTitle("Household items")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { target in
            switch target {
            case .new: ChecklistItemEditor(model: model)
            case .item(let item): ChecklistItemEditor(model: model, item: item)
            }
        }
        .task { await model.load() }
    }

    private func row(_ item: ChecklistItem) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .font(.system(size: 16, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.inkSecondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.bodyText).foregroundStyle(Color.inkPrimary).lineLimit(1)
                    Text(subtitle(item)).font(.metaText).foregroundStyle(Color.inkSecondary).lineLimit(1)
                }
                Spacer()
                if let member = model.member(item.forMember) {
                    MemberInitialChip(initial: member.initial)
                }
                if item.reminder != nil {
                    Image(systemName: "bell").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.inkSecondary)
                        .accessibilityLabel("Has a reminder")
                }
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            Hairline()
        }
    }

    private func subtitle(_ item: ChecklistItem) -> String {
        var parts = [item.recurrence.summary]
        if case .timer(let minutes) = item.kind { parts.append("\(minutes) min") }
        return parts.joined(separator: " · ")
    }

    // MARK: Templates

    private var templates: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add the things you do every morning")
                .font(.bodyText).foregroundStyle(Color.inkPrimary)
            FlowLayout(spacing: 8, alignment: .leading) {
                ForEach(ChecklistTemplate.all + ChecklistTemplate.timeWithChildren(members: model.members)) { template in
                    ChoiceChip(title: template.title, systemImage: "plus", isSelected: false) {
                        Task { await add(template) }
                    }
                }
            }
            Text("Tap to add. Everything can be changed afterwards.")
                .font(.metaText).foregroundStyle(Color.inkSecondary)
        }
    }

    private func add(_ template: ChecklistTemplate) async {
        // "Time with <child>" is tagged for that child when the name matches.
        let child = model.members.first { $0.role == .child && template.title == "Time with \($0.name)" }
        await model.save(template.makeItem(order: model.nextOrder, forMember: child?.id))
    }
}

#Preview("Items") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    return NavigationStack { ChecklistEditorView(model: ChecklistViewModel.preview()) }
}

#Preview("Empty, templates") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    return NavigationStack { ChecklistEditorView(model: ChecklistViewModel.previewEmpty()) }
}
