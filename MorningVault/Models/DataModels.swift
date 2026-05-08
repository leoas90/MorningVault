import Foundation

// MARK: - Health Data

struct HealthData: Codable {
    let sleep: SleepData?
    let steps: Int?
    let activeCalories: Double?
    let hrv: Double?
    let heartRate: Double?
    let fetchedAt: Date
}

struct SleepData: Codable {
    let hoursInBed: Int
    let minutesInBed: Int
    let hoursAsleep: Int
    let minutesAsleep: Int
    let date: Date

    var inBedFormatted: String { "\(hoursInBed)h \(minutesInBed)m" }
    var asleepFormatted: String { "\(hoursAsleep)h \(minutesAsleep)m" }
}

// MARK: - Weather Data

struct WeatherData: Codable {
    let temperatureC: Int
    let feelsLikeC: Int
    let condition: String
    let conditionIcon: String
    let humidity: Int
    let windKph: Int
    let windDirection: String
    let uvIndex: Int
    let precipMM: Double
    let location: String

    var formatted: String {
        "\(conditionIcon) \(temperatureC)°C (\(condition))"
    }

    var uvWarning: String? {
        switch uvIndex {
        case 0...2: return nil
        case 3...5: return "Moderate UV"
        case 6...7: return "High UV"
        case 8...10: return "Very High UV"
        default: return "Extreme UV"
        }
    }
}

// MARK: - Calendar Data

struct CalendarEvent: Identifiable, Codable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
    let calendarColor: String?

    var timeFormatted: String {
        if isAllDay { return "All day" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: startDate)
    }

    var durationFormatted: String {
        if isAllDay { return "" }
        let minutes = Int(endDate.timeIntervalSince(startDate) / 60)
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let h = minutes / 60
            let m = minutes % 60
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        }
    }
}

// MARK: - Briefing Data

struct BriefingData: Codable {
    let sections: [BriefingSection]
    let generatedAt: Date
    let latencyMs: Int
}

struct BriefingSection: Codable, Identifiable {
    let id: String
    let title: String
    let icon: String
    let content: String
    let sentiment: String?  // "bullish", "bearish", "neutral", "positive", "negative", nil
}

// MARK: - RSS Data

struct RSSFeedData: Codable, Identifiable {
    let id: String
    let sourceName: String
    let articles: [RSSArticle]
}

struct RSSArticle: Codable, Identifiable {
    let id: String
    let title: String
    let url: String
    let publishedAt: Date?
    let summary: String?
}

