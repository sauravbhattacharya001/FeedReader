//
//  ReadingSpeedTracker.swift
//  FeedReader
//
//  Tracks the user's actual reading speed (words per minute) by
//  correlating article word counts with time spent reading. Learns
//  a personalized WPM profile that improves estimated reading times
//  over the fixed 238 wpm assumption.
//
//  Features:
//  - Record reading speed samples (word count + time spent)
//  - Calculate personalized average WPM with outlier filtering
//  - Track speed trends over time (improving, declining, steady)
//  - Per-feed and per-category speed breakdowns
//  - Difficulty-adjusted estimates (short vs long articles)
//  - Speed percentile vs population averages
//  - Personalized time estimates for unread articles
//  - Export/import speed profile as JSON
//
//  Persistence: UserDefaults via Codable.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when a new speed sample is recorded.
    static let readingSpeedDidUpdate = Notification.Name("ReadingSpeedDidUpdateNotification")
}

// MARK: - Models

/// A single reading speed measurement.
struct SpeedSample: Codable, Equatable {
    /// Unique identifier.
    let id: String
    /// Article title (for reference).
    let articleTitle: String
    /// Feed name the article came from.
    let feedName: String
    /// Word count of the article.
    let wordCount: Int
    /// Active reading time in seconds (excluding pauses).
    let readingTimeSeconds: TimeInterval
    /// Computed words per minute for this sample.
    var wordsPerMinute: Double {
        guard readingTimeSeconds > 0 else { return 0 }
        return Double(wordCount) / (readingTimeSeconds / 60.0)
    }
    /// When this sample was recorded.
    let recordedAt: Date
    /// Optional category tag (e.g., "tech", "news", "longform").
    let category: String?

    init(articleTitle: String, feedName: String, wordCount: Int,
         readingTimeSeconds: TimeInterval, recordedAt: Date = Date(),
         category: String? = nil) {
        self.id = UUID().uuidString
        self.articleTitle = articleTitle
        self.feedName = feedName
        self.wordCount = wordCount
        self.readingTimeSeconds = readingTimeSeconds
        self.recordedAt = recordedAt
        self.category = category
    }
}

/// Speed trend direction over a time period.
enum SpeedTrend: String, Codable {
    case improving
    case declining
    case steady
    case insufficientData
}

/// Breakdown of reading speed for a specific context (feed, category, etc.).
struct SpeedBreakdown: Equatable {
    let label: String
    let sampleCount: Int
    let averageWPM: Double
    let minWPM: Double
    let maxWPM: Double
}

/// Summary of the user's reading speed profile.
struct SpeedProfile: Equatable {
    /// Overall average WPM (outlier-filtered).
    let averageWPM: Double
    /// Median WPM.
    let medianWPM: Double
    /// Standard deviation of WPM.
    let standardDeviation: Double
    /// Total samples recorded.
    let totalSamples: Int
    /// Speed trend over the last 30 days.
    let recentTrend: SpeedTrend
    /// Percentile rank vs population averages (0-100).
    let populationPercentile: Int
    /// Speed label (Slow, Below Average, Average, Above Average, Fast, Speed Reader).
    let speedLabel: String
    /// Per-feed breakdown.
    let feedBreakdown: [SpeedBreakdown]
    /// Per-category breakdown.
    let categoryBreakdown: [SpeedBreakdown]
    /// Average WPM for short articles (<500 words).
    let shortArticleWPM: Double?
    /// Average WPM for medium articles (500-1500 words).
    let mediumArticleWPM: Double?
    /// Average WPM for long articles (>1500 words).
    let longArticleWPM: Double?
    /// Date of first sample.
    let trackingSince: Date?
}

// MARK: - ReadingSpeedTracker

/// Tracks and analyzes the user's personal reading speed over time.
///
/// Samples are filtered to remove outliers (e.g., leaving a tab open
/// without reading, or skimming headings only). The tracker maintains
/// a rolling profile that improves time estimates as more data is
/// collected.
class ReadingSpeedTracker {

    // MARK: - Constants

    /// Minimum WPM to accept as a valid reading sample.
    /// Below this, the user was likely idle or distracted.
    static let minimumValidWPM: Double = 50

    /// Maximum WPM to accept as a valid reading sample.
    /// Above this, the user was likely skimming, not reading.
    static let maximumValidWPM: Double = 1200

    /// Minimum article word count for a valid sample.
    /// Very short articles produce unreliable speed measurements.
    static let minimumWordCount: Int = 50

    /// Minimum reading time (seconds) for a valid sample.
    static let minimumReadingTime: TimeInterval = 10

    /// Default WPM when no personal data is available.
    /// Average adult reading speed (Brysbaert, 2019).
    static let defaultWPM: Double = 238

    /// Maximum samples to keep (prevents unbounded growth).
    static let maxSamples: Int = 5000

    /// Population average WPM benchmarks for percentile calculation.
    /// Based on published literacy research.
    private static let populationBenchmarks: [(percentile: Int, wpm: Double)] = [
        (5, 100), (10, 130), (20, 160), (30, 185),
        (40, 210), (50, 238), (60, 260), (70, 290),
        (80, 330), (90, 400), (95, 500), (99, 800)
    ]

    // MARK: - Properties

    /// All recorded speed samples, newest first.
    private(set) var samples: [SpeedSample] = []

    /// UserDefaults persistence key.
    private static let userDefaultsKey = "ReadingSpeedTracker.samples"

    /// Persistence store.
    private let store = UserDefaultsCodableStore<[SpeedSample]>(
        key: ReadingSpeedTracker.userDefaultsKey
    )

    // MARK: - Init

    init() {
        loadFromDefaults()
    }

    // MARK: - Recording

    /// Record a reading speed sample.
    ///
    /// Automatically filters out invalid samples (too fast, too slow,
    /// article too short, reading time too brief).
    ///
    /// - Parameters:
    ///   - articleTitle: Title of the article read.
    ///   - feedName: Feed the article came from.
    ///   - wordCount: Number of words in the article.
    ///   - readingTimeSeconds: Active reading time in seconds.
    ///   - category: Optional category for breakdown tracking.
    /// - Returns: The sample if accepted, nil if filtered out.
    @discardableResult
    func recordSample(articleTitle: String, feedName: String,
                      wordCount: Int, readingTimeSeconds: TimeInterval,
                      category: String? = nil) -> SpeedSample? {
        // Validate inputs
        guard wordCount >= ReadingSpeedTracker.minimumWordCount else { return nil }
        guard readingTimeSeconds >= ReadingSpeedTracker.minimumReadingTime else { return nil }

        let sample = SpeedSample(
            articleTitle: articleTitle,
            feedName: feedName,
            wordCount: wordCount,
            readingTimeSeconds: readingTimeSeconds,
            category: category
        )

        // Filter outliers
        guard sample.wordsPerMinute >= ReadingSpeedTracker.minimumValidWPM else { return nil }
        guard sample.wordsPerMinute <= ReadingSpeedTracker.maximumValidWPM else { return nil }

        samples.insert(sample, at: 0)

        // Trim oldest samples if over limit
        if samples.count > ReadingSpeedTracker.maxSamples {
            samples = Array(samples.prefix(ReadingSpeedTracker.maxSamples))
        }

        saveToDefaults()

        NotificationCenter.default.post(
            name: .readingSpeedDidUpdate,
            object: self,
            userInfo: ["sample": sample]
        )

        return sample
    }

    // MARK: - Speed Calculations

    /// Current personalized WPM, or the default if insufficient data.
    var currentWPM: Double {
        let filtered = validSamples()
        guard !filtered.isEmpty else { return ReadingSpeedTracker.defaultWPM }
        return averageWPM(of: filtered)
    }

    /// Median WPM from recorded samples.
    var medianWPM: Double? {
        let filtered = validSamples()
        guard !filtered.isEmpty else { return nil }
        let sorted = filtered.map(\.wordsPerMinute).sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        }
        return sorted[mid]
    }

    /// Standard deviation of reading speeds.
    var speedStandardDeviation: Double? {
        let filtered = validSamples()
        guard filtered.count >= 2 else { return nil }
        let mean = averageWPM(of: filtered)
        let variance = filtered.map { pow($0.wordsPerMinute - mean, 2) }
            .reduce(0, +) / Double(filtered.count)
        return sqrt(variance)
    }

    /// Estimate reading time for an article with the given word count,
    /// using the user's personalized speed.
    ///
    /// Falls back to the default 238 WPM if no personal data exists.
    /// Uses length-adjusted speed when enough data is available.
    func estimatedReadingTime(wordCount: Int) -> TimeInterval {
        let wpm = lengthAdjustedWPM(wordCount: wordCount) ?? currentWPM
        guard wpm > 0 else { return 0 }
        return Double(wordCount) / wpm * 60.0
    }

    /// Formatted estimated reading time (e.g., "3 min", "1 hr 12 min").
    func formattedEstimate(wordCount: Int) -> String {
        let seconds = estimatedReadingTime(wordCount: wordCount)
        let minutes = Int(ceil(seconds / 60.0))
        if minutes < 1 { return "< 1 min" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainingMins = minutes % 60
        if remainingMins == 0 { return "\(hours) hr" }
        return "\(hours) hr \(remainingMins) min"
    }

    // MARK: - Length-Adjusted Speed

    /// WPM adjusted for article length bucket.
    ///
    /// People typically read shorter pieces faster (lighter content,
    /// less cognitive load) and longer pieces slower (deeper material,
    /// fatigue). This method returns bucket-specific averages when
    /// enough samples exist.
    ///
    /// Uses IQR-filtered samples to exclude outliers, consistent with
    /// `currentWPM` and `buildProfile()`. Previously used raw `samples`
    /// which could skew estimates when idle/skimming outliers clustered
    /// in a particular length bucket.
    func lengthAdjustedWPM(wordCount: Int) -> Double? {
        let bucket = lengthBucket(wordCount: wordCount)
        let filtered = validSamples()
        let bucketSamples = filtered.filter { lengthBucket(wordCount: $0.wordCount) == bucket }
        guard bucketSamples.count >= 3 else { return nil }
        return averageWPM(of: bucketSamples)
    }

    private func lengthBucket(wordCount: Int) -> String {
        if wordCount < 500 { return "short" }
        if wordCount <= 1500 { return "medium" }
        return "long"
    }

    // MARK: - Trend Analysis

    /// Compute reading speed trend over a time window.
    ///
    /// Compares the average WPM from the first half of recent samples
    /// to the second half. Requires at least 10 samples in the window.
    func speedTrend(days: Int = 30) -> SpeedTrend {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let recent = validSamples().filter { $0.recordedAt >= cutoff }
        guard recent.count >= 10 else { return .insufficientData }

        let sorted = recent.sorted { $0.recordedAt < $1.recordedAt }
        let mid = sorted.count / 2
        let firstHalf = Array(sorted.prefix(mid))
        let secondHalf = Array(sorted.suffix(sorted.count - mid))

        let firstAvg = averageWPM(of: firstHalf)
        let secondAvg = averageWPM(of: secondHalf)

        guard firstAvg > 0 else { return .insufficientData }

        let changePercent = (secondAvg - firstAvg) / firstAvg * 100

        if changePercent > 5 { return .improving }
        if changePercent < -5 { return .declining }
        return .steady
    }

    // MARK: - Breakdowns

    /// Speed breakdown by feed.
    func feedBreakdown() -> [SpeedBreakdown] {
        return breakdown(groupedBy: \.feedName)
    }

    /// Speed breakdown by category.
    func categoryBreakdown() -> [SpeedBreakdown] {
        let categorized = validSamples().filter { $0.category != nil }
        let grouped = Dictionary(grouping: categorized) { $0.category! }
        return grouped.map { key, values in
            let wpms = values.map(\.wordsPerMinute)
            return SpeedBreakdown(
                label: key,
                sampleCount: values.count,
                averageWPM: wpms.isEmpty ? 0.0 : wpms.reduce(0, +) / Double(wpms.count),
                minWPM: wpms.min() ?? 0,
                maxWPM: wpms.max() ?? 0
            )
        }.sorted { $0.averageWPM > $1.averageWPM }
    }

    private func breakdown(groupedBy keyPath: KeyPath<SpeedSample, String>) -> [SpeedBreakdown] {
        let grouped = Dictionary(grouping: validSamples()) { $0[keyPath: keyPath] }
        return grouped.map { key, values in
            let wpms = values.map(\.wordsPerMinute)
            return SpeedBreakdown(
                label: key,
                sampleCount: values.count,
                averageWPM: wpms.isEmpty ? 0.0 : wpms.reduce(0, +) / Double(wpms.count),
                minWPM: wpms.min() ?? 0,
                maxWPM: wpms.max() ?? 0
            )
        }.sorted { $0.averageWPM > $1.averageWPM }
    }

    // MARK: - Population Comparison

    /// User's percentile rank in population reading speed distribution.
    func populationPercentile() -> Int {
        let wpm = currentWPM
        let benchmarks = ReadingSpeedTracker.populationBenchmarks

        // Find where the user falls
        for i in stride(from: benchmarks.count - 1, through: 0, by: -1) {
            if wpm >= benchmarks[i].wpm {
                return benchmarks[i].percentile
            }
        }
        return 1 // Below 5th percentile
    }

    /// Human-readable speed category label.
    func speedLabel() -> String {
        let wpm = currentWPM
        if wpm < 150 { return "Slow" }
        if wpm < 200 { return "Below Average" }
        if wpm < 280 { return "Average" }
        if wpm < 350 { return "Above Average" }
        if wpm < 500 { return "Fast" }
        return "Speed Reader"
    }

    // MARK: - Full Profile

    /// Build a complete speed profile summary.
    func buildProfile() -> SpeedProfile {
        let filtered = validSamples()
        let avg = filtered.isEmpty ? ReadingSpeedTracker.defaultWPM : averageWPM(of: filtered)
        let med = medianWPM ?? ReadingSpeedTracker.defaultWPM
        let stdDev = speedStandardDeviation ?? 0

        let shortSamples = filtered.filter { $0.wordCount < 500 }
        let mediumSamples = filtered.filter { $0.wordCount >= 500 && $0.wordCount <= 1500 }
        let longSamples = filtered.filter { $0.wordCount > 1500 }

        return SpeedProfile(
            averageWPM: avg,
            medianWPM: med,
            standardDeviation: stdDev,
            totalSamples: filtered.count,
            recentTrend: speedTrend(),
            populationPercentile: populationPercentile(),
            speedLabel: speedLabel(),
            feedBreakdown: feedBreakdown(),
            categoryBreakdown: categoryBreakdown(),
            shortArticleWPM: shortSamples.count >= 3 ? averageWPM(of: shortSamples) : nil,
            mediumArticleWPM: mediumSamples.count >= 3 ? averageWPM(of: mediumSamples) : nil,
            longArticleWPM: longSamples.count >= 3 ? averageWPM(of: longSamples) : nil,
            trackingSince: samples.last?.recordedAt
        )
    }

    // MARK: - Export / Import

    /// Export speed data as JSON.
    func exportJSON() -> String? {
        let encoder = JSONCoding.iso8601PrettyEncoder
        guard let data = try? encoder.encode(samples) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Import speed data from JSON (merges with existing, deduplicates by ID).
    func importJSON(_ jsonString: String) -> Int {
        // Size guard: reject input larger than 10 MB to prevent OOM
        // on adversarial or accidentally huge payloads (CWE-400).
        guard jsonString.utf8.count <= 10_485_760 else { return 0 }

        let decoder = JSONCoding.iso8601Decoder
        guard let data = jsonString.data(using: .utf8),
              let imported = try? decoder.decode([SpeedSample].self, from: data)
        else { return 0 }

        let existingIDs = Set(samples.map(\.id))
        let newSamples = imported.filter { !existingIDs.contains($0.id) }
        samples.append(contentsOf: newSamples)
        samples.sort { $0.recordedAt > $1.recordedAt }

        if samples.count > ReadingSpeedTracker.maxSamples {
            samples = Array(samples.prefix(ReadingSpeedTracker.maxSamples))
        }

        saveToDefaults()
        return newSamples.count
    }

    // MARK: - Management

    /// Remove all speed samples.
    func clearAll() {
        samples.removeAll()
        saveToDefaults()
    }

    /// Remove samples older than a given date.
    func removeSamplesBefore(_ date: Date) -> Int {
        let before = samples.count
        samples.removeAll { $0.recordedAt < date }
        saveToDefaults()
        return before - samples.count
    }

    // MARK: - Private Helpers

    /// Filter out statistical outliers using IQR method.
    private func validSamples() -> [SpeedSample] {
        guard samples.count >= 4 else { return samples }

        let sorted = samples.map(\.wordsPerMinute).sorted()
        let q1Index = sorted.count / 4
        let q3Index = (sorted.count * 3) / 4
        let q1 = sorted[q1Index]
        let q3 = sorted[q3Index]
        let iqr = q3 - q1
        let lowerBound = q1 - 1.5 * iqr
        let upperBound = q3 + 1.5 * iqr

        return samples.filter {
            $0.wordsPerMinute >= lowerBound && $0.wordsPerMinute <= upperBound
        }
    }

    private func averageWPM(of samples: [SpeedSample]) -> Double {
        guard !samples.isEmpty else { return 0 }
        return samples.map(\.wordsPerMinute).reduce(0, +) / Double(samples.count)
    }

    // MARK: - Persistence

    private func saveToDefaults() {
        store.save(samples)
    }

    private func loadFromDefaults() {
        if let loaded = store.load() {
            samples = loaded
        }
    }
}
