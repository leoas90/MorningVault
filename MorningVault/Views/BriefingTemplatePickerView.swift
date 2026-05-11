import SwiftUI

// MARK: - Briefing Template Picker

struct BriefingTemplatePickerView: View {
    @AppStorage("briefing_template") private var selectedTemplateRaw: String = BriefingTemplate.standard.rawValue
    @State private var showingCustomOrderEditor = false

    private var selectedTemplate: BriefingTemplate {
        BriefingTemplate(rawValue: selectedTemplateRaw) ?? .standard
    }

    var body: some View {
        List {
            Section {
                ForEach(BriefingTemplate.allCases) { template in
                    Button {
                        selectedTemplateRaw = template.rawValue
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: template.icon)
                                .font(.system(size: 20))
                                .foregroundStyle(selectedTemplate == template ? Color.warmPrimaryAccent : .secondary)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(template.displayName)
                                    .font(.subheadline)
                                    .fontWeight(selectedTemplate == template ? .semibold : .regular)
                                    .foregroundStyle(.primary)

                                Text(template.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if selectedTemplate == template {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.warmPrimaryAccent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Briefing Layout")
            } footer: {
                Text("Choose how your briefing sections are ordered. Each template prioritizes different information.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if selectedTemplate == .custom {
                Section {
                    Button {
                        showingCustomOrderEditor = true
                    } label: {
                        Label("Edit Custom Order", systemImage: "slider.horizontal.3")
                    }
                } footer: {
                    Text("Drag to reorder sections. All enabled sections are shown in your briefing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Briefing Template")
        .sheet(isPresented: $showingCustomOrderEditor) {
            CustomOrderEditorView()
        }
    }
}

// MARK: - Custom Order Editor

struct CustomOrderEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sectionOrder: [String] = []
    @State private var enabledSections: Set<String> = []

    private let allSectionIds = ["weather", "health", "calendar", "markets", "headlines", "build"]

    private var sectionDisplayName: [String: String] {
        [
            "weather": "🌤️ Weather",
            "health": "❤️ Health",
            "calendar": "📅 Calendar",
            "markets": "📈 Markets",
            "headlines": "📰 Headlines",
            "build": "🔧 Build Task"
        ]
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(sectionOrder, id: \.self) { sectionId in
                        HStack {
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.secondary)
                            Text(sectionDisplayName[sectionId] ?? sectionId)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { enabledSections.contains(sectionId) },
                                set: { isEnabled in
                                    if isEnabled {
                                        enabledSections.insert(sectionId)
                                    } else {
                                        enabledSections.remove(sectionId)
                                    }
                                }
                            ))
                        }
                    }
                    .onMove { from, to in
                        sectionOrder.move(fromOffsets: from, toOffset: to)
                    }
                } header: {
                    Text("Section Order")
                } footer: {
                    Text("Drag to reorder. Disabled sections won't appear in your briefing.")
                        .font(.caption)
                }
            }
            .navigationTitle("Custom Order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        saveAndDismiss()
                    }
                }
            }
        }
        .onAppear { loadState() }
    }

    private func loadState() {
        sectionOrder = BriefingTemplate.loadCustomOrder()
        if sectionOrder.isEmpty {
            sectionOrder = allSectionIds
        }
        // Load enabled sections — default to all enabled
        let storedEnabled = UserDefaults.standard.stringArray(forKey: "custom_enabled_sections") ?? []
        if !storedEnabled.isEmpty {
            enabledSections = Set(storedEnabled)
        } else {
            enabledSections = Set(allSectionIds)
        }
    }

    private func saveAndDismiss() {
        BriefingTemplate.saveCustomOrder(sectionOrder)
        UserDefaults.standard.set(Array(enabledSections), forKey: "custom_enabled_sections")
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        BriefingTemplatePickerView()
    }
}