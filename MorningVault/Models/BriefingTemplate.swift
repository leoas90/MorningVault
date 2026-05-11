import Foundation

// MARK: - Custom Briefing Templates

/// Available briefing templates that define the order and visibility of sections.
/// Users select one template in Settings; it controls section priority/scoring.
enum BriefingTemplate: String, CaseIterable, Codable, Identifiable {
    /// Weather → Health → Calendar → Markets → Headlines → Build Task
    case standard = "standard"
    /// Markets → Weather → Headlines → Calendar → Health → Build Task
    case traderFocus = "trader-focus"
    /// Health → Weather → Calendar → Markets → Headlines → Build Task
    case wellnessFirst = "wellness-first"
    /// Headlines → Weather → Markets → Calendar → Health → Build Task
    case newsFirst = "news-first"
    /// Weather → Calendar → Health → Markets → Headlines → Build Task
    case balanced = "balanced"
    /// All sections enabled, custom order via drag-and-drop (stored separately)
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard:     return "Standard"
        case .traderFocus: return "Trader Focus"
        case .wellnessFirst: return "Wellness First"
        case .newsFirst:   return "News First"
        case .balanced:    return "Balanced"
        case .custom:      return "Custom"
        }
    }

    var description: String {
        switch self {
        case .standard:
            return "Weather → Health → Calendar → Markets → Headlines"
        case .traderFocus:
            return "Markets → Weather → Headlines → Calendar → Health"
        case .wellnessFirst:
            return "Health → Weather → Calendar → Markets → Headlines"
        case .newsFirst:
            return "Headlines → Weather → Markets → Calendar → Health"
        case .balanced:
            return "Weather → Calendar → Health → Markets → Headlines"
        case .custom:
            return "All sections, order set by you"
        }
    }

    var icon: String {
        switch self {
        case .standard:     return "sun.max"
        case .traderFocus:  return "chart.line.uptrend.xyaxis"
        case .wellnessFirst: return "heart.fill"
        case .newsFirst:    return "newspaper"
        case .balanced:     return "scale.3d"
        case .custom:       return "slider.horizontal.3"
        }
    }

    /// Priority map for this template: section id → priority (lower = higher priority).
    /// Sections not in the map get default priority 999.
    func sectionPriority(for sectionId: String) -> Int {
        switch self {
        case .standard:
            return priorityMap([
                ("weather", 1),
                ("health", 2),
                ("calendar", 3),
                ("markets", 4),
                ("headlines", 5),
                ("build", 6),
            ], sectionId: sectionId)

        case .traderFocus:
            return priorityMap([
                ("markets", 1),
                ("weather", 2),
                ("headlines", 3),
                ("calendar", 4),
                ("health", 5),
                ("build", 6),
            ], sectionId: sectionId)

        case .wellnessFirst:
            return priorityMap([
                ("health", 1),
                ("weather", 2),
                ("calendar", 3),
                ("markets", 4),
                ("headlines", 5),
                ("build", 6),
            ], sectionId: sectionId)

        case .newsFirst:
            return priorityMap([
                ("headlines", 1),
                ("weather", 2),
                ("markets", 3),
                ("calendar", 4),
                ("health", 5),
                ("build", 6),
            ], sectionId: sectionId)

        case .balanced:
            return priorityMap([
                ("weather", 1),
                ("calendar", 2),
                ("health", 3),
                ("markets", 4),
                ("headlines", 5),
                ("build", 6),
            ], sectionId: sectionId)

        case .custom:
            // Custom order is stored in UserDefaults as a list of section IDs
            return customOrderPriority(sectionId: sectionId)
        }
    }

    /// Looks up priority from a map, returning 999 for unknown sections.
    private func priorityMap(_ pairs: [(String, Int)], sectionId: String) -> Int {
        pairs.first { $0.0 == sectionId }?.1 ?? 999
    }

    /// Looks up custom order priority from stored UserDefaults list.
    private func customOrderPriority(sectionId: String) -> Int {
        let key = "custom_briefing_order"
        guard let data = UserDefaults.standard.data(forKey: key),
              let order = try? JSONDecoder().decode([String].self, from: data),
              let index = order.firstIndex(of: sectionId) else {
            return 999
        }
        return index
    }
}

// MARK: - Custom Order Storage

extension BriefingTemplate {
    /// Saves a custom section order (list of section IDs).
    static func saveCustomOrder(_ sectionIds: [String]) {
        if let encoded = try? JSONEncoder().encode(sectionIds) {
            UserDefaults.standard.set(encoded, forKey: "custom_briefing_order")
        }
    }

    /// Loads the saved custom section order.
    static func loadCustomOrder() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: "custom_briefing_order"),
              let order = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return order
    }
}

// MARK: - Template Selection Settings

/// Stored as `@AppStorage("briefing_template")` in SettingsView.
/// Default: `.standard`.
var briefingTemplateRaw: String {
    get { UserDefaults.standard.string(forKey: "briefing_template") ?? BriefingTemplate.standard.rawValue }
    set { UserDefaults.standard.set(newValue, forKey: "briefing_template") }
}

var briefingTemplate: BriefingTemplate {
    get {
        guard let raw = UserDefaults.standard.string(forKey: "briefing_template"),
              let template = BriefingTemplate(rawValue: raw) else {
            return .standard
        }
        return template
    }
    set { UserDefaults.standard.set(newValue.rawValue, forKey: "briefing_template") }
}

// MARK: - Section Priority Score

/// Combines template priority with user preference toggles to produce
/// a final sort key for briefing sections.
struct SectionPriorityScore {
    let sectionId: String
    let templatePriority: Int
    let isEnabled: Bool

    /// Lower sortValue = displayed first.
    /// Disabled sections get +1000 to sort after enabled ones.
    var sortValue: Int {
        isEnabled ? templatePriority : templatePriority + 1000
    }
}