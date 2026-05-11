import Foundation

/// Service for storing and retrieving daily briefing history.
/// Each day's briefing is archived for recall and comparison.
actor BriefingArchiveService {
    private let fileManager = FileManager.default
    private let storageDir: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(name: String = "BriefingArchive") {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.storageDir = base.appendingPathComponent(name)
        try? fileManager.createDirectory(at: storageDir, withIntermediateDirectories: true)
    }

    // MARK: - Archive

    func archiveBriefing(sections: [BriefingSection], aiSummary: String?, mood: MoodType?, highlights: [Highlight]) async {
        let entry = BriefingArchiveEntry(
            id: UUID().uuidString,
            date: Date(),
            sections: sections,
            aiSummary: aiSummary,
            mood: mood,
            highlights: highlights
        )
        await saveEntry(entry)
    }

    func saveEntry(_ entry: BriefingArchiveEntry) async {
        var entries = await getAllEntries()
        // Replace if same day
        let calendar = Calendar.current
        if let index = entries.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: entry.date) }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        await saveAllEntries(entries)
    }

    // MARK: - Retrieve

    func getEntry(for date: Date) async -> BriefingArchiveEntry? {
        let entries = await getAllEntries()
        let calendar = Calendar.current
        return entries.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    func getEntries(from startDate: Date, to endDate: Date) async -> [BriefingArchiveEntry] {
        let entries = await getAllEntries()
        return entries.filter { $0.date >= startDate && $0.date <= endDate }
    }

    func getRecentEntries(limit: Int = 30) async -> [BriefingArchiveEntry] {
        let entries = await getAllEntries()
        return Array(entries.sorted { $0.date > $1.date }.prefix(limit))
    }

    func getAllEntries() async -> [BriefingArchiveEntry] {
        let file = storageDir.appendingPathComponent("archive.json")
        guard let data = try? Data(contentsOf: file) else { return [] }
        let entries = (try? decoder.decode([BriefingArchiveEntry].self, from: data)) ?? []
        return entries.sorted { $0.date > $1.date }
    }

    private func saveAllEntries(_ entries: [BriefingArchiveEntry]) async {
        let file = storageDir.appendingPathComponent("archive.json")
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: file)
    }

    // MARK: - Stats

    func getMoodTrend(days: Int = 7) async -> [MoodEntry] {
        let entries = await getAllEntries()
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return entries
            .filter { $0.date >= cutoff && $0.mood != nil }
            .compactMap { BriefingArchiveEntry.createMoodEntry(from: $0) }
            .sorted { $0.date < $1.date }
    }

    func getAverageSectionsPerDay(days: Int = 7) async -> Int {
        let entries = await getRecentEntries(limit: days)
        guard !entries.isEmpty else { return 0 }
        let total = entries.reduce(0) { $0 + $1.sections.count }
        return total / entries.count
    }
}

extension BriefingArchiveEntry {
    static func createMoodEntry(from entry: BriefingArchiveEntry) -> MoodEntry? {
        guard let mood = entry.mood else { return nil }
        return MoodEntry(mood: mood, date: entry.date)
    }
}

// MARK: - Shared Instance

let briefingArchive = BriefingArchiveService()