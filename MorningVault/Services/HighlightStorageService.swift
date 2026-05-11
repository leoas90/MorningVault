import Foundation

/// Service for persistent storage of highlights, notes, moods, and briefing archive.
/// All data stored locally in cache directory — no network transmission.
actor HighlightStorageService {
    private let fileManager = FileManager.default
    private let storageDir: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(name: String = "Highlights") {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.storageDir = base.appendingPathComponent(name)
        try? fileManager.createDirectory(at: storageDir, withIntermediateDirectories: true)
    }

    // MARK: - Highlights

    func saveHighlight(_ highlight: Highlight) async {
        var highlights = await getAllHighlights()
        highlights.append(highlight)
        await saveAllHighlights(highlights)
    }

    func updateHighlight(_ highlight: Highlight) async {
        var highlights = await getAllHighlights()
        if let index = highlights.firstIndex(where: { $0.id == highlight.id }) {
            highlights[index] = highlight
            await saveAllHighlights(highlights)
        }
    }

    func deleteHighlight(id: String) async {
        var highlights = await getAllHighlights()
        highlights.removeAll { $0.id == id }
        await saveAllHighlights(highlights)
    }

    func getHighlights(forSection sectionId: String) async -> [Highlight] {
        await getAllHighlights().filter { $0.sectionId == sectionId }
    }

    func getAllHighlights() async -> [Highlight] {
        let file = storageDir.appendingPathComponent("highlights.json")
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? decoder.decode([Highlight].self, from: data)) ?? []
    }

    private func saveAllHighlights(_ highlights: [Highlight]) async {
        let file = storageDir.appendingPathComponent("highlights.json")
        guard let data = try? encoder.encode(highlights) else { return }
        try? data.write(to: file)
    }

    // MARK: - Mood Tracking

    func saveMood(_ mood: MoodType, for date: Date = Date()) async {
        var moods = await getAllMoods()
        let entry = MoodEntry(mood: mood, date: date)
        // Replace existing mood for same day
        let calendar = Calendar.current
        if let index = moods.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            moods[index] = entry
        } else {
            moods.append(entry)
        }
        await saveAllMoods(moods)
    }

    func getMood(for date: Date) async -> MoodType? {
        let moods = await getAllMoods()
        let calendar = Calendar.current
        return moods.first { calendar.isDate($0.date, inSameDayAs: date) }?.mood
    }

    func getAllMoods() async -> [MoodEntry] {
        let file = storageDir.appendingPathComponent("moods.json")
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? decoder.decode([MoodEntry].self, from: data)) ?? []
    }

    private func saveAllMoods(_ moods: [MoodEntry]) async {
        let file = storageDir.appendingPathComponent("moods.json")
        guard let data = try? encoder.encode(moods) else { return }
        try? data.write(to: file)
    }
}

struct MoodEntry: Codable {
    let mood: MoodType
    let date: Date
}

// MARK: - Shared Instance

let highlightStorage = HighlightStorageService()