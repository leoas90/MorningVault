import SwiftUI

// MARK: - Highlights & Notes View

struct HighlightsNotesView: View {
    @State private var highlights: [Highlight] = []
    @State private var selectedSection: String? = nil
    @State private var hasAppeared = false
    @State private var isLoading = false
    @State private var showAddHighlight = false
    @State private var editingHighlight: Highlight?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.warmBackground.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .scaleEffect(1.2)
                } else if highlights.isEmpty {
                    EmptyStateView(
                        title: "No Highlights Yet",
                        message: "Tap + to add your first highlight or note.",
                        systemImage: "highlighter"
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredHighlights) { highlight in
                                HighlightCard(
                                    highlight: highlight,
                                    onEdit: { editingHighlight = highlight },
                                    onDelete: { deleteHighlight(highlight) }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                }
            }
            .navigationTitle("Highlights & Notes")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddHighlight = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddHighlight) {
                AddHighlightView { newHighlight in
                    Task {
                        await highlightStorage.saveHighlight(newHighlight)
                        await loadHighlights()
                    }
                }
            }
            .sheet(item: $editingHighlight) { highlight in
                EditHighlightView(highlight: highlight) { updated in
                    Task {
                        await highlightStorage.updateHighlight(updated)
                        await loadHighlights()
                    }
                }
            }
            .task {
                await loadHighlights()
            }
        }
    }

    private var filteredHighlights: [Highlight] {
        if let section = selectedSection {
            return highlights.filter { $0.sectionId == section }
        }
        return highlights
    }

    private func loadHighlights() async {
        isLoading = true
        highlights = await highlightStorage.getAllHighlights()
        isLoading = false
    }

    private func deleteHighlight(_ highlight: Highlight) {
        Task {
            await highlightStorage.deleteHighlight(id: highlight.id)
            await loadHighlights()
        }
    }
}

// MARK: - Highlight Card

struct HighlightCard: View {
    let highlight: Highlight
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var hasAppeared = false
    @State private var showActions = false

    private var sectionIcon: String {
        switch highlight.sectionId {
        case "weather": return "cloud.sun"
        case "health": return "heart.text.square"
        case "calendar": return "calendar"
        case "markets": return "chart.line.uptrend.xyaxis"
        case "headlines": return "newspaper"
        default: return "doc.text"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: sectionIcon)
                    .font(.caption)
                    .foregroundStyle(Color.warmPrimaryAccent)

                Text(highlight.sectionId.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if let mood = highlight.mood {
                    Text(MoodType(rawValue: mood)?.emoji ?? "")
                        .font(.caption)
                }

                Text(highlight.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Content
            Text("\"\(highlight.text)\"")
                .font(.body)
                .foregroundStyle(Color.warmTextPrimary)

            // Note
            if let note = highlight.note {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "note.text")
                        .font(.caption2)
                        .foregroundStyle(Color.warmAISummary)
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Color.warmTextSecondary)
                }
                .padding(8)
                .background(Color.warmAISummary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Actions
            HStack(spacing: 16) {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                        .font(.caption)
                }
                .foregroundStyle(Color.warmPrimaryAccent)

                Button(action: onDelete) {
                    Label("Delete", systemImage: "trash")
                        .font(.caption)
                }
                .foregroundStyle(.red)
            }
        }
        .padding(16)
        .background(Color.warmSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.warmTextPrimary.opacity(0.05), radius: 4, x: 0, y: 2)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 10)
        .onAppear {
            if !UIAccessibility.isReduceMotionEnabled {
                withAnimation(.easeOut(duration: 0.35)) {
                    hasAppeared = true
                }
            } else {
                hasAppeared = true
            }
        }
    }
}

// MARK: - Add Highlight View

struct AddHighlightView: View {
    let onSave: (Highlight) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sectionId = "general"
    @State private var highlightText = ""
    @State private var note = ""
    @State private var selectedMood: MoodType?

    private let sectionOptions = ["weather", "health", "calendar", "markets", "headlines", "general"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Section") {
                    Picker("Section", selection: $sectionId) {
                        ForEach(sectionOptions, id: \.self) { section in
                            Text(section.capitalized).tag(section)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section("Highlight") {
                    TextField("What stood out?", text: $highlightText, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Note (optional)") {
                    TextField("Add a note...", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Mood") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(MoodType.allCases, id: \.self) { mood in
                                Button {
                                    selectedMood = mood
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(mood.emoji)
                                            .font(.title3)
                                        Text(mood.label)
                                            .font(.caption2)
                                    }
                                    .padding(8)
                                    .background(selectedMood == mood ? Color.warmPrimaryAccent.opacity(0.2) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Highlight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let highlight = Highlight(
                            sectionId: sectionId,
                            text: highlightText,
                            note: note.isEmpty ? nil : note,
                            mood: selectedMood?.rawValue
                        )
                        onSave(highlight)
                        dismiss()
                    }
                    .disabled(highlightText.isEmpty)
                }
            }
        }
    }
}

// MARK: - Edit Highlight View

struct EditHighlightView: View {
    let highlight: Highlight
    let onSave: (Highlight) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var highlightText: String
    @State private var note: String
    @State private var selectedMood: MoodType?

    init(highlight: Highlight, onSave: @escaping (Highlight) -> Void) {
        self.highlight = highlight
        self.onSave = onSave
        _highlightText = State(initialValue: highlight.text)
        _note = State(initialValue: highlight.note ?? "")
        _selectedMood = State<MoodType?>(initialValue: highlight.mood.flatMap { MoodType(rawValue: $0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Highlight") {
                    TextField("What stood out?", text: $highlightText, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Note (optional)") {
                    TextField("Add a note...", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Mood") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(MoodType.allCases, id: \.self) { mood in
                                Button {
                                    selectedMood = mood
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(mood.emoji)
                                            .font(.title3)
                                        Text(mood.label)
                                            .font(.caption2)
                                    }
                                    .padding(8)
                                    .background(selectedMood == mood ? Color.warmPrimaryAccent.opacity(0.2) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit Highlight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        var updated = highlight
                        updated.note = note.isEmpty ? nil : note
                        updated.mood = selectedMood?.rawValue
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(highlightText.isEmpty)
                }
            }
        }
    }
}

#Preview {
    HighlightsNotesView()
}