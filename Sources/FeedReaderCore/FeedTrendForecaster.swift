//
//  FeedTrendForecaster.swift
//  FeedReaderCore
//
//  Autonomous trending topic forecaster for RSS feeds. Detects emerging
//  trends before they peak by analyzing keyword momentum across time
//  windows, computing breakout probabilities, and generating proactive
//  alerts for topics that are about to go viral.
//

import Foundation

// MARK: - Trend Phase

/// Lifecycle phase of a trending topic.
public enum TrendPhase: String, CaseIterable, Sendable {
    case emerging = "emerging"
    case accelerating = "accelerating"
    case peaking = "peaking"
    case declining = "declining"

    /// Emoji representation for display.
    public var emoji: String {
        switch self {
        case .emerging: return "🌱"
        case .accelerating: return "🚀"
        case .peaking: return "🔥"
        case .declining: return "📉"
        }
    }
}

// MARK: - Trend Signal

/// Represents an emerging trend detected across RSS feeds.
public struct TrendSignal: Sendable {
    /// The trending keyword or topic.
    public let topic: String
    /// Momentum score from 0.0 (stagnant) to 1.0 (explosive growth).
    public let momentum: Double
    /// Total number of articles mentioning this topic.
    public let articleCount: Int
    /// When this topic first appeared in the analysis window.
    public let firstSeen: Date
    /// When this topic was most recently seen.
    public let lastSeen: Date
    /// Names of feeds where this topic appears.
    public let feedSources: [String]
    /// Current lifecycle phase of the trend.
    public let phase: TrendPhase
    /// Estimated probability (0.0–1.0) that this topic will break out.
    public let breakoutProbability: Double

    /// Human-readable summary with emoji and key metrics.
    public var summary: String {
        let spreadLabel = feedSources.count == 1 ? "1 feed" : "\(feedSources.count) feeds"
        let pct = Int(breakoutProbability * 100)
        return "\(phase.emoji) \(topic) — \(articleCount) articles across \(spreadLabel), " +
               "momentum \(String(format: "%.0f%%", momentum * 100)), " +
               "breakout \(pct)% [\(phase.rawValue)]"
    }
}

// MARK: - Trend Forecast

/// Complete forecast report containing all detected trend signals.
public struct TrendForecast: Sendable {
    /// When this forecast was generated.
    public let generatedAt: Date
    /// Number of days in the analysis window.
    public let windowDays: Int
    /// All detected trend signals, sorted by breakout probability descending.
    public let signals: [TrendSignal]
    /// Top 5 signals most likely to break out.
    public var topBreakouts: [TrendSignal] {
        Array(signals.sorted { $0.breakoutProbability > $1.breakoutProbability }.prefix(5))
    }
    /// Proactive insights and recommendations.
    public let proactiveInsights: [String]

    /// Formatted text report.
    public var textReport: String {
        var lines: [String] = []
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short

        lines.append("═══════════════════════════════════════════")
        lines.append("  📈 TREND FORECAST REPORT")
        lines.append("  Generated: \(fmt.string(from: generatedAt))")
        lines.append("  Window: \(windowDays) days | \(signals.count) trends detected")
        lines.append("═══════════════════════════════════════════")

        // Top breakouts
        let breakouts = topBreakouts
        if !breakouts.isEmpty {
            lines.append("")
            lines.append("🔥 TOP BREAKOUT CANDIDATES")
            lines.append("───────────────────────────────────────────")
            for (i, signal) in breakouts.enumerated() {
                lines.append("  \(i + 1). \(signal.summary)")
            }
        }

        // Early signals
        let early = signals.filter { $0.phase == .emerging || $0.phase == .accelerating }
        if !early.isEmpty {
            lines.append("")
            lines.append("🌱 EARLY SIGNALS")
            lines.append("───────────────────────────────────────────")
            for signal in early.prefix(10) {
                lines.append("  \(signal.summary)")
            }
        }

        // Declining
        let declining = signals.filter { $0.phase == .declining }
        if !declining.isEmpty {
            lines.append("")
            lines.append("📉 FADING TRENDS")
            lines.append("───────────────────────────────────────────")
            for signal in declining.prefix(5) {
                lines.append("  \(signal.summary)")
            }
        }

        // Proactive insights
        if !proactiveInsights.isEmpty {
            lines.append("")
            lines.append("💡 PROACTIVE INSIGHTS")
            lines.append("───────────────────────────────────────────")
            for insight in proactiveInsights {
                lines.append("  • \(insight)")
            }
        }

        lines.append("")
        lines.append("═══════════════════════════════════════════")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Forecast Diff

/// Comparison between two forecasts showing what changed.
public struct ForecastDiff: Sendable {
    /// Topics that appeared in the newer forecast but not the older one.
    public let newTrends: [TrendSignal]
    /// Topics that disappeared from the newer forecast.
    public let goneTrends: [String]
    /// Topics whose momentum increased between forecasts.
    public let acceleratedTrends: [TrendSignal]

    /// Human-readable summary of changes.
    public var textSummary: String {
        var lines: [String] = []
        lines.append("📊 Forecast Diff")
        if !newTrends.isEmpty {
            lines.append("  🆕 New: \(newTrends.map { $0.topic }.joined(separator: ", "))")
        }
        if !goneTrends.isEmpty {
            lines.append("  👋 Gone: \(goneTrends.joined(separator: ", "))")
        }
        if !acceleratedTrends.isEmpty {
            lines.append("  ⚡ Accelerated: \(acceleratedTrends.map { $0.topic }.joined(separator: ", "))")
        }
        if newTrends.isEmpty && goneTrends.isEmpty && acceleratedTrends.isEmpty {
            lines.append("  No significant changes.")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Feed Trend Forecaster

/// Autonomous engine that detects emerging trends across RSS feeds.
///
/// Analyzes article titles over configurable time windows, computes
/// keyword momentum via linear regression on daily mention counts,
/// and predicts which topics are about to break out.
///
/// ## Usage
/// ```swift
/// let forecaster = FeedTrendForecaster()
/// let articles = [
///     (title: "AI breakthrough in healthcare", feedName: "TechCrunch", publishedDate: Date()),
///     (title: "New AI model beats benchmarks", feedName: "ArsTechnica", publishedDate: Date()),
///     // ...
/// ]
/// let forecast = forecaster.forecast(articles: articles)
/// print(forecast.textReport)
/// ```
public class FeedTrendForecaster {

    /// Minimum number of article mentions for a keyword to be considered a trend.
    public let minimumMentions: Int

    /// Number of days in the analysis window.
    public let windowDays: Int

    /// Minimum word length for keyword extraction.
    public var minimumWordLength: Int = 3

    // MARK: - Initialization

    /// Creates a new trend forecaster.
    /// - Parameters:
    ///   - minimumMentions: Minimum article mentions to qualify as a trend (default 3).
    ///   - windowDays: Analysis window in days (default 7).
    public init(minimumMentions: Int = 3, windowDays: Int = 7) {
        self.minimumMentions = max(1, minimumMentions)
        self.windowDays = max(1, windowDays)
    }

    // MARK: - Public API

    /// Article input type for the forecaster.
    public typealias ArticleInput = (title: String, feedName: String, publishedDate: Date?)

    /// Generates a full trend forecast from a collection of articles.
    /// - Parameter articles: Array of article tuples with title, feed name, and optional date.
    /// - Returns: A complete `TrendForecast` with signals, breakouts, and insights.
    public func forecast(articles: [(title: String, feedName: String, publishedDate: Date?)]) -> TrendForecast {
        let now = Date()
        let windowStart = Calendar.current.date(byAdding: .day, value: -windowDays, to: now) ?? now

        // Build keyword data: for each keyword track mentions per day and source feeds
        var keywordData: [String: KeywordRecord] = [:]

        for article in articles {
            let date = article.publishedDate ?? now
            guard date >= windowStart else { continue }

            let keywords = TextUtilities.extractSignificantWords(
                from: article.title,
                minimumLength: minimumWordLength
            )
            let uniqueKeywords = Set(keywords)

            for keyword in uniqueKeywords {
                var record = keywordData[keyword] ?? KeywordRecord()
                record.totalCount += 1
                record.feedSources.insert(article.feedName)
                if date < record.firstSeen { record.firstSeen = date }
                if date > record.lastSeen { record.lastSeen = date }

                let dayIndex = daysBetween(windowStart, date)
                record.dailyCounts[dayIndex, default: 0] += 1

                keywordData[keyword] = record
            }
        }

        // Filter to keywords meeting minimum mentions threshold
        let candidates = keywordData.filter { $0.value.totalCount >= minimumMentions }

        // Build signals
        var signals: [TrendSignal] = []
        for (keyword, record) in candidates {
            let momentum = computeMomentum(dailyCounts: record.dailyCounts, windowDays: windowDays)
            let spread = Double(record.feedSources.count)
            let phase = classifyPhase(momentum: momentum, dailyCounts: record.dailyCounts, windowDays: windowDays)
            let breakout = computeBreakoutProbability(momentum: momentum, spread: spread, totalArticles: articles.count)

            let signal = TrendSignal(
                topic: keyword,
                momentum: momentum,
                articleCount: record.totalCount,
                firstSeen: record.firstSeen,
                lastSeen: record.lastSeen,
                feedSources: Array(record.feedSources).sorted(),
                phase: phase,
                breakoutProbability: breakout
            )
            signals.append(signal)
        }

        // Sort by breakout probability
        signals.sort { $0.breakoutProbability > $1.breakoutProbability }

        // Generate proactive insights
        let insights = generateInsights(signals: signals)

        return TrendForecast(
            generatedAt: now,
            windowDays: windowDays,
            signals: signals,
            proactiveInsights: insights
        )
    }

    /// Detects only early-stage signals (emerging or accelerating).
    /// - Parameter articles: Array of article tuples.
    /// - Returns: Signals in the emerging or accelerating phase.
    public func detectEarlySignals(articles: [(title: String, feedName: String, publishedDate: Date?)]) -> [TrendSignal] {
        let full = forecast(articles: articles)
        return full.signals.filter { $0.phase == .emerging || $0.phase == .accelerating }
    }

    /// Compares two forecasts to show what changed between them.
    /// - Parameters:
    ///   - older: The earlier forecast.
    ///   - newer: The more recent forecast.
    /// - Returns: A `ForecastDiff` describing new, gone, and accelerated trends.
    public func compareForecasts(_ older: TrendForecast, _ newer: TrendForecast) -> ForecastDiff {
        let olderTopics = Dictionary(uniqueKeysWithValues: older.signals.map { ($0.topic, $0) })
        let newerTopics = Dictionary(uniqueKeysWithValues: newer.signals.map { ($0.topic, $0) })

        let newTrends = newer.signals.filter { olderTopics[$0.topic] == nil }
        let goneTrends = older.signals.filter { newerTopics[$0.topic] == nil }.map { $0.topic }

        var accelerated: [TrendSignal] = []
        for signal in newer.signals {
            if let oldSignal = olderTopics[signal.topic], signal.momentum > oldSignal.momentum {
                accelerated.append(signal)
            }
        }

        return ForecastDiff(
            newTrends: newTrends,
            goneTrends: goneTrends,
            acceleratedTrends: accelerated
        )
    }

    // MARK: - Internal Types

    private struct KeywordRecord {
        var totalCount: Int = 0
        var feedSources: Set<String> = []
        var firstSeen: Date = .distantFuture
        var lastSeen: Date = .distantPast
        /// Mention count per day index (0 = window start).
        var dailyCounts: [Int: Int] = [:]
    }

    // MARK: - Momentum Computation

    /// Computes momentum via linear regression slope on daily mention counts,
    /// normalized to 0.0–1.0.
    ///
    /// Uses closed-form sums for the evenly-spaced x-axis (0, 1, …, n−1)
    /// to avoid allocating temporary arrays per keyword. Only `sumY` and
    /// `sumXY` need to be computed from `dailyCounts`; `sumX`, `sumX²`,
    /// and the denominator are arithmetic-series constants.
    private func computeMomentum(dailyCounts: [Int: Int], windowDays: Int) -> Double {
        guard windowDays > 1 else { return 0.5 }

        let n = Double(windowDays)

        // Closed-form sums for x = 0, 1, …, n-1:
        //   sumX  = n(n-1)/2
        //   sumX2 = n(n-1)(2n-1)/6
        let sumX  = n * (n - 1.0) / 2.0
        let sumX2 = n * (n - 1.0) * (2.0 * n - 1.0) / 6.0

        let denominator = n * sumX2 - sumX * sumX
        guard abs(denominator) > 1e-10 else { return 0.5 }

        // Single pass over dailyCounts to compute sumY and sumXY.
        // Days with no entries contribute 0, so we only iterate present keys.
        var sumY  = 0.0
        var sumXY = 0.0
        for (day, count) in dailyCounts {
            let c = Double(count)
            sumY  += c
            sumXY += Double(day) * c
        }

        let slope = (n * sumXY - sumX * sumY) / denominator

        // Normalize: a slope of 1 article/day increase = momentum ~0.8
        // Sigmoid-like mapping
        let normalized = 1.0 / (1.0 + exp(-slope * 3.0))
        return min(1.0, max(0.0, normalized))
    }

    // MARK: - Phase Classification

    private func classifyPhase(momentum: Double, dailyCounts: [Int: Int], windowDays: Int) -> TrendPhase {
        // Check if mentions are concentrated in the recent half
        let midpoint = windowDays / 2
        let recentCount = (midpoint..<windowDays).reduce(0) { $0 + (dailyCounts[$1] ?? 0) }
        let olderCount = (0..<midpoint).reduce(0) { $0 + (dailyCounts[$1] ?? 0) }

        if momentum > 0.7 && recentCount > olderCount * 2 {
            return .accelerating
        } else if momentum > 0.6 && recentCount >= olderCount {
            return .emerging
        } else if momentum < 0.4 && olderCount > recentCount {
            return .declining
        } else {
            return .peaking
        }
    }

    // MARK: - Breakout Probability

    private func computeBreakoutProbability(momentum: Double, spread: Double, totalArticles: Int) -> Double {
        // Three factors:
        // 1. Momentum (0-1): higher = more likely
        // 2. Cross-feed spread: appearing in more feeds = stronger signal
        // 3. Recency weight built into momentum

        let spreadFactor = min(1.0, spread / 5.0)  // Cap at 5 feeds
        let momentumWeight = 0.6
        let spreadWeight = 0.4

        let raw = momentum * momentumWeight + spreadFactor * spreadWeight
        return min(1.0, max(0.0, raw))
    }

    // MARK: - Proactive Insights

    private func generateInsights(signals: [TrendSignal]) -> [String] {
        var insights: [String] = []

        // Cross-feed breakout candidates
        let crossFeed = signals.filter { $0.feedSources.count >= 3 && $0.phase != .declining }
        for signal in crossFeed.prefix(3) {
            insights.append(
                "\"\(signal.topic)\" appeared across \(signal.feedSources.count) feeds — potential breakout topic"
            )
        }

        // Rapidly accelerating
        let accelerating = signals.filter { $0.phase == .accelerating }
        for signal in accelerating.prefix(3) {
            insights.append(
                "\"\(signal.topic)\" is accelerating rapidly (momentum \(String(format: "%.0f%%", signal.momentum * 100))) — watch closely"
            )
        }

        // Fading trends
        let declining = signals.filter { $0.phase == .declining }
        for signal in declining.prefix(2) {
            insights.append(
                "\"\(signal.topic)\" momentum is declining — trend may be fading"
            )
        }

        // New arrivals (emerging with low article count = very new)
        let fresh = signals.filter { $0.phase == .emerging && $0.articleCount <= 5 }
        for signal in fresh.prefix(2) {
            insights.append(
                "\"\(signal.topic)\" just started appearing (\(signal.articleCount) articles) — early signal worth monitoring"
            )
        }

        if signals.count > 20 {
            insights.append(
                "High trend density: \(signals.count) active trends detected — consider narrowing your feed focus"
            )
        }

        return insights
    }

    // MARK: - Helpers

    private func daysBetween(_ start: Date, _ end: Date) -> Int {
        let components = Calendar.current.dateComponents([.day], from: start, to: end)
        return max(0, components.day ?? 0)
    }
}
