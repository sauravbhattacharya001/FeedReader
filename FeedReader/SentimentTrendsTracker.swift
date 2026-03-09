//
//  SentimentTrendsTracker.swift
//  FeedReader
//
//  Aggregates per-article sentiment scores over time to reveal trends
//  in the user's reading diet.  Tracks daily/weekly/monthly averages,
//  per-feed sentiment profiles, emotional composition shifts, and
//  negativity exposure alerts.
//
//  Built on ArticleSentimentAnalyzer — each recorded sample stores the
//  pre-computed SentimentResult fields so the lexicon is not re-run at
//  query time.
//
//  Key features:
//  - Record sentiment for read articles
//  - Daily, weekly, monthly sentiment averages
//  - Per-feed sentiment profiles (avg score, dominant emotion, volume)
//  - Sentiment trend detection (improving, worsening, steady)
//  - Emotional composition over time (joy vs fear vs anger etc.)
//  - Negativity exposure alerts and weekly positivity ratio
//  - Feed sentiment ranking (most positive → most negative)
//  - Diet diversity scoring (balanced vs. one-sided reading)
//  - Export to JSON for external analysis
//
//  Persistence: UserDefaults via Codable.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when a new sentiment sample is recorded.
    static let sentimentTrendsDidUpdate = Notification.Name("SentimentTrendsDidUpdateNotification")
    /// Posted when negativity exposure exceeds the alert threshold.
    static let sentimentNegativityAlert = Notification.Name("SentimentNegativityAlertNotification")
}

// MARK: - Models

/// A single sentiment data point linked to an article.
struct SentimentSample: Codable, Equatable {
    let id: String
    let articleTitle: String
    let feedName: String
    let recordedAt: Date
    /// Normalised score from -1.0 (most negative) to 1.0 (most positive).
    let score: Double
    /// String-encoded SentimentLabel raw value for Codable round-trip.
    let label: String
    /// String-encoded DominantEmotion raw value.
    let dominantEmotion: String
    /// Positive word count in the article.
    let positiveWords: Int
    /// Negative word count in the article.
    let negativeWords: Int
    /// Article word count.
    let wordCount: Int

    init(articleTitle: String, feedName: String, score: Double,
         label: String, dominantEmotion: String,
         positiveWords: Int, negativeWords: Int, wordCount: Int,
         recordedAt: Date = Date()) {
        self.id = UUID().uuidString
        self.articleTitle = articleTitle
        self.feedName = feedName
        self.score = max(-1, min(1, score))
        self.label = label
        self.dominantEmotion = dominantEmotion
        self.positiveWords = positiveWords
        self.negativeWords = negativeWords
        self.wordCount = wordCount
        self.recordedAt = recordedAt
    }
}

/// Aggregated sentiment for a time bucket (day, week, month).
struct SentimentAggregate: Equatable {
    let periodLabel: String
    let periodStart: Date
    let sampleCount: Int
    let averageScore: Double
    let medianScore: Double
    let minScore: Double
    let maxScore: Double
    let positivityRatio: Double      // fraction of samples with score > 0
    let dominantEmotion: String
    let articleCount: Int
}

/// Per-feed sentiment profile.
struct FeedSentimentProfile: Equatable {
    let feedName: String
    let sampleCount: Int
    let averageScore: Double
    let medianScore: Double
    let dominantEmotion: String
    let positivityRatio: Double
    let trend: SentimentTrend
    let recentScore: Double?         // average of last 5 samples

    /// Human-readable sentiment description.
    var sentimentDescription: String {
        if averageScore > 0.3 { return "Positive" }
        if averageScore > 0.05 { return "Slightly Positive" }
        if averageScore > -0.05 { return "Neutral" }
        if averageScore > -0.3 { return "Slightly Negative" }
        return "Negative"
    }
}

/// Sentiment trend direction.
enum SentimentTrend: String, Codable {
    case improving
    case worsening
    case steady
    case insufficientData
}

/// Emotional composition snapshot.
struct EmotionalComposition: Equatable {
    let sampleCount: Int
    /// Fraction of articles per emotion (values sum to ~1.0).
    let emotionShares: [String: Double]
    /// Dominant emotion (highest share).
    let dominant: String
    /// Diversity score 0-1 (1 = evenly spread across emotions).
    let diversity: Double
}

/// Overall diet health report.
struct SentimentDietReport: Equatable {
    let totalSamples: Int
    let overallAverage: Double
    let overallLabel: String
    let weeklyAverage: Double
    let trend: SentimentTrend
    let positivityRatio: Double
    let negativityExposure: Double
    let emotionalDiversity: Double
    let topPositiveFeeds: [String]
    let topNegativeFeeds: [String]
    let recommendation: String
}

// MARK: - SentimentTrendsTracker

/// Tracks sentiment trends across the user's reading history.
class SentimentTrendsTracker {

    // MARK: - Constants

    /// Maximum samples to keep.
    static let maxSamples = 10000

    /// Threshold below which a weekly average triggers a negativity alert.
    static let negativityAlertThreshold: Double = -0.2

    /// UserDefaults persistence key.
    private static let userDefaultsKey = "SentimentTrendsTracker.samples"

    // MARK: - Date Formatters (Cached)

    private static let dayFormatter = DateFormatting.isoDate

    private static let weekFormatter = DateFormatting.yearWeek

    private static let monthFormatter = DateFormatting.yearMonth

    // MARK: - State

    private(set) var samples: [SentimentSample] = []
    private let calendar: Calendar
    private let store: UserDefaultsCodableStore<[SentimentSample]>

    // MARK: - Init

    init(calendar: Calendar = .current) {
        self.calendar = calendar
        self.store = UserDefaultsCodableStore(key: SentimentTrendsTracker.userDefaultsKey)
        load()
    }

    /// Init for testing with pre-loaded samples (no persistence).
    init(samples: [SentimentSample], calendar: Calendar = .current) {
        self.calendar = calendar
        self.store = UserDefaultsCodableStore(key: "SentimentTrendsTracker.test.\(UUID().uuidString)")
        self.samples = samples
    }

    // MARK: - Recording

    /// Record an article's sentiment.  Runs `ArticleSentimentAnalyzer.analyze`
    /// and stores the result.
    ///
    /// - Returns: The recorded sample, or `nil` if the text was empty.
    @discardableResult
    func recordArticle(title: String, feedName: String, text: String,
                       at date: Date = Date()) -> SentimentSample? {
        guard !text.isEmpty else { return nil }

        let result = ArticleSentimentAnalyzer.analyze(text)

        let sample = SentimentSample(
            articleTitle: title,
            feedName: feedName,
            score: result.score,
            label: result.label.rawValue,
            dominantEmotion: result.dominantEmotion.rawValue,
            positiveWords: result.positiveWordCount,
            negativeWords: result.negativeWordCount,
            wordCount: result.wordCount,
            recordedAt: date
        )

        samples.insert(sample, at: 0) // newest first
        pruneIfNeeded()
        save()

        NotificationCenter.default.post(name: .sentimentTrendsDidUpdate, object: nil)

        // Check negativity alert
        checkNegativityAlert()

        return sample
    }

    /// Record a pre-computed sentiment sample (for batch import or testing).
    @discardableResult
    func recordSample(_ sample: SentimentSample) -> SentimentSample {
        samples.insert(sample, at: 0)
        pruneIfNeeded()
        save()
        NotificationCenter.default.post(name: .sentimentTrendsDidUpdate, object: nil)
        return sample
    }

    /// Remove a sample by ID.
    @discardableResult
    func removeSample(id: String) -> Bool {
        let before = samples.count
        samples.removeAll { $0.id == id }
        if samples.count < before {
            save()
            return true
        }
        return false
    }

    /// Remove all samples.
    func clearAll() {
        samples.removeAll()
        save()
    }

    // MARK: - Aggregation

    /// Daily sentiment averages for the last N days.
    func dailyAverages(lastDays: Int = 30, asOf date: Date = Date()) -> [SentimentAggregate] {
        var results: [SentimentAggregate] = []
        for i in 0..<lastDays {
            guard let day = calendar.date(byAdding: .day, value: -i, to: date) else { continue }
            let dayStart = calendar.startOfDay(for: day)
            let daySamples = samples.filter { calendar.isDate($0.recordedAt, inSameDayAs: dayStart) }
            if daySamples.isEmpty { continue }
            results.append(aggregate(
                daySamples,
                label: Self.dayFormatter.string(from: dayStart),
                start: dayStart
            ))
        }
        return results
    }

    /// Weekly sentiment averages for the last N weeks.
    func weeklyAverages(lastWeeks: Int = 12, asOf date: Date = Date()) -> [SentimentAggregate] {
        var results: [SentimentAggregate] = []
        for i in 0..<lastWeeks {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -i, to: date) else { continue }
            let startOfWeek = startOfWeekContaining(weekStart)
            guard let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek) else { continue }
            let weekSamples = samples.filter { $0.recordedAt >= startOfWeek && $0.recordedAt < endOfWeek }
            if weekSamples.isEmpty { continue }
            results.append(aggregate(
                weekSamples,
                label: Self.weekFormatter.string(from: startOfWeek),
                start: startOfWeek
            ))
        }
        return results
    }

    /// Monthly sentiment averages for the last N months.
    func monthlyAverages(lastMonths: Int = 6, asOf date: Date = Date()) -> [SentimentAggregate] {
        var results: [SentimentAggregate] = []
        for i in 0..<lastMonths {
            guard let monthStart = calendar.date(byAdding: .month, value: -i, to: date) else { continue }
            let comps = calendar.dateComponents([.year, .month], from: monthStart)
            guard let start = calendar.date(from: comps),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { continue }
            let monthSamples = samples.filter { $0.recordedAt >= start && $0.recordedAt < end }
            if monthSamples.isEmpty { continue }
            results.append(aggregate(
                monthSamples,
                label: Self.monthFormatter.string(from: start),
                start: start
            ))
        }
        return results
    }

    // MARK: - Feed Profiles

    /// Sentiment profile for a specific feed.
    func feedProfile(feedName: String) -> FeedSentimentProfile? {
        let feedSamples = samples.filter { $0.feedName == feedName }
        guard !feedSamples.isEmpty else { return nil }
        return buildFeedProfile(feedName: feedName, feedSamples: feedSamples)
    }

    /// Sentiment profiles for all feeds, sorted by average score (descending).
    func allFeedProfiles() -> [FeedSentimentProfile] {
        let grouped = Dictionary(grouping: samples, by: { $0.feedName })
        return grouped.map { buildFeedProfile(feedName: $0.key, feedSamples: $0.value) }
            .sorted { $0.averageScore > $1.averageScore }
    }

    /// Top N most positive feeds.
    func topPositiveFeeds(limit: Int = 5) -> [FeedSentimentProfile] {
        return Array(allFeedProfiles().prefix(limit))
    }

    /// Top N most negative feeds.
    func topNegativeFeeds(limit: Int = 5) -> [FeedSentimentProfile] {
        return Array(allFeedProfiles().reversed().prefix(limit))
    }

    // MARK: - Emotional Composition

    /// Emotional composition of all samples (or within a date range).
    func emotionalComposition(from start: Date? = nil, to end: Date? = nil) -> EmotionalComposition {
        var filtered = samples
        if let s = start { filtered = filtered.filter { $0.recordedAt >= s } }
        if let e = end { filtered = filtered.filter { $0.recordedAt <= e } }
        return buildComposition(filtered)
    }

    /// Compare emotional composition between two time periods.
    func compareComposition(
        period1Start: Date, period1End: Date,
        period2Start: Date, period2End: Date
    ) -> (period1: EmotionalComposition, period2: EmotionalComposition) {
        return (
            emotionalComposition(from: period1Start, to: period1End),
            emotionalComposition(from: period2Start, to: period2End)
        )
    }

    // MARK: - Trend Detection

    /// Overall sentiment trend over the last N days.
    func overallTrend(lastDays: Int = 30, asOf date: Date = Date()) -> SentimentTrend {
        guard let cutoff = calendar.date(byAdding: .day, value: -lastDays, to: date) else {
            return .insufficientData
        }
        let recent = samples.filter { $0.recordedAt >= cutoff }
        return detectTrend(recent)
    }

    /// Feed-specific sentiment trend.
    func feedTrend(feedName: String, lastDays: Int = 30, asOf date: Date = Date()) -> SentimentTrend {
        guard let cutoff = calendar.date(byAdding: .day, value: -lastDays, to: date) else {
            return .insufficientData
        }
        let recent = samples.filter { $0.feedName == feedName && $0.recordedAt >= cutoff }
        return detectTrend(recent)
    }

    // MARK: - Diet Report

    /// Generate a comprehensive sentiment diet health report.
    func dietReport(asOf date: Date = Date()) -> SentimentDietReport {
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: date) ?? date
        let weeklySamples = samples.filter { $0.recordedAt >= weekAgo }

        let overallAvg = samples.isEmpty ? 0 : averageScore(samples)
        let weeklyAvg = weeklySamples.isEmpty ? 0 : averageScore(weeklySamples)
        let trend = overallTrend(lastDays: 30, asOf: date)

        let posRatio = samples.isEmpty ? 0 :
            Double(samples.filter { $0.score > 0 }.count) / Double(samples.count)
        let negExposure = samples.isEmpty ? 0 :
            Double(samples.filter { $0.score < -0.3 }.count) / Double(samples.count)

        let comp = emotionalComposition()
        let profiles = allFeedProfiles()
        let topPos = profiles.prefix(3).map { $0.feedName }
        let topNeg = profiles.reversed().prefix(3).map { $0.feedName }

        let overallLabel: String
        if overallAvg > 0.3 { overallLabel = "Positive" }
        else if overallAvg > 0.05 { overallLabel = "Slightly Positive" }
        else if overallAvg > -0.05 { overallLabel = "Neutral" }
        else if overallAvg > -0.3 { overallLabel = "Slightly Negative" }
        else { overallLabel = "Negative" }

        let recommendation = generateRecommendation(
            weeklyAvg: weeklyAvg, posRatio: posRatio,
            negExposure: negExposure, diversity: comp.diversity
        )

        return SentimentDietReport(
            totalSamples: samples.count,
            overallAverage: overallAvg,
            overallLabel: overallLabel,
            weeklyAverage: weeklyAvg,
            trend: trend,
            positivityRatio: posRatio,
            negativityExposure: negExposure,
            emotionalDiversity: comp.diversity,
            topPositiveFeeds: Array(topPos),
            topNegativeFeeds: Array(topNeg),
            recommendation: recommendation
        )
    }

    // MARK: - Statistics

    /// Total number of tracked articles.
    var totalSamples: Int { return samples.count }

    /// Unique feeds with sentiment data.
    var trackedFeeds: [String] {
        return Array(Set(samples.map { $0.feedName })).sorted()
    }

    /// Average sentiment score across all samples.
    var overallAverageScore: Double {
        return samples.isEmpty ? 0 : averageScore(samples)
    }

    /// Weekly positivity ratio (fraction of positive articles this week).
    func weeklyPositivityRatio(asOf date: Date = Date()) -> Double {
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: date) else { return 0 }
        let weeklySamples = samples.filter { $0.recordedAt >= weekAgo }
        guard !weeklySamples.isEmpty else { return 0 }
        return Double(weeklySamples.filter { $0.score > 0 }.count) / Double(weeklySamples.count)
    }

    // MARK: - Export

    /// Export all samples as JSON.
    func exportJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(samples) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Import samples from JSON (appends, does not replace).
    func importJSON(_ json: String) -> Int {
        guard let data = json.data(using: .utf8),
              let imported = try? JSONDecoder().decode([SentimentSample].self, from: data) else {
            return 0
        }
        let existingIds = Set(samples.map { $0.id })
        let newSamples = imported.filter { !existingIds.contains($0.id) }
        samples.append(contentsOf: newSamples)
        samples.sort { $0.recordedAt > $1.recordedAt }
        pruneIfNeeded()
        save()
        return newSamples.count
    }

    // MARK: - Private Helpers

    private func aggregate(_ group: [SentimentSample], label: String, start: Date) -> SentimentAggregate {
        let scores = group.map { $0.score }
        let sorted = scores.sorted()
        let avg = scores.isEmpty ? 0.0 : scores.reduce(0, +) / Double(scores.count)
        let median: Double
        if sorted.count % 2 == 0 {
            median = (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2.0
        } else {
            median = sorted[sorted.count / 2]
        }

        let emotionCounts = Dictionary(grouping: group, by: { $0.dominantEmotion })
        let dominant = emotionCounts.max(by: { $0.value.count < $1.value.count })?.key ?? "None"

        return SentimentAggregate(
            periodLabel: label,
            periodStart: start,
            sampleCount: group.count,
            averageScore: avg,
            medianScore: median,
            minScore: sorted.first ?? 0,
            maxScore: sorted.last ?? 0,
            positivityRatio: group.isEmpty ? 0.0 : Double(group.filter { $0.score > 0 }.count) / Double(group.count),
            dominantEmotion: dominant,
            articleCount: group.count
        )
    }

    private func buildFeedProfile(feedName: String, feedSamples: [SentimentSample]) -> FeedSentimentProfile {
        let scores = feedSamples.map { $0.score }
        let sorted = scores.sorted()
        let avg = scores.isEmpty ? 0.0 : scores.reduce(0, +) / Double(scores.count)
        let median: Double
        if sorted.count % 2 == 0 {
            median = (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2.0
        } else {
            median = sorted[sorted.count / 2]
        }

        let emotionCounts = Dictionary(grouping: feedSamples, by: { $0.dominantEmotion })
        let dominant = emotionCounts.max(by: { $0.value.count < $1.value.count })?.key ?? "None"

        let posRatio = feedSamples.isEmpty ? 0.0 : Double(feedSamples.filter { $0.score > 0 }.count) / Double(feedSamples.count)

        let recent = Array(feedSamples.prefix(5))
        let recentAvg = recent.isEmpty ? nil : averageScore(recent)

        let trend = detectTrend(feedSamples)

        return FeedSentimentProfile(
            feedName: feedName,
            sampleCount: feedSamples.count,
            averageScore: avg,
            medianScore: median,
            dominantEmotion: dominant,
            positivityRatio: posRatio,
            trend: trend,
            recentScore: recentAvg
        )
    }

    private func buildComposition(_ group: [SentimentSample]) -> EmotionalComposition {
        guard !group.isEmpty else {
            return EmotionalComposition(sampleCount: 0, emotionShares: [:], dominant: "None", diversity: 0)
        }

        let emotionCounts = Dictionary(grouping: group, by: { $0.dominantEmotion })
            .mapValues { Double($0.count) / Double(group.count) }

        let dominant = emotionCounts.max(by: { $0.value < $1.value })?.key ?? "None"

        // Shannon diversity index normalised to 0-1
        let n = Double(emotionCounts.count)
        let entropy = n <= 1 ? 0 :
            -emotionCounts.values.reduce(0.0) { sum, p in
                p > 0 ? sum + p * log(p) : sum
            } / log(n)

        return EmotionalComposition(
            sampleCount: group.count,
            emotionShares: emotionCounts,
            dominant: dominant,
            diversity: min(1, max(0, entropy))
        )
    }

    private func detectTrend(_ sorted: [SentimentSample]) -> SentimentTrend {
        guard sorted.count >= 5 else { return .insufficientData }

        // Split into first half and second half (chronological order)
        let chronological = sorted.sorted { $0.recordedAt < $1.recordedAt }
        let mid = chronological.count / 2
        let firstHalf = Array(chronological[..<mid])
        let secondHalf = Array(chronological[mid...])

        let firstAvg = averageScore(firstHalf)
        let secondAvg = averageScore(secondHalf)
        let delta = secondAvg - firstAvg

        if delta > 0.1 { return .improving }
        if delta < -0.1 { return .worsening }
        return .steady
    }

    private func averageScore(_ group: [SentimentSample]) -> Double {
        guard !group.isEmpty else { return 0 }
        return group.map { $0.score }.reduce(0, +) / Double(group.count)
    }

    private func checkNegativityAlert() {
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date())
        guard let cutoff = weekAgo else { return }
        let recent = samples.filter { $0.recordedAt >= cutoff }
        guard recent.count >= 5 else { return }
        let avg = averageScore(recent)
        if avg < Self.negativityAlertThreshold {
            NotificationCenter.default.post(name: .sentimentNegativityAlert, object: nil,
                                            userInfo: ["weeklyAverage": avg])
        }
    }

    private func generateRecommendation(weeklyAvg: Double, posRatio: Double,
                                         negExposure: Double, diversity: Double) -> String {
        if weeklyAvg < -0.3 {
            return "Your reading diet has been quite negative this week. Consider adding some uplifting or solution-focused feeds to balance your intake."
        }
        if negExposure > 0.5 {
            return "Over half your articles are strongly negative. Try mixing in constructive journalism or positive-news sources."
        }
        if diversity < 0.3 {
            return "Your reading triggers a narrow range of emotions. Diversifying your feed sources could give you a richer media diet."
        }
        if posRatio > 0.8 {
            return "Your reading is overwhelmingly positive — which is great, but make sure you're not filtering out important critical perspectives."
        }
        if weeklyAvg > 0 && diversity > 0.5 {
            return "Well-balanced reading diet! You have a healthy mix of perspectives and emotional variety."
        }
        return "Your reading sentiment is fairly neutral. Your diet looks balanced."
    }

    private func startOfWeekContaining(_ date: Date) -> Date {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        guard let weekInterval = cal.dateInterval(of: .weekOfYear, for: date) else { return date }
        return weekInterval.start
    }

    private func pruneIfNeeded() {
        if samples.count > Self.maxSamples {
            samples = Array(samples.prefix(Self.maxSamples))
        }
    }

    private func save() {
        store.save(samples)
    }

    private func load() {
        samples = store.load() ?? []
    }
}
