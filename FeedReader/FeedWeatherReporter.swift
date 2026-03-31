//
//  FeedWeatherReporter.swift
//  FeedReader
//
//  Generates a "weather report" metaphor for feed reading activity.
//  Temperature = article volume, Pressure = article length,
//  Wind = rate of change, UV = reading complexity, etc.
//

import Foundation

// MARK: - Enums

/// Feed activity level expressed as temperature.
enum FeedTemperature: String, CustomStringConvertible {
    case freezing = "❄️ Freezing"
    case cold     = "🥶 Cold"
    case cool     = "🌤 Cool"
    case mild     = "😊 Mild"
    case warm     = "☀️ Warm"
    case hot      = "🔥 Hot"
    case scorching = "🌋 Scorching"

    var description: String {
        switch self {
        case .freezing:  return "Almost no activity — feeds are dormant"
        case .cold:      return "Very light reading — just a trickle"
        case .cool:      return "Light activity — a handful of articles"
        case .mild:      return "Moderate flow — comfortable reading pace"
        case .warm:      return "Active feeds — plenty to read"
        case .hot:       return "High volume — hard to keep up"
        case .scorching: return "Overwhelming — information overload!"
        }
    }

    static func from(articlesPerDay: Double) -> FeedTemperature {
        switch articlesPerDay {
        case ..<2:    return .freezing
        case ..<5:    return .cold
        case ..<10:   return .cool
        case ..<20:   return .mild
        case ..<40:   return .warm
        case ..<50:   return .hot
        default:      return .scorching
        }
    }
}

/// Reading pressure based on average word count.
enum FeedPressure: String, CustomStringConvertible {
    case low      = "Low"
    case moderate = "Moderate"
    case high     = "High"
    case extreme  = "Extreme"

    var description: String {
        switch self {
        case .low:      return "Short, easy reads"
        case .moderate: return "Standard-length articles"
        case .high:     return "Long-form content"
        case .extreme:  return "Very dense, lengthy articles"
        }
    }

    static func from(avgWordCount: Double) -> FeedPressure {
        switch avgWordCount {
        case ..<200:  return .low
        case ..<500:  return .moderate
        case ..<1000: return .high
        default:      return .extreme
        }
    }
}

/// Rate of change in feed activity.
enum FeedWindSpeed: String, CustomStringConvertible {
    case calm      = "Calm"
    case breeze    = "Breeze"
    case gusty     = "Gusty"
    case gale      = "Gale"
    case hurricane = "Hurricane"

    var description: String {
        switch self {
        case .calm:      return "Steady, predictable flow"
        case .breeze:    return "Slight variation in activity"
        case .gusty:     return "Noticeable spikes in content"
        case .gale:      return "Major swings in volume"
        case .hurricane: return "Wildly unpredictable activity"
        }
    }

    static func from(changeRatio: Double) -> FeedWindSpeed {
        switch changeRatio {
        case ..<0.8:  return .calm
        case ..<1.5:  return .breeze
        case ..<2.5:  return .gusty
        case ..<4.0:  return .gale
        default:      return .hurricane
        }
    }
}

/// Reading complexity as UV index (inverse of Flesch score).
enum FeedUVIndex: String, CustomStringConvertible {
    case low      = "Low"
    case moderate = "Moderate"
    case high     = "High"
    case veryHigh = "Very High"
    case extreme  = "Extreme"

    var description: String {
        switch self {
        case .low:      return "Easy, accessible reading"
        case .moderate: return "Standard complexity"
        case .high:     return "Challenging content"
        case .veryHigh: return "Academic-level difficulty"
        case .extreme:  return "Extremely dense material"
        }
    }

    static func from(fleschScore: Double) -> FeedUVIndex {
        switch fleschScore {
        case 70...:   return .low
        case 50...:   return .moderate
        case 30...:   return .high
        case 10...:   return .veryHigh
        default:      return .extreme
        }
    }
}

/// Weather conditions derived from sentiment + volume patterns.
enum FeedWeatherCondition: String, CaseIterable {
    case sunny       = "☀️ Sunny"
    case cloudy      = "☁️ Cloudy"
    case rainy       = "🌧 Rainy"
    case stormy      = "⛈ Stormy"
    case foggy       = "🌫 Foggy"
    case snowy       = "❄️ Snowy"
    case rainbow     = "🌈 Rainbow"
    case heatwave    = "🥵 Heatwave"

    var advisory: String {
        switch self {
        case .sunny:    return "Great reading conditions! Enjoy your feeds."
        case .cloudy:   return "Mixed content ahead — pace yourself."
        case .rainy:    return "Negative sentiment trending — take breaks."
        case .stormy:   return "Heavy negative content — consider filtering."
        case .foggy:    return "Low activity and unclear trends."
        case .snowy:    return "Feeds are quiet — good time to catch up on saved articles."
        case .rainbow:  return "Positive shift after a rough patch — enjoy the good news!"
        case .heatwave: return "Extremely high volume — prioritize ruthlessly."
        }
    }
}

// MARK: - Alert

enum FeedAlertType: String {
    case topicFlood    = "Topic Flood"
    case longReadSurge = "Long Read Surge"
    case sentimentDrop = "Sentiment Drop"
    case volumeSpike   = "Volume Spike"
}

struct FeedAlert {
    let type: FeedAlertType
    let message: String
    let severity: Int // 1-5
}

// MARK: - Per-Feed Temperature

struct FeedTemperatureEntry {
    let feedName: String
    let articleCount: Int
    let temperature: FeedTemperature
}

// MARK: - Forecast Day

struct ForecastDay {
    let date: Date
    let expectedArticles: Int
    let expectedTemperature: FeedTemperature
    let confidence: Double
}

// MARK: - Weather Report

struct FeedWeatherReport {
    let generatedAt: Date
    let periodStart: Date
    let periodEnd: Date

    let totalArticles: Int
    let articlesPerDay: Double
    let avgWordCount: Double
    let positiveRatio: Double

    let temperature: FeedTemperature
    let pressure: FeedPressure
    let windSpeed: FeedWindSpeed
    let uvIndex: FeedUVIndex
    let condition: FeedWeatherCondition

    let feedTemperatures: [FeedTemperatureEntry]
    let forecast: [ForecastDay]
    let alerts: [FeedAlert]

    var summary: String {
        var lines: [String] = []
        lines.append("📊 Feed Weather Report")
        lines.append("Period: \(DateFormatter.shortDate.string(from: periodStart)) – \(DateFormatter.shortDate.string(from: periodEnd))")
        lines.append("")
        lines.append("🌡 Temperature: \(temperature.rawValue) — \(temperature.description)")
        lines.append("📏 Pressure: \(pressure.rawValue) — \(pressure.description)")
        lines.append("💨 Wind: \(windSpeed.rawValue) — \(windSpeed.description)")
        lines.append("☀️ UV Index: \(uvIndex.rawValue) — \(uvIndex.description)")
        lines.append("🌤 Condition: \(condition.rawValue)")
        lines.append("")
        lines.append("📈 \(totalArticles) articles | \(String(format: "%.1f", articlesPerDay))/day | avg \(Int(avgWordCount)) words")
        if !feedTemperatures.isEmpty {
            lines.append("")
            lines.append("Per-Feed Breakdown:")
            for ft in feedTemperatures.prefix(5) {
                lines.append("  \(ft.feedName): \(ft.articleCount) articles — \(ft.temperature.rawValue)")
            }
        }
        if !alerts.isEmpty {
            lines.append("")
            lines.append("⚠️ Alerts:")
            for alert in alerts {
                lines.append("  [\(alert.type.rawValue)] \(alert.message)")
            }
        }
        return lines.joined(separator: "\n")
    }

    var advisory: String {
        return condition.advisory
    }
}

// MARK: - DateFormatter helper

private extension DateFormatter {
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()
}

// MARK: - FeedWeatherReporter

class FeedWeatherReporter {

    var reportPeriodDays: Int = 7
    var forecastDays: Int = 5

    private var history: [FeedWeatherReport] = []
    private let maxHistory = 30

    // MARK: - Public API

    func generateReport(from stories: [Story]) -> FeedWeatherReport? {
        guard stories.count >= 5 else {
            // Still store a minimal report if count >= 3
            if stories.count >= 3 {
                return buildReport(from: stories)
            }
            return nil
        }
        return buildReport(from: stories)
    }

    func getReportHistory() -> [FeedWeatherReport] {
        return history
    }

    func latestReport() -> FeedWeatherReport? {
        return history.last
    }

    func clearHistory() {
        history.removeAll()
    }

    func compareReports(_ a: FeedWeatherReport, _ b: FeedWeatherReport) -> String {
        var changes: [String] = []
        if a.temperature != b.temperature {
            changes.append("Temperature changed from \(a.temperature.rawValue) to \(b.temperature.rawValue)")
        }
        if a.pressure != b.pressure {
            changes.append("Pressure changed from \(a.pressure.rawValue) to \(b.pressure.rawValue)")
        }
        if a.windSpeed != b.windSpeed {
            changes.append("Wind changed from \(a.windSpeed.rawValue) to \(b.windSpeed.rawValue)")
        }
        if abs(a.articlesPerDay - b.articlesPerDay) > 2 {
            changes.append("Volume shifted from \(String(format: "%.1f", a.articlesPerDay)) to \(String(format: "%.1f", b.articlesPerDay)) articles/day")
        }
        if changes.isEmpty {
            return "No significant changes detected between reports."
        }
        return changes.joined(separator: "\n")
    }

    // MARK: - Text Analysis

    func analyzeSentiment(text: String) -> Double {
        guard !text.isEmpty else { return 0 }
        let words = text.lowercased().split(separator: " ").map(String.init)
        let positive = Set(["great", "wonderful", "amazing", "excellent", "brilliant",
                            "good", "fantastic", "awesome", "outstanding", "superb",
                            "happy", "joy", "love", "success", "achievement",
                            "progress", "positive", "win", "best", "perfect"])
        let negative = Set(["terrible", "awful", "horrible", "disaster", "crisis",
                            "failure", "bad", "worst", "tragic", "death",
                            "war", "conflict", "scandal", "collapse", "corruption",
                            "tragedy", "problem", "danger", "threat", "fear"])
        var score = 0.0
        for word in words {
            if positive.contains(word) { score += 1 }
            if negative.contains(word) { score -= 1 }
        }
        return score
    }

    func countWords(in text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return trimmed.split(separator: " ").count
    }

    func countSyllables(in word: String) -> Int {
        let w = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty else { return 0 }
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        var count = 0
        var prevVowel = false
        for ch in w {
            if vowels.contains(ch) {
                if !prevVowel { count += 1 }
                prevVowel = true
            } else {
                prevVowel = false
            }
        }
        // Silent e
        if w.hasSuffix("e") && count > 1 { count -= 1 }
        return max(count, 1)
    }

    func computeFleschEase(text: String) -> Double {
        let sentences = text.split { $0 == "." || $0 == "!" || $0 == "?" }.count
        guard sentences > 0 else { return 0 }
        let words = text.split(separator: " ")
        guard words.count > 0 else { return 0 }
        let totalSyllables = words.reduce(0) { $0 + countSyllables(in: String($1)) }
        let wordsPerSentence = Double(words.count) / Double(sentences)
        let syllablesPerWord = Double(totalSyllables) / Double(words.count)
        return 206.835 - 1.015 * wordsPerSentence - 84.6 * syllablesPerWord
    }

    // MARK: - Private

    private func buildReport(from stories: [Story]) -> FeedWeatherReport {
        let now = Date()
        let periodStart = Calendar.current.date(byAdding: .day, value: -reportPeriodDays, to: now)!
        let periodEnd = now

        let totalArticles = stories.count
        let articlesPerDay = Double(totalArticles) / max(Double(reportPeriodDays), 1)

        // Word counts
        let wordCounts = stories.map { countWords(in: $0.body) }
        let avgWordCount = wordCounts.isEmpty ? 0.0 : Double(wordCounts.reduce(0, +)) / Double(wordCounts.count)

        // Sentiment
        let sentiments = stories.map { analyzeSentiment(text: "\($0.title) \($0.body)") }
        let positiveCount = sentiments.filter { $0 > 0 }.count
        let positiveRatio = sentiments.isEmpty ? 0.5 : Double(positiveCount) / Double(sentiments.count)

        // Metrics
        let temperature = FeedTemperature.from(articlesPerDay: articlesPerDay)
        let pressure = FeedPressure.from(avgWordCount: avgWordCount)

        // Flesch
        let allText = stories.map { $0.body }.joined(separator: ". ")
        let fleschScore = computeFleschEase(text: allText)
        let uvIndex = FeedUVIndex.from(fleschScore: fleschScore)

        // Wind (use variance as proxy for change ratio)
        let changeRatio = wordCounts.count > 1 ? Double(wordCounts.max()!) / max(Double(wordCounts.min()!), 1) : 1.0
        let windSpeed = FeedWindSpeed.from(changeRatio: changeRatio)

        // Condition
        let avgSentiment = sentiments.isEmpty ? 0.0 : sentiments.reduce(0, +) / Double(sentiments.count)
        let condition = deriveCondition(temperature: temperature, avgSentiment: avgSentiment, articlesPerDay: articlesPerDay)

        // Per-feed breakdown
        var feedGroups: [String: [Story]] = [:]
        for story in stories {
            let name = story.sourceFeedName ?? "Unknown"
            feedGroups[name, default: []].append(story)
        }
        let feedTemperatures = feedGroups.map { (name, stories) -> FeedTemperatureEntry in
            let perDay = Double(stories.count) / max(Double(reportPeriodDays), 1)
            return FeedTemperatureEntry(feedName: name, articleCount: stories.count, temperature: FeedTemperature.from(articlesPerDay: perDay))
        }.sorted { $0.articleCount > $1.articleCount }

        // Alerts
        var alerts: [FeedAlert] = []
        // Topic flood: any single feed > 70% of total
        for ft in feedTemperatures {
            if Double(ft.articleCount) / Double(totalArticles) > 0.7 && feedTemperatures.count > 1 {
                alerts.append(FeedAlert(type: .topicFlood, message: "\(ft.feedName) dominates with \(ft.articleCount)/\(totalArticles) articles", severity: 3))
            }
        }
        // Long read surge
        if avgWordCount > 800 {
            alerts.append(FeedAlert(type: .longReadSurge, message: "Average article length is \(Int(avgWordCount)) words — very long reads", severity: 2))
        }
        // Sentiment drop
        if avgSentiment < -2 {
            alerts.append(FeedAlert(type: .sentimentDrop, message: "Overall sentiment is strongly negative", severity: 3))
        }

        // Forecast
        let forecast = (0..<forecastDays).map { dayOffset -> ForecastDay in
            let date = Calendar.current.date(byAdding: .day, value: dayOffset + 1, to: now)!
            let jitter = Double.random(in: 0.8...1.2)
            let expected = Int(articlesPerDay * jitter)
            let confidence = max(0.3, 1.0 - Double(dayOffset) * 0.15)
            return ForecastDay(date: date, expectedArticles: expected, expectedTemperature: temperature, confidence: confidence)
        }

        let report = FeedWeatherReport(
            generatedAt: now,
            periodStart: periodStart,
            periodEnd: periodEnd,
            totalArticles: totalArticles,
            articlesPerDay: articlesPerDay,
            avgWordCount: avgWordCount,
            positiveRatio: positiveRatio,
            temperature: temperature,
            pressure: pressure,
            windSpeed: windSpeed,
            uvIndex: uvIndex,
            condition: condition,
            feedTemperatures: feedTemperatures,
            forecast: forecast,
            alerts: alerts
        )

        history.append(report)
        if history.count > maxHistory {
            history.removeFirst(history.count - maxHistory)
        }

        return report
    }

    private func deriveCondition(temperature: FeedTemperature, avgSentiment: Double, articlesPerDay: Double) -> FeedWeatherCondition {
        if temperature == .scorching { return .heatwave }
        if temperature == .freezing || temperature == .cold { return .snowy }
        if avgSentiment < -3 { return .stormy }
        if avgSentiment < -1 { return .rainy }
        if avgSentiment > 2 { return .rainbow }
        if avgSentiment > 0 { return .sunny }
        if articlesPerDay < 3 { return .foggy }
        return .cloudy
    }
}
