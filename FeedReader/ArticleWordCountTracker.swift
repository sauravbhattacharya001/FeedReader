//
//  ArticleWordCountTracker.swift
//  FeedReader
//
//  Tracks word counts across articles the user reads. Maintains cumulative
//  reading volume statistics including total words read, average article
//  length, daily/weekly/monthly volumes, and reading velocity trends.
//
//  Usage:
//    let tracker = ArticleWordCountTracker()
//    tracker.recordArticle(title: "...", wordCount: 1200, feedName: "TechCrunch")
//    let stats = tracker.overallStats()
//    let daily = tracker.dailyVolume(for: Date())
//    let trend = tracker.velocityTrend(days: 30)
//

import Foundation

// MARK: - Models

/// A single reading record with word count metadata.
struct WordCountRecord: Codable, Equatable {
    let id: String
    let articleTitle: String
    let feedName: String
    let wordCount: Int
    let readAt: Date
    
    init(articleTitle: String, feedName: String, wordCount: Int, readAt: Date = Date()) {
        self.id = UUID().uuidString
        self.articleTitle = articleTitle
        self.feedName = feedName
        self.wordCount = wordCount
        self.readAt = readAt
    }
}

/// Aggregated reading volume statistics.
struct ReadingVolumeStats: Codable, Equatable {
    let totalArticles: Int
    let totalWords: Int
    let averageWordCount: Int
    let shortestArticle: Int?
    let longestArticle: Int?
    let medianWordCount: Int?
    let estimatedReadingHours: Double  // assuming 250 wpm
    let topFeedsByVolume: [FeedVolume]
    let period: String
}

/// Word count volume for a single feed.
struct FeedVolume: Codable, Equatable {
    let feedName: String
    let articleCount: Int
    let totalWords: Int
    let averageWords: Int
}

/// Daily reading volume snapshot.
struct DailyVolume: Codable, Equatable {
    let date: String  // yyyy-MM-dd
    let articleCount: Int
    let wordCount: Int
}

/// Velocity trend data point.
struct VelocityPoint: Codable, Equatable {
    let weekLabel: String  // "Week of Mar 23"
    let wordsPerDay: Int
    let articlesPerDay: Double
}

/// Length category for article classification.
enum ArticleLengthCategory: String, Codable, CaseIterable {
    case micro = "Micro (<200)"
    case short = "Short (200-500)"
    case medium = "Medium (500-1500)"
    case long = "Long (1500-3000)"
    case longform = "Longform (3000+)"
    
    var emoji: String {
        switch self {
        case .micro: return "📄"
        case .short: return "📃"
        case .medium: return "📑"
        case .long: return "📚"
        case .longform: return "📖"
        }
    }
    
    static func from(wordCount: Int) -> ArticleLengthCategory {
        switch wordCount {
        case ..<200: return .micro
        case 200..<500: return .short
        case 500..<1500: return .medium
        case 1500..<3000: return .long
        default: return .longform
        }
    }
}

/// Breakdown by article length category.
struct LengthDistribution: Codable, Equatable {
    let category: String
    let count: Int
    let percentage: Double
}

// MARK: - Tracker

/// Tracks article word counts and computes reading volume analytics.
final class ArticleWordCountTracker {
    
    private static let storageKey = "ArticleWordCountRecords"
    private let defaults: UserDefaults
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    // MARK: - Storage
    
    private func loadRecords() -> [WordCountRecord] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [] }
        return (try? JSONDecoder().decode([WordCountRecord].self, from: data)) ?? []
    }
    
    private func saveRecords(_ records: [WordCountRecord]) {
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
    
    // MARK: - Recording
    
    /// Record a completed article reading.
    @discardableResult
    func recordArticle(title: String, wordCount: Int, feedName: String, readAt: Date = Date()) -> WordCountRecord {
        let record = WordCountRecord(articleTitle: title, feedName: feedName, wordCount: max(0, wordCount), readAt: readAt)
        var records = loadRecords()
        records.append(record)
        saveRecords(records)
        return record
    }
    
    /// Remove a record by ID.
    func removeRecord(id: String) {
        var records = loadRecords()
        records.removeAll { $0.id == id }
        saveRecords(records)
    }
    
    /// Count total words from a text string.
    static func countWords(in text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return trimmed.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }
    
    // MARK: - Overall Stats
    
    /// Compute overall reading volume statistics.
    func overallStats() -> ReadingVolumeStats {
        return computeStats(from: loadRecords(), period: "All Time")
    }
    
    /// Stats for a specific date range.
    func stats(from startDate: Date, to endDate: Date) -> ReadingVolumeStats {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let records = loadRecords().filter { $0.readAt >= startDate && $0.readAt <= endDate }
        let period = "\(formatter.string(from: startDate)) – \(formatter.string(from: endDate))"
        return computeStats(from: records, period: period)
    }
    
    /// Stats for the last N days.
    func stats(lastDays days: Int) -> ReadingVolumeStats {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let records = loadRecords().filter { $0.readAt >= cutoff }
        return computeStats(from: records, period: "Last \(days) days")
    }
    
    private func computeStats(from records: [WordCountRecord], period: String) -> ReadingVolumeStats {
        guard !records.isEmpty else {
            return ReadingVolumeStats(
                totalArticles: 0, totalWords: 0, averageWordCount: 0,
                shortestArticle: nil, longestArticle: nil, medianWordCount: nil,
                estimatedReadingHours: 0, topFeedsByVolume: [], period: period
            )
        }
        
        let counts = records.map(\.wordCount)
        let sorted = counts.sorted()
        let total = counts.reduce(0, +)
        let median = sorted[sorted.count / 2]
        
        // Group by feed
        var feedGroups: [String: [WordCountRecord]] = [:]
        for r in records { feedGroups[r.feedName, default: []].append(r) }
        
        let feedVolumes = feedGroups.map { name, recs in
            let feedTotal = recs.map(\.wordCount).reduce(0, +)
            return FeedVolume(
                feedName: name,
                articleCount: recs.count,
                totalWords: feedTotal,
                averageWords: feedTotal / max(1, recs.count)
            )
        }.sorted { $0.totalWords > $1.totalWords }
        
        return ReadingVolumeStats(
            totalArticles: records.count,
            totalWords: total,
            averageWordCount: total / records.count,
            shortestArticle: sorted.first,
            longestArticle: sorted.last,
            medianWordCount: median,
            estimatedReadingHours: Double(total) / (250.0 * 60.0),
            topFeedsByVolume: Array(feedVolumes.prefix(10)),
            period: period
        )
    }
    
    // MARK: - Daily Volume
    
    /// Get daily reading volumes for the last N days.
    func dailyVolumes(days: Int = 30) -> [DailyVolume] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        let records = loadRecords()
        let cutoff = calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let filtered = records.filter { $0.readAt >= cutoff }
        
        // Group by day
        var dayGroups: [String: [WordCountRecord]] = [:]
        for r in filtered {
            let key = formatter.string(from: r.readAt)
            dayGroups[key, default: []].append(r)
        }
        
        // Fill in missing days
        var result: [DailyVolume] = []
        for offset in 0..<days {
            let date = calendar.date(byAdding: .day, value: -offset, to: Date())!
            let key = formatter.string(from: date)
            let group = dayGroups[key] ?? []
            result.append(DailyVolume(
                date: key,
                articleCount: group.count,
                wordCount: group.map(\.wordCount).reduce(0, +)
            ))
        }
        return result.reversed()
    }
    
    // MARK: - Velocity Trend
    
    /// Calculate reading velocity (words/day) over weekly intervals.
    func velocityTrend(weeks: Int = 8) -> [VelocityPoint] {
        let calendar = Calendar.current
        let records = loadRecords()
        let weekFormatter = DateFormatter()
        weekFormatter.dateFormat = "MMM d"
        
        var points: [VelocityPoint] = []
        for weekOffset in (0..<weeks).reversed() {
            let weekEnd = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: Date())!
            let weekStart = calendar.date(byAdding: .day, value: -6, to: weekEnd)!
            let weekRecords = records.filter { $0.readAt >= weekStart && $0.readAt <= weekEnd }
            let totalWords = weekRecords.map(\.wordCount).reduce(0, +)
            let label = "Week of \(weekFormatter.string(from: weekStart))"
            points.append(VelocityPoint(
                weekLabel: label,
                wordsPerDay: totalWords / 7,
                articlesPerDay: Double(weekRecords.count) / 7.0
            ))
        }
        return points
    }
    
    // MARK: - Length Distribution
    
    /// Get breakdown of articles by length category.
    func lengthDistribution() -> [LengthDistribution] {
        let records = loadRecords()
        guard !records.isEmpty else { return [] }
        
        var counts: [ArticleLengthCategory: Int] = [:]
        for cat in ArticleLengthCategory.allCases { counts[cat] = 0 }
        for r in records {
            let cat = ArticleLengthCategory.from(wordCount: r.wordCount)
            counts[cat, default: 0] += 1
        }
        
        let total = Double(records.count)
        return ArticleLengthCategory.allCases.compactMap { cat in
            let count = counts[cat] ?? 0
            guard count > 0 else { return nil }
            return LengthDistribution(
                category: "\(cat.emoji) \(cat.rawValue)",
                count: count,
                percentage: (Double(count) / total) * 100.0
            )
        }
    }
    
    // MARK: - Records Access
    
    /// All recorded entries, most recent first.
    func allRecords() -> [WordCountRecord] {
        return loadRecords().sorted { $0.readAt > $1.readAt }
    }
    
    /// Total record count.
    var recordCount: Int { loadRecords().count }
    
    /// Clear all records.
    func clearAll() {
        defaults.removeObject(forKey: Self.storageKey)
    }
}
