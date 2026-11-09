import Foundation

// MARK: - Rotating Brief widget: page selection and schedule
//
// The rotating widget shows one Brief section at a time and moves to the next one every few
// minutes, or when the user taps it. Which pages exist, and which one a given timeline slot
// shows, is decided here so the unit tests can check it without WidgetKit. Foundation only;
// compiled into the app and the widget extension.

/// One page of the rotating widget. Raw values double as the eyebrow label.
enum RotatingBriefPage: String, CaseIterable, Codable, Sendable {
    case weather
    case next
    case markets
    case today
    case water
    case headlines

    /// Eyebrow text, in the widget's small-caps style.
    var eyebrow: String {
        switch self {
        case .weather: return "WEATHER"
        case .next: return "NEXT"
        case .markets: return "MARKETS"
        case .today: return "TODAY"
        case .water: return "WATER"
        case .headlines: return "NEWS"
        }
    }

    /// Deep link for a tap on the page. Only hosts the app already handles: any
    /// `morningvault://` URL opens the Brief, `water` also opens the tracker over it.
    var deepLink: URL? {
        switch self {
        case .water: return URL(string: "morningvault://water")
        default: return URL(string: "morningvault://briefing")
        }
    }

    /// Pages that only fit the medium size.
    var mediumOnly: Bool { self == .headlines }
}

/// What the stores currently hold, reduced to "is there something to show". Built by the
/// widget provider from the App Group snapshots and the section toggles.
struct RotatingBriefInput: Equatable, Sendable {
    /// Section ids that are on in Settings (`BriefSectionPrefs.isEnabled`).
    var enabled: Set<String>
    var hasWeather: Bool
    /// A first event that has not started yet.
    var hasUpcomingEvent: Bool
    var marketCount: Int
    /// Checklist items scheduled for today (0 = nothing to show).
    var checklistTotal: Int
    /// A `water_today_v1` snapshot exists for today.
    var hasWaterSnapshot: Bool
    var headlineCount: Int

    init(enabled: Set<String> = [], hasWeather: Bool = false, hasUpcomingEvent: Bool = false, marketCount: Int = 0,
         checklistTotal: Int = 0, hasWaterSnapshot: Bool = false, headlineCount: Int = 0) {
        self.enabled = enabled
        self.hasWeather = hasWeather
        self.hasUpcomingEvent = hasUpcomingEvent
        self.marketCount = marketCount
        self.checklistTotal = checklistTotal
        self.hasWaterSnapshot = hasWaterSnapshot
        self.headlineCount = headlineCount
    }

    /// The section ids the pages depend on, read from the shared prefs.
    static let sectionIDs = ["weather", "next", "markets", "today", "water", "headlines"]
}

/// One scheduled entry: when it shows and which page.
struct RotatingBriefSlot: Equatable, Sendable {
    var date: Date
    var slot: Int
    var pageIndex: Int
    var page: RotatingBriefPage
}

enum RotatingBriefPages {
    /// Six hours of entries, one every twelve minutes.
    static let horizonHours = 6
    static let intervalMinutes = 12
    static let pageOrder: [RotatingBriefPage] = [.weather, .next, .markets, .today, .water, .headlines]

    /// Pages in display order. A page needs its section on in Settings and data to show;
    /// `mediumOnly` pages are left out on the small size. Empty when nothing qualifies.
    static func select(_ input: RotatingBriefInput, medium: Bool) -> [RotatingBriefPage] {
        pageOrder.filter { page in
            if page.mediumOnly, !medium { return false }
            guard input.enabled.contains(page.rawValue) else { return false }
            switch page {
            case .weather: return input.hasWeather
            case .next: return input.hasUpcomingEvent
            case .markets: return input.marketCount > 0
            case .today: return input.checklistTotal > 0
            case .water: return input.hasWaterSnapshot
            case .headlines: return input.headlineCount > 0
            }
        }
    }

    /// Page index for a slot, with the tap offset applied; wraps and tolerates negatives.
    static func index(slot: Int, offset: Int, pageCount: Int) -> Int {
        guard pageCount > 0 else { return 0 }
        let raw = (slot + offset) % pageCount
        return raw < 0 ? raw + pageCount : raw
    }

    /// Number of slots in the horizon (30 for six hours at twelve minutes).
    static func slotCount(hours: Int = horizonHours, intervalMinutes: Int = RotatingBriefPages.intervalMinutes) -> Int {
        guard intervalMinutes > 0 else { return 1 }
        return max(1, hours * 60 / intervalMinutes)
    }

    /// The schedule from `start`: one entry per slot cycling through `pages`. With no pages,
    /// a single weather entry (the widget then shows "Open MorningVault").
    static func schedule(pages: [RotatingBriefPage], offset: Int, start: Date,
                         hours: Int = horizonHours, intervalMinutes: Int = RotatingBriefPages.intervalMinutes) -> [RotatingBriefSlot] {
        guard !pages.isEmpty else {
            return [RotatingBriefSlot(date: start, slot: 0, pageIndex: 0, page: .weather)]
        }
        return (0..<slotCount(hours: hours, intervalMinutes: intervalMinutes)).map { slot in
            let i = index(slot: slot, offset: offset, pageCount: pages.count)
            return RotatingBriefSlot(date: start.addingTimeInterval(TimeInterval(slot * intervalMinutes * 60)),
                                     slot: slot, pageIndex: i, page: pages[i])
        }
    }
}

/// The tap offset, parked in the App Group. The advance intent writes it; the provider reads
/// it when it builds the timeline (slot 0 of a fresh timeline shows page `offset`).
enum RotatingBriefOffsetStore {
    static let appGroup = "group.com.morningvault.app"
    static let key = "rotating_page_offset"

    private static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    static func load(from defaults: UserDefaults? = nil) -> Int {
        (defaults ?? self.defaults).integer(forKey: key)
    }

    static func save(_ offset: Int, to defaults: UserDefaults? = nil) {
        (defaults ?? self.defaults).set(max(0, offset), forKey: key)
    }
}

/// Asks WidgetKit to refresh the rotating widget after any store that feeds a page writes.
enum RotatingBriefWidgetReloader {
    static let widgetKind = "RotatingBriefWidget"

    nonisolated static func reload() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        #endif
    }
}

#if canImport(WidgetKit)
import WidgetKit
#endif
