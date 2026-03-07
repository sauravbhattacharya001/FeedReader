//
//  ArticleTrendDetector.swift
//  FeedReader
//
//  Detects trending topics across feeds by tracking keyword frequency
//  over time windows. Surfaces emerging stories, hot topics, and
//  declining trends so users can stay on top of what matters.
//
//  Fully offline — no network, no dependencies beyond Foundation.
//

import Foundation

// MARK: - Notification

extension Notification.Name {
    static let trendsDidUpdate = Notification.Name("TrendsDidUpdateNotification")
}

// MARK: - TrendDirection

/// Whether a topic is gaining or losing momentum.
enum TrendDirection: String, Codable {
    case rising      // frequency increasing
    case stable      // roughly flat
    case declining   // frequency decreasing
    case spike       // sudden burst (new topic)
    case fading      // was hot, now cooling
}

// MARK: - TopicTrend

/// A detected trending topic with frequency data.
struct TopicTrend: Equatable {
    /// The keyword or phrase representing this topic.
    let topic: String
    /// Number of articles mentioning this topic in the current window.
    let currentCount: Int
    /// Number of articles mentioning this topic in the previous window.
    let previousCount: Int
    /// Percentage change from previous to current window.
    let changePercent: Double
    /// Direction of the trend.
    let direction: TrendDirection
    /// Momentum score (0.0-1.0) combining frequency and acceleration.
    let momentum: Double
    /// Sample article titles containing this topic.
    let sampleTitles: [String]
    /// Feeds where this topic appears.
    let feedSources: [String]
    /// First seen timestamp.
    let firstSeen: Date
    /// Last seen timestamp.
    let lastSeen: Date
}

// MARK: - TrendSnapshot

/// A point-in-time record of keyword frequency for persistence.
struct TrendSnapshot: Codable, Equatable {
    let timestamp: Date
    let keywordCounts: [String: Int]
    let totalArticles: Int
}

// MARK: - TrendConfig

/// Configuration for the trend detector.
struct TrendConfig {
    /// How far back the "current" window extends (in hours).
    var currentWindowHours: Double = 24
    /// How far back the "previous" window extends (in hours).
    var previousWindowHours: Double = 48
    /// Minimum article count to qualify as a trend.
    var minMentions: Int = 2
    /// Maximum number of trends to return.
    var maxTrends: Int = 20
    /// Words to exclude from trend detection.
    /// Defaults to `TextAnalyzer.stopWords` for consistency across modules.
    var stopWords: Set<String> = TextAnalyzer.stopWords
}

// MARK: - ArticleTrendDetector

/// Detects trending topics by analyzing keyword frequency across time windows.
/// Maintains a history of snapshots for comparing current vs. past frequency.
class ArticleTrendDetector {

    // MARK: - Properties

    private(set) var snapshots: [TrendSnapshot] = []
    private var config: TrendConfig

    /// Maximum snapshots to retain (rolling window).
    private let maxSnapshots = 200

    // MARK: - Persistence

    private static let archiveURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("trendSnapshots.json")
    }()

    // MARK: - Init

    init(config: TrendConfig = TrendConfig()) {
        self.config = config
        loadSnapshots()
    }

    /// Init with injected snapshots (for testing).
    init(config: TrendConfig = TrendConfig(), snapshots: [TrendSnapshot]) {
        self.config = config
        self.snapshots = snapshots
    }

    // MARK: - Ingest

    /// Ingest a batch of articles and create a new snapshot.
    /// Call this after a feed refresh to update trend data.
    /// - Parameters:
    ///   - articles: The articles to analyze.
    ///   - timestamp: When these articles were ingested (default: now).
    func ingest(articles: [(title: String, body: String, feedName: String)], timestamp: Date = Date()) {
        var keywordCounts: [String: Int] = [:]

        for article in articles {
            let text = "\(article.title) \(article.body)"
            let keywords = extractKeywords(from: text)
            // Count each keyword once per article (presence, not frequency)
            let uniqueKeywords = Set(keywords)
            for keyword in uniqueKeywords {
                keywordCounts[keyword, default: 0] += 1
            }
        }

        let snapshot = TrendSnapshot(
            timestamp: timestamp,
            keywordCounts: keywordCounts,
            totalArticles: articles.count
        )

        snapshots.append(snapshot)

        // Trim old snapshots
        if snapshots.count > maxSnapshots {
            snapshots = Array(snapshots.suffix(maxSnapshots))
        }

        saveSnapshots()
        NotificationCenter.default.post(name: .trendsDidUpdate, object: self)
    }

    // MARK: - Detect Trends

    /// Analyze snapshots to find trending topics.
    /// - Parameter referenceDate: The "now" for window calculations (default: Date()).
    /// - Returns: Array of TopicTrend sorted by momentum descending.
    func detectTrends(referenceDate: Date = Date()) -> [TopicTrend] {
        let currentCutoff = referenceDate.addingTimeInterval(-config.currentWindowHours * 3600)
        let previousCutoff = referenceDate.addingTimeInterval(-(config.currentWindowHours + config.previousWindowHours) * 3600)

        // Aggregate keyword counts per window
        let currentCounts = aggregateCounts(from: currentCutoff, to: referenceDate)
        let previousCounts = aggregateCounts(from: previousCutoff, to: currentCutoff)

        var trends: [TopicTrend] = []

        for (keyword, currentCount) in currentCounts {
            guard currentCount >= config.minMentions else { continue }

            let previousCount = previousCounts[keyword] ?? 0
            let changePercent: Double
            if previousCount == 0 {
                changePercent = currentCount > 0 ? 100.0 : 0.0
            } else {
                changePercent = Double(currentCount - previousCount) / Double(previousCount) * 100.0
            }

            let direction = classifyDirection(current: currentCount, previous: previousCount, changePercent: changePercent)
            let momentum = calculateMomentum(current: currentCount, previous: previousCount, direction: direction)

            // Collect sample titles and sources
            let (titles, sources, firstSeen, lastSeen) = collectMetadata(for: keyword, from: previousCutoff, to: referenceDate)

            let trend = TopicTrend(
                topic: keyword,
                currentCount: currentCount,
                previousCount: previousCount,
                changePercent: changePercent,
                direction: direction,
                momentum: momentum,
                sampleTitles: Array(titles.prefix(3)),
                feedSources: Array(Set(sources)).sorted(),
                firstSeen: firstSeen ?? referenceDate,
                lastSeen: lastSeen ?? referenceDate
            )
            trends.append(trend)
        }

        // Also check for declining topics (were popular, now gone)
        for (keyword, prevCount) in previousCounts {
            guard prevCount >= config.minMentions else { continue }
            guard currentCounts[keyword] == nil else { continue }

            let (titles, sources, firstSeen, lastSeen) = collectMetadata(for: keyword, from: previousCutoff, to: referenceDate)

            let trend = TopicTrend(
                topic: keyword,
                currentCount: 0,
                previousCount: prevCount,
                changePercent: -100.0,
                direction: .fading,
                momentum: 0.1, // low but non-zero so they still appear
                sampleTitles: Array(titles.prefix(3)),
                feedSources: Array(Set(sources)).sorted(),
                firstSeen: firstSeen ?? referenceDate,
                lastSeen: lastSeen ?? referenceDate
            )
            trends.append(trend)
        }

        // Sort by momentum descending, then by count
        trends.sort { ($0.momentum, Double($0.currentCount)) > ($1.momentum, Double($1.currentCount)) }

        return Array(trends.prefix(config.maxTrends))
    }

    // MARK: - Top Keywords

    /// Get the most frequent keywords across all snapshots in a time range.
    func topKeywords(hours: Double = 24, limit: Int = 10, referenceDate: Date = Date()) -> [(keyword: String, count: Int)] {
        let cutoff = referenceDate.addingTimeInterval(-hours * 3600)
        let counts = aggregateCounts(from: cutoff, to: referenceDate)
        return counts.sorted { $0.value > $1.value }.prefix(limit).map { ($0.key, $0.value) }
    }

    // MARK: - Topic History

    /// Get the frequency history of a specific topic across all snapshots.
    func topicHistory(for topic: String) -> [(date: Date, count: Int)] {
        let normalized = topic.lowercased()
        return snapshots.compactMap { snapshot in
            if let count = snapshot.keywordCounts[normalized], count > 0 {
                return (snapshot.timestamp, count)
            }
            return nil
        }
    }

    // MARK: - Summary

    /// Generate a human-readable trend summary.
    func summary(referenceDate: Date = Date()) -> String {
        let trends = detectTrends(referenceDate: referenceDate)
        guard !trends.isEmpty else { return "No trending topics detected." }

        var lines: [String] = ["📈 Trending Topics"]
        lines.append(String(repeating: "─", count: 40))

        for (i, trend) in trends.prefix(10).enumerated() {
            let icon: String
            switch trend.direction {
            case .rising: icon = "🔥"
            case .spike: icon = "⚡"
            case .stable: icon = "➡️"
            case .declining: icon = "📉"
            case .fading: icon = "💤"
            }

            let change = trend.changePercent >= 0 ? "+\(Int(trend.changePercent))%" : "\(Int(trend.changePercent))%"
            lines.append("\(i + 1). \(icon) \(trend.topic) — \(trend.currentCount) mentions (\(change))")
            if !trend.feedSources.isEmpty {
                lines.append("   Sources: \(trend.feedSources.joined(separator: ", "))")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Reset

    /// Clear all snapshots.
    func reset() {
        snapshots = []
        saveSnapshots()
    }

    // MARK: - Private Helpers

    /// Extract keywords from text using the shared tokenizer.
    /// Uses `config.stopWords` if customized, otherwise delegates
    /// fully to `TextAnalyzer.shared.tokenize()`.
    private func extractKeywords(from text: String) -> [String] {
        // If using the default TextAnalyzer stop words, delegate directly.
        // Otherwise, apply the custom stop word set for backward compatibility.
        if config.stopWords == TextAnalyzer.stopWords {
            return TextAnalyzer.shared.tokenize(text)
        }
        let lowered = text.lowercased()
        return lowered.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !config.stopWords.contains($0) }
    }

    private func aggregateCounts(from start: Date, to end: Date) -> [String: Int] {
        var aggregate: [String: Int] = [:]
        for snapshot in snapshots where snapshot.timestamp >= start && snapshot.timestamp <= end {
            for (keyword, count) in snapshot.keywordCounts {
                aggregate[keyword, default: 0] += count
            }
        }
        return aggregate
    }

    private func classifyDirection(current: Int, previous: Int, changePercent: Double) -> TrendDirection {
        if previous == 0 && current > 0 { return .spike }
        if current == 0 && previous > 0 { return .fading }
        if changePercent > 30 { return .rising }
        if changePercent < -30 { return .declining }
        return .stable
    }

    private func calculateMomentum(current: Int, previous: Int, direction: TrendDirection) -> Double {
        let frequency = min(Double(current) / 10.0, 1.0)
        let acceleration: Double
        if previous == 0 {
            acceleration = current > 0 ? 1.0 : 0.0
        } else {
            acceleration = min(max(Double(current - previous) / Double(previous), -1.0), 1.0)
        }

        // Weight: 60% frequency, 40% acceleration
        let raw = 0.6 * frequency + 0.4 * ((acceleration + 1.0) / 2.0)
        return min(max(raw, 0.0), 1.0)
    }

    /// Collect sample titles and feed sources for a keyword from snapshot metadata.
    /// Since snapshots only store counts, we return empty arrays for titles.
    /// In production, you'd cross-reference with the article store.
    private func collectMetadata(for keyword: String, from start: Date, to end: Date) -> (titles: [String], sources: [String], firstSeen: Date?, lastSeen: Date?) {
        var firstSeen: Date?
        var lastSeen: Date?

        for snapshot in snapshots where snapshot.timestamp >= start && snapshot.timestamp <= end {
            if let count = snapshot.keywordCounts[keyword], count > 0 {
                if firstSeen == nil { firstSeen = snapshot.timestamp }
                lastSeen = snapshot.timestamp
            }
        }

        return ([], [], firstSeen, lastSeen)
    }

    // MARK: - Persistence

    private func loadSnapshots() {
        guard FileManager.default.fileExists(atPath: Self.archiveURL.path) else { return }
        do {
            let data = try Data(contentsOf: Self.archiveURL)
            snapshots = try JSONDecoder().decode([TrendSnapshot].self, from: data)
        } catch {
            snapshots = []
        }
    }

    private func saveSnapshots() {
        do {
            let data = try JSONEncoder().encode(snapshots)
            try data.write(to: Self.archiveURL, options: .atomic)
        } catch {
            // Silent fail — not critical
        }
    }
}
