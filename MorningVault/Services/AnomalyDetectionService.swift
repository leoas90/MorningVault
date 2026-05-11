import Foundation
import UserNotifications

/// Detects overnight anomalies across market, calendar, and health data.
/// Proactive alerts delivered via local notification before the user wakes up.
final class AnomalyDetectionService {

    static let shared = AnomalyDetectionService()

    private let alertStore = AlertStore.shared
    private let cacheService = sharedCache

    private init() {}

    // MARK: - Public API

    /// Checks for anomalies and sends a local notification if something significant happened.
    /// Call this once per day — ideally at 6 AM before the briefing is generated.
    func checkAndNotify() async {
        var anomalyMessages: [String] = []

        // 1. Market anomalies (large overnight moves)
        let marketAnomalies = await detectMarketAnomalies()
        anomalyMessages.append(contentsOf: marketAnomalies)

        // 2. Calendar anomalies (double-booking, last-minute changes)
        let calendarAnomalies = detectCalendarAnomalies()
        anomalyMessages.append(contentsOf: calendarAnomalies)

        // 3. Send notification if any anomalies found
        if !anomalyMessages.isEmpty {
            await sendNotification(
                title: "Something happened overnight",
                body: anomalyMessages.first ?? "Check your briefing for details.",
                subtitle: anomalyMessages.count > 1 ? "+\(anomalyMessages.count - 1) more" : nil
            )
        }
    }

    /// Returns all detected anomalies (for displaying in-app).
    func detectedAnomalies() async -> [AnomalyAlert] {
        var anomalies: [AnomalyAlert] = []

        let market = await detectMarketAnomalies()
        anomalies.append(contentsOf: market.map { AnomalyAlert(category: .market, message: $0) })

        let calendar = detectCalendarAnomalies()
        anomalies.append(contentsOf: calendar.map { AnomalyAlert(category: .calendar, message: $0) })

        return anomalies
    }

    // MARK: - Detection

    private func detectMarketAnomalies() async -> [String] {
        var messages: [String] = []

        // Get tracked symbols and their cached prices
        let trackedSymbols = loadTrackedSymbols()
        let cached = loadCachedPrices()

        for (symbol, data) in cached {
            let change = data.change24h

            // Large move (>3%)
            if abs(change) > 3.0 {
                let direction = change > 0 ? "surged" : "crashed"
                messages.append("\(symbol) \(direction) \(String(format: "%.1f", abs(change)))% overnight")
            }

            // Near 52-week high
            if let high52 = data.high52Week, data.price >= high52 * 0.99 {
                messages.append("\(symbol) hit a 52-week high at \(formatPrice(data.price))")
            }

            // Near 52-week low
            if let low52 = data.low52Week, data.price <= low52 * 1.01 {
                messages.append("\(symbol) near 52-week low at \(formatPrice(data.price))")
            }
        }

        return messages
    }

    private func detectCalendarAnomalies() -> [String] {
        var messages: [String] = []

        let todayEvents = loadTodayCalendarEvents()
        var timeSlots: [String: [CalendarEvent]] = [:]

        for event in todayEvents {
            let key = timeSlotKey(for: event.startTime)
            timeSlots[key, default: []].append(event)
        }

        // Check for double-bookings
        for (slot, events) in timeSlots {
            if events.count > 1 {
                messages.append("Double-booked at \(slot): \(events.map { $0.title }.joined(separator: ", "))")
            }
        }

        // Check for new events added since yesterday
        let yesterdayAdded = todayEvents.filter { $0.createdAt != nil && isRecent($0.createdAt!) }
        if !yesterdayAdded.isEmpty {
            messages.append("\(yesterdayAdded.count) new event(s) added to your calendar")
        }

        return messages
    }

    // MARK: - Notification

    private func sendNotification(title: String, body: String, subtitle: String?) async {
        let center = UNUserNotificationCenter.current()

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { return }
        } catch {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let subtitle = subtitle {
            content.subtitle = subtitle
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "morningvault.anomaly.\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil  // Immediate
        )

        try? await center.add(request)
    }

    // MARK: - Data Access (placeholder adapters — replace with actual services)

    private func loadTrackedSymbols() -> [String] {
        // Would integrate with MarketsViewModel's trackedSymbols
        return UserDefaults.standard.stringArray(forKey: "tracked_symbols") ?? ["SPY", "AAPL", "BTC"]
    }

    private func loadCachedPrices() -> [String: CachedPriceData] {
        var result: [String: CachedPriceData] = [:]
        let defaults = UserDefaults.standard
        for symbol in loadTrackedSymbols() {
            if let data = defaults.data(forKey: "cached_price:\(symbol)"),
               let decoded = try? JSONDecoder().decode(CachedPriceData.self, from: data) {
                result[symbol] = decoded
            }
        }
        return result
    }

    private func loadTodayCalendarEvents() -> [CalendarEvent] {
        // Placeholder — would integrate with CalendarService
        return []
    }

    // MARK: - Helpers

    private func timeSlotKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func isRecent(_ date: Date) -> Bool {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        return date > yesterday
    }

    private func formatPrice(_ price: Double) -> String {
        if price >= 1000 { return String(format: "$%.0f", price) }
        return String(format: "$%.2f", price)
    }
}

// MARK: - Supporting Types

struct CachedPriceData: Codable {
    let price: Double
    let change24h: Double
    let high52Week: Double?
    let low52Week: Double?
    let timestamp: Date
}

struct AnomalyAlert: Identifiable {
    let id = UUID()
    let category: AnomalyCategory
    let message: String
}

enum AnomalyCategory {
    case market
    case calendar
    case health

    var icon: String {
        switch self {
        case .market: return "chart.line.uptrend.xyaxis"
        case .calendar: return "calendar.badge.exclamationmark"
        case .health: return "heart.fill"
        }
    }
}