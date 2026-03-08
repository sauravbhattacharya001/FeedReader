//
//  FeedWeatherReport.swift
//  FeedReader
//
//  Generates a "weather report" metaphor for feed activity — a fun,
//  at-a-glance summary of what's happening across your feeds.
//
//  Metrics mapped to weather concepts:
//  - Temperature: overall activity level (articles per day)
//  - Pressure: content density (avg article length)
//  - Wind: velocity of change (acceleration in posting rate)
//  - Sunshine: ratio of positive to negative sentiment
//  - Storms: high-controversy or divisive content spikes
//  - Forecast: predicted activity for upcoming days
//  - UV Index: readability difficulty level
//
//  Works entirely offline using data from existing managers.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    static let feedWeatherDidUpdate = Notification.Name("FeedWeatherDidUpdateNotification")
}

// MARK: - Weather Condition

/// Overall weather condition for the feed ecosystem.
enum FeedWeatherCondition: String, Codable, CaseIterable {
    case sunny          = "☀️ Sunny"
    case partlyCloudy   = "⛅ Partly Cloudy"
    case cloudy          = "☁️ Cloudy"
    case rainy           = "🌧️ Rainy"
    case stormy          = "⛈️ Stormy"
    case snowy           = "🌨️ Snowy"
    case foggy           = "🌫️ Foggy"
    case windy           = "💨 Windy"
    case heatwave        = "🔥 Heatwave"
    case clear           = "🌙 Clear"

    var advisory: String {
        switch self {
        case .sunny:        return "Great reading weather! Mostly positive content today."
        case .partlyCloudy: return "Mixed signals across your feeds. Some good, some heavy."
        case .cloudy:       return "Dense content day. Bring your focus."
        case .rainy:        return "Negative sentiment is high. Consider lighter feeds."
        case .stormy:       return "Controversy brewing! Multiple heated topics detected."
        case .snowy:        return "Quiet day. Your feeds are taking a break."
        case .foggy:        return "Dense, complex articles dominating. Take it slow."
        case .windy:        return "Rapid-fire updates! Lots of breaking content."
        case .heatwave:     return "Activity spike! Your feeds are on fire today."
        case .clear:        return "All calm. A good time to catch up on your queue."
        }
    }
}

// MARK: - Temperature Scale

enum FeedTemperature: String, Codable {
    case freezing  = "🥶 Freezing"
    case cold      = "❄️ Cold"
    case cool      = "🌤️ Cool"
    case mild      = "😊 Mild"
    case warm      = "☀️ Warm"
    case hot       = "🔥 Hot"
    case scorching = "🌋 Scorching"

    var description: String {
        switch self {
        case .freezing:  return "Almost no activity (0-2 articles)"
        case .cold:      return "Very light activity (3-5 articles)"
        case .cool:      return "Light activity (6-10 articles)"
        case .mild:      return "Normal activity (11-20 articles)"
        case .warm:      return "Busy day (21-35 articles)"
        case .hot:       return "Very busy (36-50 articles)"
        case .scorching: return "Extremely busy (50+ articles)"
        }
    }

    static func from(articlesPerDay count: Int) -> FeedTemperature {
        switch count {
        case 0...2:   return .freezing
        case 3...5:   return .cold
        case 6...10:  return .cool
        case 11...20: return .mild
        case 21...35: return .warm
        case 36...50: return .hot
        default:      return .scorching
        }
    }
}

// MARK: - Pressure Level

enum FeedPressure: String, Codable {
    case low      = "📖 Low Pressure"
    case moderate = "📄 Moderate Pressure"
    case high     = "📚 High Pressure"
    case extreme  = "🏋️ Extreme Pressure"

    static func from(avgWordCount: Int) -> FeedPressure {
        switch avgWordCount {
        case 0...200:    return .low
        case 201...500:  return .moderate
        case 501...1000: return .high
        default:         return .extreme
        }
    }

    var description: String {
        switch self {
        case .low:      return "Light reading — short articles dominating"
        case .moderate: return "Moderate reads — average length content"
        case .high:     return "Heavy reads — long-form content detected"
        case .extreme:  return "Very dense — substantial articles requiring time"
        }
    }
}

// MARK: - Wind Speed

enum FeedWindSpeed: String, Codable {
    case calm      = "🍃 Calm"
    case breeze    = "🌬️ Breeze"
    case gusty     = "💨 Gusty"
    case gale      = "🌪️ Gale"
    case hurricane = "🌀 Hurricane"

    static func from(changeRatio: Double) -> FeedWindSpeed {
        switch changeRatio {
        case ..<0.8:     return .calm
        case 0.8..<1.5:  return .breeze
        case 1.5..<2.5:  return .gusty
        case 2.5..<4.0:  return .gale
        default:         return .hurricane
        }
    }

    var description: String {
        switch self {
        case .calm:      return "Steady posting rate"
        case .breeze:    return "Slight uptick in activity"
        case .gusty:     return "Noticeably more articles than usual"
        case .gale:      return "Dramatic activity spike"
        case .hurricane: return "Extreme surge — something big is happening"
        }
    }
}

// MARK: - UV Index (Readability)

enum FeedUVIndex: String, Codable {
    case low      = "🟢 Low"
    case moderate = "🟡 Moderate"
    case high     = "🟠 High"
    case veryHigh = "🔴 Very High"
    case extreme  = "🟣 Extreme"

    static func from(fleschScore: Double) -> FeedUVIndex {
        switch fleschScore {
        case 70...:     return .low
        case 50..<70:   return .moderate
        case 30..<50:   return .high
        case 10..<30:   return .veryHigh
        default:        return .extreme
        }
    }

    var description: String {
        switch self {
        case .low:      return "Easy, accessible content — no protection needed"
        case .moderate: return "Average difficulty — comfortable reading"
        case .high:     return "Challenging content — take breaks"
        case .veryHigh: return "Very difficult — heavy concentration required"
        case .extreme:  return "Academic/technical level — deep focus mode"
        }
    }
}

// MARK: - Supporting Models

struct FeedTemperatureEntry: Codable {
    let feedName: String
    let articleCount: Int
    let temperature: FeedTemperature
    let trend: FeedTrend
}

enum FeedTrend: String, Codable {
    case rising   = "📈 Rising"
    case stable   = "➡️ Stable"
    case falling  = "📉 Falling"
    case inactive = "💤 Inactive"
}

struct FeedForecastDay: Codable {
    let date: Date
    let condition: FeedWeatherCondition
    let expectedArticles: Int
    let confidence: Double
}

struct WeatherAlert: Codable {
    let type: WeatherAlertType
    let message: String
    let emoji: String
    let severity: AlertSeverity
}

enum WeatherAlertType: String, Codable {
    case activitySpike  = "Activity Spike"
    case sentimentDrop  = "Sentiment Drop"
    case readingBacklog = "Reading Backlog"
    case feedInactive   = "Feed Inactive"
    case topicFlood     = "Topic Flood"
    case longReadSurge  = "Long Read Surge"
}

enum AlertSeverity: String, Codable {
    case info     = "Info"
    case warning  = "Warning"
    case critical = "Critical"
}

// MARK: - Weather Report

struct FeedWeatherReport: Codable {
    let generatedAt: Date
    let periodStart: Date
    let periodEnd: Date
    let condition: FeedWeatherCondition
    let temperature: FeedTemperature
    let pressure: FeedPressure
    let windSpeed: FeedWindSpeed
    let uvIndex: FeedUVIndex
    let totalArticles: Int
    let articlesPerDay: Double
    let avgWordCount: Int
    let positiveRatio: Double
    let activityChangeRatio: Double
    let feedTemperatures: [FeedTemperatureEntry]
    let forecast: [FeedForecastDay]
    let advisory: String
    let alerts: [WeatherAlert]

    var summary: String {
        var parts: [String] = []
        parts.append("📡 Feed Weather Report")
        parts.append("Generated: \(FeedWeatherReport.dateFormatter.string(from: generatedAt))")
        parts.append("")
        parts.append("Condition: \(condition.rawValue)")
        parts.append("Temperature: \(temperature.rawValue) (\(String(format: "%.1f", articlesPerDay)) articles/day)")
        parts.append("Pressure: \(pressure.rawValue) (avg \(avgWordCount) words)")
        parts.append("Wind: \(windSpeed.rawValue)")
        parts.append("UV Index: \(uvIndex.rawValue)")
        parts.append("Sunshine: \(String(format: "%.0f%%", positiveRatio * 100)) positive")
        parts.append("")
        parts.append("💬 \(advisory)")
        if !alerts.isEmpty {
            parts.append("")
            parts.append("⚠️ Alerts:")
            for alert in alerts {
                parts.append("  • \(alert.emoji) \(alert.message)")
            }
        }
        if !forecast.isEmpty {
            parts.append("")
            parts.append("📅 Forecast:")
            for day in forecast.prefix(3) {
                parts.append("  \(FeedWeatherReport.shortDateFormatter.string(from: day.date)): \(day.condition.rawValue) — \(day.expectedArticles) articles expected")
            }
        }
        return parts.joined(separator: "\n")
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()
}

// MARK: - Feed Weather Reporter

class FeedWeatherReporter {

    static let shared = FeedWeatherReporter()

    var reportPeriodDays: Int = 7
    var forecastDays: Int = 5
    static let minimumArticles = 3

    private let store = UserDefaultsCodableStore<[FeedWeatherReport]>(
        key: "feed_weather_reports",
        dateStrategy: .iso8601
    )

    private var reportHistory: [FeedWeatherReport] = []

    init() {
        reportHistory = store.load() ?? []
    }

    // MARK: - Report Generation

    func generateReport(from stories: [Story], periodDays: Int? = nil) -> FeedWeatherReport? {
        let days = periodDays ?? reportPeriodDays

        guard stories.count >= FeedWeatherReporter.minimumArticles else {
            return nil
        }

        let now = Date()
        let periodStart = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now

        let totalArticles = stories.count
        let articlesPerDay = Double(totalArticles) / max(1.0, Double(days))

        let wordCounts = stories.map { countWords(in: $0.body) }
        let avgWordCount = wordCounts.isEmpty ? 0 : wordCounts.reduce(0, +) / wordCounts.count

        let sentiments = stories.map { analyzeSentiment(text: $0.title + " " + $0.body) }
        let positiveCount = sentiments.filter { $0 > 0 }.count
        let positiveRatio = sentiments.isEmpty ? 0.5 : Double(positiveCount) / Double(sentiments.count)

        let midpoint = stories.count / 2
        let firstHalf = max(1, midpoint)
        let secondHalf = max(1, stories.count - firstHalf)
        let changeRatio = Double(secondHalf) / Double(firstHalf)

        let fleschScores = stories.map { computeFleschEase(text: $0.body) }
        let avgFlesch = fleschScores.isEmpty ? 60.0 : fleschScores.reduce(0, +) / Double(fleschScores.count)

        let temperature = FeedTemperature.from(articlesPerDay: Int(articlesPerDay))
        let pressure = FeedPressure.from(avgWordCount: avgWordCount)
        let windSpeed = FeedWindSpeed.from(changeRatio: changeRatio)
        let uvIndex = FeedUVIndex.from(fleschScore: avgFlesch)
        let condition = determineCondition(
            articlesPerDay: articlesPerDay,
            positiveRatio: positiveRatio,
            changeRatio: changeRatio,
            avgFlesch: avgFlesch
        )

        let feedGroups = Dictionary(grouping: stories, by: { $0.sourceFeedName ?? "Unknown" })
        let feedTemps = feedGroups.map { (name, feedStories) -> FeedTemperatureEntry in
            let count = feedStories.count
            let feedPerDay = Double(count) / max(1.0, Double(days))
            let temp = FeedTemperature.from(articlesPerDay: Int(feedPerDay))

            let trend: FeedTrend
            if count <= 1 {
                trend = .inactive
            } else {
                let feedMid = count / 2
                let first = max(1, feedMid)
                let second = count - first
                let ratio = Double(second) / Double(first)
                if ratio > 1.3 { trend = .rising }
                else if ratio < 0.7 { trend = .falling }
                else { trend = .stable }
            }

            return FeedTemperatureEntry(
                feedName: name, articleCount: count,
                temperature: temp, trend: trend
            )
        }.sorted { $0.articleCount > $1.articleCount }

        let forecast = generateForecast(
            currentRate: articlesPerDay,
            currentCondition: condition,
            changeRatio: changeRatio
        )

        let alerts = generateAlerts(
            articlesPerDay: articlesPerDay,
            positiveRatio: positiveRatio,
            changeRatio: changeRatio,
            avgWordCount: avgWordCount,
            feedTemps: feedTemps
        )

        let report = FeedWeatherReport(
            generatedAt: now, periodStart: periodStart, periodEnd: now,
            condition: condition, temperature: temperature,
            pressure: pressure, windSpeed: windSpeed, uvIndex: uvIndex,
            totalArticles: totalArticles, articlesPerDay: articlesPerDay,
            avgWordCount: avgWordCount, positiveRatio: positiveRatio,
            activityChangeRatio: changeRatio,
            feedTemperatures: feedTemps, forecast: forecast,
            advisory: condition.advisory, alerts: alerts
        )

        reportHistory.append(report)
        if reportHistory.count > 30 {
            reportHistory = Array(reportHistory.suffix(30))
        }
        store.save(reportHistory)
        NotificationCenter.default.post(name: .feedWeatherDidUpdate, object: report)

        return report
    }

    // MARK: - History

    func getReportHistory() -> [FeedWeatherReport] {
        return reportHistory.sorted { $0.generatedAt > $1.generatedAt }
    }

    func latestReport() -> FeedWeatherReport? {
        return reportHistory.max { $0.generatedAt < $1.generatedAt }
    }

    func clearHistory() {
        reportHistory = []
        store.save(reportHistory)
    }

    // MARK: - Condition Logic

    private func determineCondition(
        articlesPerDay: Double, positiveRatio: Double,
        changeRatio: Double, avgFlesch: Double
    ) -> FeedWeatherCondition {
        if articlesPerDay > 50 { return .heatwave }
        if articlesPerDay < 2 { return .snowy }
        if changeRatio > 3.0 { return .windy }
        if positiveRatio < 0.3 && changeRatio > 1.5 { return .stormy }
        if positiveRatio < 0.3 { return .rainy }
        if avgFlesch < 30 { return .foggy }
        if positiveRatio > 0.7 && articlesPerDay < 15 { return .sunny }
        if positiveRatio > 0.6 { return .partlyCloudy }
        if articlesPerDay < 5 { return .clear }
        return .cloudy
    }

    // MARK: - Forecast

    private func generateForecast(
        currentRate: Double, currentCondition: FeedWeatherCondition,
        changeRatio: Double
    ) -> [FeedForecastDay] {
        var days: [FeedForecastDay] = []
        let calendar = Calendar.current
        let now = Date()

        for i in 1...forecastDays {
            guard let date = calendar.date(byAdding: .day, value: i, to: now) else { continue }
            let dampening = pow(0.7, Double(i))
            let trendFactor = 1.0 + (changeRatio - 1.0) * dampening
            let expectedArticles = max(0, Int(currentRate * trendFactor))

            let condition: FeedWeatherCondition
            if i <= 1 { condition = currentCondition }
            else if i <= 3 {
                if expectedArticles > 35 { condition = .partlyCloudy }
                else if expectedArticles < 5 { condition = .clear }
                else { condition = .partlyCloudy }
            } else {
                condition = .partlyCloudy
            }

            let confidence = max(0.2, 1.0 - Double(i) * 0.15)
            days.append(FeedForecastDay(
                date: date, condition: condition,
                expectedArticles: expectedArticles, confidence: confidence
            ))
        }
        return days
    }

    // MARK: - Alerts

    private func generateAlerts(
        articlesPerDay: Double, positiveRatio: Double,
        changeRatio: Double, avgWordCount: Int,
        feedTemps: [FeedTemperatureEntry]
    ) -> [WeatherAlert] {
        var alerts: [WeatherAlert] = []

        if changeRatio > 2.5 {
            alerts.append(WeatherAlert(
                type: .activitySpike,
                message: "Article volume is \(String(format: "%.1f", changeRatio))x above normal",
                emoji: "📈",
                severity: changeRatio > 4.0 ? .critical : .warning
            ))
        }

        if positiveRatio < 0.25 {
            alerts.append(WeatherAlert(
                type: .sentimentDrop,
                message: "Only \(String(format: "%.0f%%", positiveRatio * 100)) of content is positive",
                emoji: "😞", severity: .warning
            ))
        }

        let inactiveFeeds = feedTemps.filter { $0.trend == .inactive }
        if inactiveFeeds.count >= 2 {
            let names = inactiveFeeds.prefix(3).map { $0.feedName }.joined(separator: ", ")
            alerts.append(WeatherAlert(
                type: .feedInactive,
                message: "\(inactiveFeeds.count) feeds are inactive: \(names)",
                emoji: "💤", severity: .info
            ))
        }

        if avgWordCount > 800 {
            alerts.append(WeatherAlert(
                type: .longReadSurge,
                message: "Average article length is \(avgWordCount) words — heavy reading ahead",
                emoji: "📚", severity: .info
            ))
        }

        let totalArticles = feedTemps.reduce(0) { $0 + $1.articleCount }
        if totalArticles > 0 {
            for feed in feedTemps {
                let share = Double(feed.articleCount) / Double(totalArticles)
                if share > 0.6 && feedTemps.count > 1 {
                    alerts.append(WeatherAlert(
                        type: .topicFlood,
                        message: "\(feed.feedName) accounts for \(String(format: "%.0f%%", share * 100)) of all articles",
                        emoji: "🌊", severity: .info
                    ))
                    break
                }
            }
        }

        return alerts
    }

    // MARK: - Text Helpers

    func countWords(in text: String) -> Int {
        return text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.count
    }

    func analyzeSentiment(text: String) -> Double {
        let words = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return 0.0 }

        let positive: Set<String> = [
            "good", "great", "excellent", "amazing", "wonderful", "fantastic",
            "brilliant", "outstanding", "superb", "love", "happy", "joy",
            "success", "improve", "growth", "positive", "win", "best",
            "beautiful", "innovative", "breakthrough", "celebrate", "progress",
            "achievement", "inspiring", "hope", "opportunity", "benefit",
            "exciting", "impressive", "remarkable", "triumph", "advance"
        ]
        let negative: Set<String> = [
            "bad", "terrible", "awful", "horrible", "worst", "fail",
            "failure", "crisis", "disaster", "tragic", "death", "war",
            "attack", "threat", "danger", "fear", "violence", "crime",
            "corruption", "scandal", "collapse", "crash", "decline",
            "problem", "risk", "warning", "conflict", "suffer", "loss",
            "devastate", "alarming", "controversial", "exploit", "breach"
        ]

        var score = 0
        for word in words {
            if positive.contains(word) { score += 1 }
            if negative.contains(word) { score -= 1 }
        }
        return max(-1.0, min(1.0, Double(score) / max(1.0, Double(words.count) * 0.1)))
    }

    func computeFleschEase(text: String) -> Double {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        let syllables = words.reduce(0) { $0 + countSyllables(in: $1) }

        let sc = max(1, sentences.count)
        let wc = max(1, words.count)
        let asl = Double(wc) / Double(sc)
        let asw = Double(syllables) / Double(wc)
        return 206.835 - (1.015 * asl) - (84.6 * asw)
    }

    func countSyllables(in word: String) -> Int {
        let lowered = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
        guard !lowered.isEmpty else { return 0 }

        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        var count = 0
        var prevWasVowel = false

        for char in lowered {
            let isVowel = vowels.contains(char)
            if isVowel && !prevWasVowel { count += 1 }
            prevWasVowel = isVowel
        }
        if lowered.hasSuffix("e") && count > 1 { count -= 1 }
        return max(1, count)
    }

    // MARK: - Comparison

    func compareReports(_ older: FeedWeatherReport, _ newer: FeedWeatherReport) -> String {
        var changes: [String] = []
        if older.temperature != newer.temperature {
            changes.append("Temperature: \(older.temperature.rawValue) → \(newer.temperature.rawValue)")
        }
        if older.condition != newer.condition {
            changes.append("Condition: \(older.condition.rawValue) → \(newer.condition.rawValue)")
        }
        if older.pressure != newer.pressure {
            changes.append("Pressure: \(older.pressure.rawValue) → \(newer.pressure.rawValue)")
        }
        let delta = newer.articlesPerDay - older.articlesPerDay
        if abs(delta) > 2 {
            changes.append("Activity \(delta > 0 ? "up" : "down") \(String(format: "%.1f", abs(delta))) articles/day")
        }
        let sDelta = newer.positiveRatio - older.positiveRatio
        if abs(sDelta) > 0.1 {
            changes.append("Sentiment \(sDelta > 0 ? "improving" : "declining") (\(String(format: "%.0f%%", sDelta * 100)))")
        }
        return changes.isEmpty ? "No significant changes since last report." : changes.joined(separator: "\n")
    }
}
