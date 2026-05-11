import Foundation

/// Service for generating contextual signals — smart greetings and contextual tips
/// based on time, weather, health, calendar, and market data.
actor ContextualSignalService {
    private let defaults = UserDefaults.standard

    /// Generates contextual signals based on current context
    func generateSignals(
        hour: Int,
        weather: WeatherData?,
        health: HealthData?,
        calendarEvents: [CalendarEvent],
        marketSentiment: String?,
        userName: String
    ) async -> [ContextualSignal] {
        var signals: [ContextualSignal] = []

        // Greeting signal
        let greeting = await generateGreeting(hour: hour, userName: userName, weather: weather)
        signals.append(greeting)

        // Weather-based signal
        if let weather = weather {
            let weatherSignal = generateWeatherSignal(weather: weather)
            signals.append(weatherSignal)
        }

        // Health-based signal
        if let health = health {
            let healthSignal = generateHealthSignal(health: health)
            signals.append(healthSignal)
        }

        // Calendar-based signal
        let calendarSignal = generateCalendarSignal(events: calendarEvents)
        signals.append(calendarSignal)

        // Market-based signal
        if let sentiment = marketSentiment {
            let marketSignal = generateMarketSignal(sentiment: sentiment)
            signals.append(marketSignal)
        }

        return signals.sorted { $0.priority > $1.priority }
    }

    // MARK: - Smart Greeting

    private func generateGreeting(
        hour: Int,
        userName: String,
        weather: WeatherData?
    ) async -> ContextualSignal {
        let message: String
        let priority: Int

        // Time-based greeting
        let timeGreeting: String
        switch hour {
        case 5..<8:
            timeGreeting = "Early bird"
            priority = 9
        case 8..<12:
            timeGreeting = "Good morning"
            priority = 7
        case 12..<14:
            timeGreeting = "Good afternoon"
            priority = 5
        case 14..<18:
            timeGreeting = "Good afternoon"
            priority = 4
        default:
            timeGreeting = "Good evening"
            priority = 3
        }

        // Build contextual message
        var details: [String] = []

        // Weather context
        if let weather = weather {
            if weather.temperatureC < 10 {
                details.append("cold")
            } else if weather.temperatureC > 28 {
                details.append("hot")
            }
            if weather.condition.lowercased().contains("rain") {
                details.append("rainy")
            }
        }

        if details.isEmpty {
            message = "\(timeGreeting), \(userName)."
        } else {
            message = "\(timeGreeting), \(userName). It's \(details.joined(separator: " and ")) outside — \(weatherHint(for: weather))"
        }

        return ContextualSignal(
            id: UUID().uuidString,
            type: .greeting,
            title: timeGreeting,
            message: message,
            icon: iconFor(hour: hour),
            priority: priority,
            createdAt: Date()
        )
    }

    private func iconFor(hour: Int) -> String {
        switch hour {
        case 5..<8: return "sunrise.fill"
        case 8..<12: return "sun.max.fill"
        case 12..<17: return "sun.min.fill"
        case 17..<20: return "sunset.fill"
        default: return "moon.stars.fill"
        }
    }

    private func weatherHint(for weather: WeatherData?) -> String {
        guard let weather = weather else { return "" }
        if weather.condition.lowercased().contains("rain") {
            return "bring an umbrella"
        }
        if weather.temperatureC < 10 {
            return "bundle up"
        }
        if weather.temperatureC > 28 {
            return "stay cool"
        }
        return "enjoy the day"
    }

    // MARK: - Weather Signal

    private func generateWeatherSignal(weather: WeatherData) -> ContextualSignal {
        var message = "\(weather.temperatureC)°C in \(weather.location)"
        var priority = 6

        if let uvWarning = weather.uvWarning {
            message += ". \(uvWarning)"
            priority = 7
        }

        if weather.precipMM > 5 {
            message += ". Rain expected — bring a jacket"
            priority = 8
        }

        return ContextualSignal(
            id: UUID().uuidString,
            type: .weather,
            title: "Weather",
            message: message,
            icon: weather.conditionIcon,
            priority: priority,
            createdAt: Date()
        )
    }

    // MARK: - Health Signal

    private func generateHealthSignal(health: HealthData) -> ContextualSignal {
        var message = ""
        var priority = 5

        if let sleep = health.sleep {
            let sleepHours = Double(sleep.hoursAsleep) + Double(sleep.minutesAsleep) / 60.0
            if sleepHours < 6 {
                message = "You got less than 6 hours of sleep. Consider an early night."
                priority = 7
            } else if sleepHours >= 7 {
                message = "Great sleep last night — \(sleep.asleepFormatted) of rest."
                priority = 6
            } else {
                message = "\(sleep.asleepFormatted) of sleep. Consider winding down earlier."
                priority = 5
            }
        }

        if let steps = health.steps, steps < 5000 {
            if !message.isEmpty { message += " Also, " }
            message += "Only \(steps) steps so far. Time for a walk?"
            priority = max(priority, 6)
        }

        if message.isEmpty {
            message = "Your health metrics look good today."
        }

        return ContextualSignal(
            id: UUID().uuidString,
            type: .health,
            title: "Health Check",
            message: message,
            icon: "heart.text.square",
            priority: priority,
            createdAt: Date()
        )
    }

    // MARK: - Calendar Signal

    private func generateCalendarSignal(events: [CalendarEvent]) -> ContextualSignal {
        var message = ""
        var priority = 5
        let icon = "calendar"

        if events.isEmpty {
            message = "No events today. Your calendar is clear."
            priority = 4
        } else if events.count == 1 {
            let event = events[0]
            message = "1 event today: \(event.title)"
            priority = 6
            if !event.isAllDay {
                message += " at \(event.timeFormatted)"
            }
        } else {
            message = "\(events.count) events today"
            priority = 6
            if let nextEvent = events.first(where: { !$0.isAllDay }) {
                message += ". Next: \(nextEvent.title) at \(nextEvent.timeFormatted)"
            }
        }

        return ContextualSignal(
            id: UUID().uuidString,
            type: .calendar,
            title: "Your Day",
            message: message,
            icon: icon,
            priority: priority,
            createdAt: Date()
        )
    }

    // MARK: - Market Signal

    private func generateMarketSignal(sentiment: String) -> ContextualSignal {
        let message: String
        let priority: Int
        let icon: String

        switch sentiment.lowercased() {
        case "bullish":
            message = "Markets looking bullish today 📈"
            priority = 6
            icon = "chart.line.uptrend.xyaxis"
        case "bearish":
            message = "Markets feeling cautious today 📉"
            priority = 5
            icon = "chart.line.downtrend.xyaxis"
        default:
            message = "Markets are steady today"
            priority = 4
            icon = "chart.line.flattrend.xyaxis"
        }

        return ContextualSignal(
            id: UUID().uuidString,
            type: .market,
            title: "Market Mood",
            message: message,
            icon: icon,
            priority: priority,
            createdAt: Date()
        )
    }

    // MARK: - Time of Day Helpers

    nonisolated var currentTimeGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    var isMorningTime: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 5 && hour < 12
    }

    var isEveningTime: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 17 || hour < 5
    }
}

// MARK: - Shared Instance

let contextualSignal = ContextualSignalService()