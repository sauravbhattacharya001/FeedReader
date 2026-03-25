//
//  ArticleEngagementPredictor.swift
//  FeedReader
//
//  Predicts how likely the user is to finish reading an article based
//  on their historical reading patterns.  Learns from past sessions to
//  build a lightweight, on-device model of reading preferences.
//
//  Signals used:
//    - Word count (articles too long or too short may get abandoned)
//    - Feed source (some feeds consistently hold attention better)
//    - Time of day (morning reader vs. evening reader patterns)
//    - Day of week (weekday vs. weekend reading habits)
//    - Topic keywords (certain topics correlate with completion)
//
//  The predictor outputs an engagement score (0.0–1.0) and a human-
//  friendly label: "Likely to finish", "Might skim", "Probably skip".
//
//  Usage:
//    let predictor = ArticleEngagementPredictor()
//    predictor.recordOutcome(articleId: "abc", feedTitle: "Ars Technica",
//        wordCount: 1200, hour: 8, dayOfWeek: 2, keywords: ["apple","tech"],
//        completed: true)
//    let score = predictor.predict(feedTitle: "Ars Technica",
//        wordCount: 2500, hour: 8, dayOfWeek: 2, keywords: ["apple"])
//    // score.value = 0.73, score.label = "Likely to finish"
//
//  Persistence: JSON file in Documents directory.
//  Fully offline — no network, no dependencies beyond Foundation.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when a new reading outcome is recorded.
    static let engagementDataDidChange = Notification.Name("EngagementDataDidChangeNotification")
    /// Posted when the model is retrained.
    static let engagementModelDidUpdate = Notification.Name("EngagementModelDidUpdateNotification")
}

// MARK: - Types

/// Represents the engagement prediction for an article.
struct EngagementPrediction: Codable, Equatable {
    /// Score from 0.0 (will skip) to 1.0 (will definitely finish).
    let value: Double
    /// Human-friendly label.
    let label: String
    /// Breakdown of contributing factors.
    let factors: [EngagementFactor]

    /// Convenience label from score.
    static func labelFor(score: Double) -> String {
        switch score {
        case 0.8...: return "Likely to finish"
        case 0.5..<0.8: return "Might skim"
        case 0.3..<0.5: return "Probably skip"
        default: return "Very unlikely to read"
        }
    }
}

/// A single factor contributing to the engagement prediction.
struct EngagementFactor: Codable, Equatable {
    /// Factor name (e.g., "word_count", "feed_affinity").
    let name: String
    /// Factor weight (positive = boosts, negative = reduces).
    let weight: Double
    /// Human-friendly explanation.
    let explanation: String
}

/// A recorded reading outcome for learning.
struct ReadingOutcome: Codable, Equatable, Identifiable {
    let id: String // article ID
    let feedTitle: String
    let wordCount: Int
    let hour: Int          // 0-23
    let dayOfWeek: Int     // 1=Sun, 7=Sat
    let keywords: [String]
    let completed: Bool
    let timestamp: Date
}

// MARK: - Learned Weights

/// Simple statistical model learned from outcomes.
struct EngagementModel: Codable, Equatable {
    /// Completion rate per feed (feed title → rate 0-1).
    var feedCompletionRates: [String: Double] = [:]
    /// Completion rate per hour bucket (0-23 → rate).
    var hourCompletionRates: [Int: Double] = [:]
    /// Completion rate per day of week.
    var dayCompletionRates: [Int: Double] = [:]
    /// Optimal word count range (articles in this range complete most).
    var optimalWordCountMin: Int = 300
    var optimalWordCountMax: Int = 2000
    /// Keyword affinity scores.
    var keywordScores: [String: Double] = [:]
    /// Global baseline completion rate.
    var baselineRate: Double = 0.5
    /// Number of outcomes used to train.
    var sampleCount: Int = 0
}

// MARK: - ArticleEngagementPredictor

/// Predicts article engagement based on historical reading patterns.
final class ArticleEngagementPredictor {

    // MARK: Properties

    private(set) var outcomes: [ReadingOutcome] = []
    private(set) var model: EngagementModel = EngagementModel()
    private let fileManager = FileManager.default

    /// Maximum outcomes to retain (FIFO).
    let maxOutcomes = 5000

    // MARK: Init

    init() {
        load()
    }

    // MARK: Record Outcome

    /// Records a reading outcome and optionally retrains the model.
    func recordOutcome(articleId: String, feedTitle: String, wordCount: Int,
                       hour: Int, dayOfWeek: Int, keywords: [String],
                       completed: Bool, autoRetrain: Bool = true) {
        let outcome = ReadingOutcome(
            id: articleId,
            feedTitle: feedTitle,
            wordCount: wordCount,
            hour: hour,
            dayOfWeek: dayOfWeek,
            keywords: keywords,
            completed: completed,
            timestamp: Date()
        )
        outcomes.append(outcome)

        // Trim oldest if over limit
        if outcomes.count > maxOutcomes {
            outcomes = Array(outcomes.suffix(maxOutcomes))
        }

        save()
        NotificationCenter.default.post(name: .engagementDataDidChange, object: self)

        if autoRetrain {
            retrain()
        }
    }

    // MARK: Predict

    /// Predicts engagement for an article with the given characteristics.
    func predict(feedTitle: String, wordCount: Int, hour: Int,
                 dayOfWeek: Int, keywords: [String] = []) -> EngagementPrediction {

        guard model.sampleCount >= 5 else {
            // Not enough data; return neutral prediction
            return EngagementPrediction(
                value: 0.5,
                label: "Not enough data yet",
                factors: [EngagementFactor(name: "sample_size",
                    weight: 0.0,
                    explanation: "Need at least 5 reading sessions to predict")]
            )
        }

        var factors: [EngagementFactor] = []
        var weightedSum = 0.0
        var totalWeight = 0.0

        // Factor 1: Feed affinity
        let feedRate = model.feedCompletionRates[feedTitle] ?? model.baselineRate
        let feedWeight = 3.0
        weightedSum += feedRate * feedWeight
        totalWeight += feedWeight
        factors.append(EngagementFactor(
            name: "feed_affinity",
            weight: feedRate - model.baselineRate,
            explanation: String(format: "You finish %.0f%% of articles from \"%@\"",
                                feedRate * 100, feedTitle)
        ))

        // Factor 2: Time of day
        let hourRate = model.hourCompletionRates[hour] ?? model.baselineRate
        let hourWeight = 2.0
        weightedSum += hourRate * hourWeight
        totalWeight += hourWeight
        let hourLabel = hourName(hour)
        factors.append(EngagementFactor(
            name: "time_of_day",
            weight: hourRate - model.baselineRate,
            explanation: String(format: "You finish %.0f%% of articles read at %@",
                                hourRate * 100, hourLabel)
        ))

        // Factor 3: Day of week
        let dayRate = model.dayCompletionRates[dayOfWeek] ?? model.baselineRate
        let dayWeight = 1.0
        weightedSum += dayRate * dayWeight
        totalWeight += dayWeight
        factors.append(EngagementFactor(
            name: "day_of_week",
            weight: dayRate - model.baselineRate,
            explanation: String(format: "You finish %.0f%% of articles on %@s",
                                dayRate * 100, dayName(dayOfWeek))
        ))

        // Factor 4: Word count fit
        let wordCountScore = wordCountFitScore(wordCount)
        let wcWeight = 2.0
        weightedSum += wordCountScore * wcWeight
        totalWeight += wcWeight
        factors.append(EngagementFactor(
            name: "word_count",
            weight: wordCountScore - model.baselineRate,
            explanation: wordCountExplanation(wordCount, score: wordCountScore)
        ))

        // Factor 5: Keyword affinity (average of matching keywords)
        if !keywords.isEmpty {
            let kwScores = keywords.compactMap { model.keywordScores[$0.lowercased()] }
            if !kwScores.isEmpty {
                let avgKw = kwScores.reduce(0.0, +) / Double(kwScores.count)
                let kwWeight = 1.5
                weightedSum += avgKw * kwWeight
                totalWeight += kwWeight
                factors.append(EngagementFactor(
                    name: "topic_keywords",
                    weight: avgKw - model.baselineRate,
                    explanation: String(format: "Topic keywords suggest %.0f%% engagement",
                                        avgKw * 100)
                ))
            }
        }

        let score = totalWeight > 0 ? weightedSum / totalWeight : model.baselineRate
        let clampedScore = min(1.0, max(0.0, score))

        return EngagementPrediction(
            value: clampedScore,
            label: EngagementPrediction.labelFor(score: clampedScore),
            factors: factors
        )
    }

    // MARK: Retrain

    /// Rebuilds the model from all stored outcomes.
    func retrain() {
        guard !outcomes.isEmpty else { return }

        var newModel = EngagementModel()
        newModel.sampleCount = outcomes.count

        // Global baseline
        let completedCount = outcomes.filter { $0.completed }.count
        newModel.baselineRate = Double(completedCount) / Double(outcomes.count)

        // Per-feed rates
        let feedGroups = Dictionary(grouping: outcomes) { $0.feedTitle }
        for (feed, group) in feedGroups {
            let rate = Double(group.filter { $0.completed }.count) / Double(group.count)
            newModel.feedCompletionRates[feed] = rate
        }

        // Per-hour rates
        let hourGroups = Dictionary(grouping: outcomes) { $0.hour }
        for (hour, group) in hourGroups {
            let rate = Double(group.filter { $0.completed }.count) / Double(group.count)
            newModel.hourCompletionRates[hour] = rate
        }

        // Per-day rates
        let dayGroups = Dictionary(grouping: outcomes) { $0.dayOfWeek }
        for (day, group) in dayGroups {
            let rate = Double(group.filter { $0.completed }.count) / Double(group.count)
            newModel.dayCompletionRates[day] = rate
        }

        // Word count: find optimal range (middle 50% of completed articles)
        let completedWordCounts = outcomes.filter { $0.completed }
            .map { $0.wordCount }.sorted()
        if completedWordCounts.count >= 4 {
            let q1 = completedWordCounts[completedWordCounts.count / 4]
            let q3 = completedWordCounts[(completedWordCounts.count * 3) / 4]
            newModel.optimalWordCountMin = q1
            newModel.optimalWordCountMax = q3
        }

        // Keyword scores
        var keywordCompletions: [String: (completed: Int, total: Int)] = [:]
        for outcome in outcomes {
            for kw in outcome.keywords {
                let key = kw.lowercased()
                var entry = keywordCompletions[key] ?? (0, 0)
                entry.total += 1
                if outcome.completed { entry.completed += 1 }
                keywordCompletions[key] = entry
            }
        }
        for (kw, counts) in keywordCompletions where counts.total >= 3 {
            newModel.keywordScores[kw] = Double(counts.completed) / Double(counts.total)
        }

        model = newModel
        save()
        NotificationCenter.default.post(name: .engagementModelDidUpdate, object: self)
    }

    // MARK: Analytics

    /// Returns the top N feeds by completion rate (min 3 articles).
    func topFeeds(limit: Int = 5) -> [(feed: String, rate: Double, count: Int)] {
        let feedGroups = Dictionary(grouping: outcomes) { $0.feedTitle }
        return feedGroups
            .filter { $0.value.count >= 3 }
            .map { (feed: $0.key,
                     rate: Double($0.value.filter { $0.completed }.count) / Double($0.value.count),
                     count: $0.value.count) }
            .sorted { $0.rate > $1.rate }
            .prefix(limit)
            .map { $0 }
    }

    /// Returns the best hours for reading (sorted by completion rate).
    func bestHours(limit: Int = 5) -> [(hour: Int, rate: Double)] {
        return model.hourCompletionRates
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { (hour: $0.key, rate: $0.value) }
    }

    /// Returns a summary of reading engagement patterns.
    func summary() -> String {
        guard model.sampleCount >= 5 else {
            return "Not enough reading data yet (\(outcomes.count)/5 sessions needed)."
        }

        var lines: [String] = []
        lines.append("📊 Engagement Summary (\(model.sampleCount) articles tracked)")
        lines.append(String(format: "Overall completion rate: %.0f%%", model.baselineRate * 100))
        lines.append(String(format: "Sweet spot: %d–%d words",
                            model.optimalWordCountMin, model.optimalWordCountMax))

        let top = topFeeds(limit: 3)
        if !top.isEmpty {
            lines.append("\nTop feeds by engagement:")
            for t in top {
                lines.append(String(format: "  • %@ — %.0f%% (%d articles)",
                                    t.feed, t.rate * 100, t.count))
            }
        }

        let hours = bestHours(limit: 3)
        if !hours.isEmpty {
            lines.append("\nBest reading hours:")
            for h in hours {
                lines.append(String(format: "  • %@ — %.0f%% completion",
                                    hourName(h.hour), h.rate * 100))
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Exports all outcomes as JSON data.
    func exportJSON() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        struct Export: Codable {
            let outcomes: [ReadingOutcome]
            let model: EngagementModel
            let exportDate: Date
        }
        return try? encoder.encode(Export(outcomes: outcomes, model: model, exportDate: Date()))
    }

    /// Resets all data.
    func resetAll() {
        outcomes = []
        model = EngagementModel()
        save()
    }

    // MARK: Persistence

    private var storageURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("engagement_predictor.json")
    }

    private struct Storage: Codable {
        let outcomes: [ReadingOutcome]
        let model: EngagementModel
    }

    private func save() {
        let storage = Storage(outcomes: outcomes, model: model)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(storage) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let storage = try? decoder.decode(Storage.self, from: data) {
            outcomes = storage.outcomes
            model = storage.model
        }
    }

    // MARK: Helpers

    private func wordCountFitScore(_ wordCount: Int) -> Double {
        let min = model.optimalWordCountMin
        let max = model.optimalWordCountMax
        if wordCount >= min && wordCount <= max {
            return model.baselineRate + 0.15 // Boost for sweet spot
        }
        // Distance penalty
        let distance: Int
        if wordCount < min {
            distance = min - wordCount
        } else {
            distance = wordCount - max
        }
        let penalty = Double(distance) / 2000.0 // gradual falloff
        return Swift.max(0.1, model.baselineRate - penalty)
    }

    private func wordCountExplanation(_ wordCount: Int, score: Double) -> String {
        let min = model.optimalWordCountMin
        let max = model.optimalWordCountMax
        if wordCount >= min && wordCount <= max {
            return String(format: "%d words is in your sweet spot (%d–%d)",
                          wordCount, min, max)
        } else if wordCount < min {
            return String(format: "%d words is shorter than your usual (%d–%d)",
                          wordCount, min, max)
        } else {
            return String(format: "%d words is longer than your usual (%d–%d)",
                          wordCount, min, max)
        }
    }

    private func hourName(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        var components = DateComponents()
        components.hour = hour
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return "\(hour):00"
    }

    private func dayName(_ day: Int) -> String {
        let names = ["", "Sunday", "Monday", "Tuesday", "Wednesday",
                     "Thursday", "Friday", "Saturday"]
        return (day >= 1 && day <= 7) ? names[day] : "Day \(day)"
    }
}
