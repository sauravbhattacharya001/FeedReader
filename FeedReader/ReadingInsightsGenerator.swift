//
//  ReadingInsightsGenerator.swift
//  FeedReader
//
//  Generates personalized reading insights — think "Spotify Wrapped"
//  but for your RSS reading habits. Produces weekly and monthly insight
//  reports with trend comparisons, reading personality classification,
//  fun facts, and actionable recommendations.
//
//  Key features:
//  - Weekly & monthly insight report generation
//  - Period-over-period trend comparisons (this week vs last week, etc.)
//  - Reading personality classification (8 archetypes)
//  - Fun/quirky stats (page equivalents, word counts, streaks)
//  - Top feeds, categories, and peak hours analysis
//  - Diversity score measuring topic breadth
//  - Consistency rating and habit analysis
//  - Exportable insight summaries (plain text & JSON)
//
//  Persistence: JSON file in Documents directory.
//  Fully offline — no network, no dependencies beyond Foundation.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when a new insight report is generated.
    static let readingInsightGenerated = Notification.Name("ReadingInsightGeneratedNotification")
}

// MARK: - Reading Personality

/// Archetype describing a user's reading style based on behavior patterns.
enum ReadingPersonality: String, Codable, CaseIterable {
    case explorer       = "The Explorer"        // reads many different feeds/topics
    case specialist     = "The Specialist"       // concentrates on few feeds deeply
    case nightOwl       = "The Night Owl"        // reads mostly late at night
    case earlyBird      = "The Early Bird"       // reads mostly in the morning
    case weekendWarrior = "The Weekend Warrior"  // most reading on weekends
    case marathoner     = "The Marathoner"       // long unbroken reading sessions
    case snacker        = "The Snacker"          // many short sessions throughout day
    case consistent     = "The Steady Reader"    // even distribution across days

    /// Short description of this personality type.
    var tagline: String {
        switch self {
        case .explorer:       return "You cast a wide net — curious about everything."
        case .specialist:     return "Deep focus on what matters most to you."
        case .nightOwl:       return "The world sleeps; you read."
        case .earlyBird:      return "First coffee, then feeds."
        case .weekendWarrior: return "You save the best reading for downtime."
        case .marathoner:     return "Once you start, you don't stop."
        case .snacker:        return "A little here, a little there — always reading."
        case .consistent:     return "Steady and reliable — reading is your daily habit."
        }
    }
}

// MARK: - Insight Period

/// The time window an insight report covers.
enum InsightPeriod: String, Codable {
    case weekly
    case monthly
}

// MARK: - Models

/// A single reading event used as input for insight generation.
struct InsightReadEvent: Codable, Equatable {
    let link: String
    let title: String
    let feedName: String
    let category: String?
    let wordCount: Int?
    let timestamp: Date
}

/// Trend comparison between current period and previous period.
struct TrendComparison: Codable {
    let currentValue: Double
    let previousValue: Double

    /// Percentage change from previous to current. Nil if previous is 0.
    var percentChange: Double? {
        guard previousValue != 0 else { return nil }
        return ((currentValue - previousValue) / previousValue) * 100.0
    }

    /// Human-readable trend direction.
    var direction: String {
        guard let pct = percentChange else { return "new" }
        if pct > 5 { return "up" }
        if pct < -5 { return "down" }
        return "steady"
    }
}

/// Fun/quirky statistics to make insights engaging.
struct FunStats: Codable {
    /// Estimated total words read in the period.
    let totalWordsRead: Int
    /// Approximate book-page equivalents (250 words/page).
    let bookPagesEquivalent: Int
    /// Longest streak of consecutive reading days in the period.
    let longestStreakDays: Int
    /// Number of unique feeds read from.
    let uniqueFeedsRead: Int
    /// Number of unique categories/topics touched.
    let uniqueCategories: Int
    /// The single busiest reading day (date string + count).
    let busiestDay: (date: String, count: Int)?
    /// Average articles per reading day (days with ≥1 read).
    let avgArticlesPerActiveDay: Double

    // Codable conformance for the tuple
    enum CodingKeys: String, CodingKey {
        case totalWordsRead, bookPagesEquivalent, longestStreakDays
        case uniqueFeedsRead, uniqueCategories
        case busiestDayDate, busiestDayCount, avgArticlesPerActiveDay
    }

    init(totalWordsRead: Int, bookPagesEquivalent: Int, longestStreakDays: Int,
         uniqueFeedsRead: Int, uniqueCategories: Int,
         busiestDay: (date: String, count: Int)?, avgArticlesPerActiveDay: Double) {
        self.totalWordsRead = totalWordsRead
        self.bookPagesEquivalent = bookPagesEquivalent
        self.longestStreakDays = longestStreakDays
        self.uniqueFeedsRead = uniqueFeedsRead
        self.uniqueCategories = uniqueCategories
        self.busiestDay = busiestDay
        self.avgArticlesPerActiveDay = avgArticlesPerActiveDay
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalWordsRead = try c.decode(Int.self, forKey: .totalWordsRead)
        bookPagesEquivalent = try c.decode(Int.self, forKey: .bookPagesEquivalent)
        longestStreakDays = try c.decode(Int.self, forKey: .longestStreakDays)
        uniqueFeedsRead = try c.decode(Int.self, forKey: .uniqueFeedsRead)
        uniqueCategories = try c.decode(Int.self, forKey: .uniqueCategories)
        avgArticlesPerActiveDay = try c.decode(Double.self, forKey: .avgArticlesPerActiveDay)
        if let d = try c.decodeIfPresent(String.self, forKey: .busiestDayDate),
           let n = try c.decodeIfPresent(Int.self, forKey: .busiestDayCount) {
            busiestDay = (d, n)
        } else {
            busiestDay = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(totalWordsRead, forKey: .totalWordsRead)
        try c.encode(bookPagesEquivalent, forKey: .bookPagesEquivalent)
        try c.encode(longestStreakDays, forKey: .longestStreakDays)
        try c.encode(uniqueFeedsRead, forKey: .uniqueFeedsRead)
        try c.encode(uniqueCategories, forKey: .uniqueCategories)
        try c.encode(avgArticlesPerActiveDay, forKey: .avgArticlesPerActiveDay)
        try c.encode(busiestDay?.date, forKey: .busiestDayDate)
        try c.encode(busiestDay?.count, forKey: .busiestDayCount)
    }
}

/// Diversity score measuring how broadly the user reads.
struct DiversityScore: Codable {
    /// 0.0 – 1.0 Shannon entropy normalized by log(categoryCount).
    let topicDiversity: Double
    /// 0.0 – 1.0 Shannon entropy normalized by log(feedCount).
    let feedDiversity: Double
    /// Combined diversity score (average of topic and feed diversity).
    var overall: Double { (topicDiversity + feedDiversity) / 2.0 }

    /// Human-readable label.
    var label: String {
        switch overall {
        case 0.8...: return "Extremely diverse"
        case 0.6..<0.8: return "Well-rounded"
        case 0.4..<0.6: return "Moderately focused"
        case 0.2..<0.4: return "Narrowly focused"
        default: return "Hyper-specialized"
        }
    }
}

/// A complete insight report for one period.
struct InsightReport: Codable {
    let id: String
    let period: InsightPeriod
    let startDate: Date
    let endDate: Date
    let generatedAt: Date
    let totalArticlesRead: Int
    let articlesTrend: TrendComparison
    let topFeeds: [(name: String, count: Int)]
    let topCategories: [(name: String, count: Int)]
    let peakHours: [Int]   // top 3 hours (0-23)
    let personality: ReadingPersonality
    let funStats: FunStats
    let diversity: DiversityScore
    let consistencyRating: Double  // 0-1, how evenly spread across days
    let highlights: [String]       // generated text insights

    // Codable for arrays of tuples
    enum CodingKeys: String, CodingKey {
        case id, period, startDate, endDate, generatedAt, totalArticlesRead
        case articlesTrend, peakHours, personality, funStats, diversity
        case consistencyRating, highlights
        case topFeedNames, topFeedCounts, topCatNames, topCatCounts
    }

    init(id: String, period: InsightPeriod, startDate: Date, endDate: Date,
         generatedAt: Date, totalArticlesRead: Int, articlesTrend: TrendComparison,
         topFeeds: [(name: String, count: Int)],
         topCategories: [(name: String, count: Int)],
         peakHours: [Int], personality: ReadingPersonality,
         funStats: FunStats, diversity: DiversityScore,
         consistencyRating: Double, highlights: [String]) {
        self.id = id; self.period = period; self.startDate = startDate
        self.endDate = endDate; self.generatedAt = generatedAt
        self.totalArticlesRead = totalArticlesRead
        self.articlesTrend = articlesTrend; self.topFeeds = topFeeds
        self.topCategories = topCategories; self.peakHours = peakHours
        self.personality = personality; self.funStats = funStats
        self.diversity = diversity; self.consistencyRating = consistencyRating
        self.highlights = highlights
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        period = try c.decode(InsightPeriod.self, forKey: .period)
        startDate = try c.decode(Date.self, forKey: .startDate)
        endDate = try c.decode(Date.self, forKey: .endDate)
        generatedAt = try c.decode(Date.self, forKey: .generatedAt)
        totalArticlesRead = try c.decode(Int.self, forKey: .totalArticlesRead)
        articlesTrend = try c.decode(TrendComparison.self, forKey: .articlesTrend)
        peakHours = try c.decode([Int].self, forKey: .peakHours)
        personality = try c.decode(ReadingPersonality.self, forKey: .personality)
        funStats = try c.decode(FunStats.self, forKey: .funStats)
        diversity = try c.decode(DiversityScore.self, forKey: .diversity)
        consistencyRating = try c.decode(Double.self, forKey: .consistencyRating)
        highlights = try c.decode([String].self, forKey: .highlights)
        let fNames = try c.decode([String].self, forKey: .topFeedNames)
        let fCounts = try c.decode([Int].self, forKey: .topFeedCounts)
        topFeeds = zip(fNames, fCounts).map { ($0, $1) }
        let cNames = try c.decode([String].self, forKey: .topCatNames)
        let cCounts = try c.decode([Int].self, forKey: .topCatCounts)
        topCategories = zip(cNames, cCounts).map { ($0, $1) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(period, forKey: .period)
        try c.encode(startDate, forKey: .startDate)
        try c.encode(endDate, forKey: .endDate)
        try c.encode(generatedAt, forKey: .generatedAt)
        try c.encode(totalArticlesRead, forKey: .totalArticlesRead)
        try c.encode(articlesTrend, forKey: .articlesTrend)
        try c.encode(peakHours, forKey: .peakHours)
        try c.encode(personality, forKey: .personality)
        try c.encode(funStats, forKey: .funStats)
        try c.encode(diversity, forKey: .diversity)
        try c.encode(consistencyRating, forKey: .consistencyRating)
        try c.encode(highlights, forKey: .highlights)
        try c.encode(topFeeds.map { $0.name }, forKey: .topFeedNames)
        try c.encode(topFeeds.map { $0.count }, forKey: .topFeedCounts)
        try c.encode(topCategories.map { $0.name }, forKey: .topCatNames)
        try c.encode(topCategories.map { $0.count }, forKey: .topCatCounts)
    }
}

// MARK: - ReadingInsightsGenerator

class ReadingInsightsGenerator {

    // MARK: - Singleton

    static let shared = ReadingInsightsGenerator()

    // MARK: - Properties

    /// Previously generated reports, newest first.
    private(set) var reports: [InsightReport] = []

    /// Maximum stored reports.
    static let maxReports = 100

    /// Persistence file name.
    private static let fileName = "ReadingInsights.json"

    /// Persistence wrapper.
    private struct Storage: Codable {
        var reports: [InsightReport]
    }

    // MARK: - Init

    private init() {
        load()
    }

    // MARK: - Public API

    /// Generate a weekly insight report for the 7-day window ending on `endDate`.
    /// - Parameters:
    ///   - events: All reading events available (will be filtered to the window).
    ///   - endDate: Last day of the week (inclusive). Defaults to today.
    /// - Returns: The generated `InsightReport`.
    @discardableResult
    func generateWeeklyInsight(from events: [InsightReadEvent],
                                endDate: Date = Date()) -> InsightReport {
        let cal = Calendar.current
        let end = cal.startOfDay(for: endDate).addingTimeInterval(86399)
        let start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: endDate))!
        let prevEnd = start.addingTimeInterval(-1)
        let prevStart = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: prevEnd))!

        return generateInsight(period: .weekly, events: events,
                               start: start, end: end,
                               prevStart: prevStart, prevEnd: prevEnd)
    }

    /// Generate a monthly insight report for the 30-day window ending on `endDate`.
    @discardableResult
    func generateMonthlyInsight(from events: [InsightReadEvent],
                                 endDate: Date = Date()) -> InsightReport {
        let cal = Calendar.current
        let end = cal.startOfDay(for: endDate).addingTimeInterval(86399)
        let start = cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: endDate))!
        let prevEnd = start.addingTimeInterval(-1)
        let prevStart = cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: prevEnd))!

        return generateInsight(period: .monthly, events: events,
                               start: start, end: end,
                               prevStart: prevStart, prevEnd: prevEnd)
    }

    /// Get the most recent report for a given period, if any.
    func latestReport(for period: InsightPeriod) -> InsightReport? {
        reports.first { $0.period == period }
    }

    /// Export a report as a human-readable plain text summary.
    func exportAsText(_ report: InsightReport) -> String {
        let df = DateFormatting.mediumDate

        var lines: [String] = []
        let title = report.period == .weekly ? "Weekly" : "Monthly"
        lines.append("📊 \(title) Reading Insights")
        lines.append("\(df.string(from: report.startDate)) – \(df.string(from: report.endDate))")
        lines.append(String(repeating: "─", count: 40))
        lines.append("")

        // Personality
        lines.append("🧬 Your Reading Personality: \(report.personality.rawValue)")
        lines.append("   \(report.personality.tagline)")
        lines.append("")

        // Key numbers
        let arrow = trendArrow(report.articlesTrend)
        lines.append("📖 Articles Read: \(report.totalArticlesRead) \(arrow)")
        lines.append("📝 Words Read: ~\(formatNumber(report.funStats.totalWordsRead))")
        lines.append("📚 Book Pages Equivalent: \(report.funStats.bookPagesEquivalent)")
        lines.append("🔥 Longest Streak: \(report.funStats.longestStreakDays) days")
        lines.append("📡 Feeds Used: \(report.funStats.uniqueFeedsRead)")
        lines.append("")

        // Top feeds
        if !report.topFeeds.isEmpty {
            lines.append("⭐ Top Feeds:")
            for (i, feed) in report.topFeeds.prefix(5).enumerated() {
                lines.append("   \(i + 1). \(feed.name) (\(feed.count) articles)")
            }
            lines.append("")
        }

        // Peak hours
        if !report.peakHours.isEmpty {
            let hours = report.peakHours.map { formatHour($0) }.joined(separator: ", ")
            lines.append("⏰ Peak Reading Hours: \(hours)")
            lines.append("")
        }

        // Diversity
        lines.append("🌈 Diversity: \(report.diversity.label) (\(Int(report.diversity.overall * 100))%)")
        lines.append("📏 Consistency: \(Int(report.consistencyRating * 100))%")
        lines.append("")

        // Fun stats
        if let busiest = report.funStats.busiestDay {
            lines.append("🏆 Busiest Day: \(busiest.date) (\(busiest.count) articles)")
        }
        lines.append("📊 Avg per Active Day: \(String(format: "%.1f", report.funStats.avgArticlesPerActiveDay)) articles")
        lines.append("")

        // Highlights
        if !report.highlights.isEmpty {
            lines.append("💡 Highlights:")
            for h in report.highlights {
                lines.append("   • \(h)")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Export a report as a JSON string.
    func exportAsJSON(_ report: InsightReport) -> String? {
        let encoder = JSONCoding.iso8601PrettyEncoder
        guard let data = try? encoder.encode(report) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Delete all stored reports.
    func clearHistory() {
        reports.removeAll()
        save()
    }

    // MARK: - Core Generation

    private func generateInsight(period: InsightPeriod,
                                  events: [InsightReadEvent],
                                  start: Date, end: Date,
                                  prevStart: Date, prevEnd: Date) -> InsightReport {
        let current = events.filter { $0.timestamp >= start && $0.timestamp <= end }
        let previous = events.filter { $0.timestamp >= prevStart && $0.timestamp <= prevEnd }

        let trend = TrendComparison(currentValue: Double(current.count),
                                     previousValue: Double(previous.count))

        let topFeeds = computeTopItems(current.map { $0.feedName }, limit: 10)
        let topCats = computeTopItems(current.compactMap { $0.category }, limit: 10)

        let hourDist = computeHourDistribution(current)
        let peakHours = Array(hourDist.sorted { $0.value > $1.value }.prefix(3).map { $0.key })

        let personality = classifyPersonality(events: current, hourDist: hourDist)
        let funStats = computeFunStats(current, start: start, end: end)
        let diversity = computeDiversity(current)
        let consistency = computeConsistency(current, start: start, end: end)
        let highlights = generateHighlights(current: current, previous: previous,
                                             trend: trend, personality: personality,
                                             diversity: diversity)

        let report = InsightReport(
            id: UUID().uuidString,
            period: period, startDate: start, endDate: end,
            generatedAt: Date(), totalArticlesRead: current.count,
            articlesTrend: trend, topFeeds: topFeeds, topCategories: topCats,
            peakHours: peakHours, personality: personality,
            funStats: funStats, diversity: diversity,
            consistencyRating: consistency, highlights: highlights
        )

        reports.insert(report, at: 0)
        if reports.count > Self.maxReports {
            reports = Array(reports.prefix(Self.maxReports))
        }
        save()

        NotificationCenter.default.post(name: .readingInsightGenerated,
                                         object: self, userInfo: ["report": report])
        return report
    }

    // MARK: - Personality Classification

    private func classifyPersonality(events: [InsightReadEvent],
                                      hourDist: [Int: Int]) -> ReadingPersonality {
        guard !events.isEmpty else { return .consistent }

        let cal = Calendar.current

        // Check night owl (22-4) vs early bird (5-9)
        let nightCount = (22...23).reduce(0) { $0 + (hourDist[$1] ?? 0) }
            + (0...4).reduce(0) { $0 + (hourDist[$1] ?? 0) }
        let morningCount = (5...9).reduce(0) { $0 + (hourDist[$1] ?? 0) }
        let total = events.count

        if Double(nightCount) / Double(total) > 0.4 { return .nightOwl }
        if Double(morningCount) / Double(total) > 0.4 { return .earlyBird }

        // Check weekend warrior
        let weekendCount = events.filter {
            let wd = cal.component(.weekday, from: $0.timestamp)
            return wd == 1 || wd == 7
        }.count
        if Double(weekendCount) / Double(total) > 0.5 { return .weekendWarrior }

        // Check explorer vs specialist (feed diversity)
        let uniqueFeeds = Set(events.map { $0.feedName }).count
        if uniqueFeeds >= 8 { return .explorer }
        if uniqueFeeds <= 2 && total >= 5 { return .specialist }

        // Check session patterns (marathoner vs snacker)
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        var sessionLengths: [Int] = []
        var sessionStart = 0
        for i in 1..<sorted.count {
            let gap = sorted[i].timestamp.timeIntervalSince(sorted[i-1].timestamp)
            if gap > 1800 { // 30 min gap = new session
                sessionLengths.append(i - sessionStart)
                sessionStart = i
            }
        }
        sessionLengths.append(sorted.count - sessionStart)

        let avgSession = sessionLengths.isEmpty ? 0 :
            Double(sessionLengths.reduce(0, +)) / Double(sessionLengths.count)
        if avgSession >= 5 { return .marathoner }
        if sessionLengths.count >= 5 && avgSession < 3 { return .snacker }

        return .consistent
    }

    // MARK: - Analytics Helpers

    private func computeTopItems(_ items: [String], limit: Int) -> [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for item in items { counts[item, default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }
            .prefix(limit)
            .map { (name: $0.key, count: $0.value) }
    }

    private func computeHourDistribution(_ events: [InsightReadEvent]) -> [Int: Int] {
        let cal = Calendar.current
        var dist: [Int: Int] = [:]
        for e in events {
            let hour = cal.component(.hour, from: e.timestamp)
            dist[hour, default: 0] += 1
        }
        return dist
    }

    private func computeFunStats(_ events: [InsightReadEvent],
                                  start: Date, end: Date) -> FunStats {
        let cal = Calendar.current
        let avgWords = 800  // default article word count estimate

        let totalWords = events.reduce(0) { $0 + ($1.wordCount ?? avgWords) }

        // Daily counts for streak and busiest day
        let df = DateFormatting.isoDate
        var dailyCounts: [String: Int] = [:]
        for e in events {
            let key = df.string(from: e.timestamp)
            dailyCounts[key, default: 0] += 1
        }

        // Longest streak within period
        var date = start
        var currentStreak = 0
        var longestStreak = 0
        while date <= end {
            let key = df.string(from: date)
            if (dailyCounts[key] ?? 0) > 0 {
                currentStreak += 1
                longestStreak = max(longestStreak, currentStreak)
            } else {
                currentStreak = 0
            }
            date = cal.date(byAdding: .day, value: 1, to: date)!
        }

        let busiest = dailyCounts.max(by: { $0.value < $1.value })
        let activeDays = dailyCounts.values.filter { $0 > 0 }.count
        let avgPerDay = activeDays > 0 ? Double(events.count) / Double(activeDays) : 0

        return FunStats(
            totalWordsRead: totalWords,
            bookPagesEquivalent: totalWords / 250,
            longestStreakDays: longestStreak,
            uniqueFeedsRead: Set(events.map { $0.feedName }).count,
            uniqueCategories: Set(events.compactMap { $0.category }).count,
            busiestDay: busiest.map { ($0.key, $0.value) },
            avgArticlesPerActiveDay: avgPerDay
        )
    }

    private func computeDiversity(_ events: [InsightReadEvent]) -> DiversityScore {
        let topicDiv = shannonEntropy(events.compactMap { $0.category })
        let feedDiv = shannonEntropy(events.map { $0.feedName })
        return DiversityScore(topicDiversity: topicDiv, feedDiversity: feedDiv)
    }

    /// Normalized Shannon entropy: 0 = all same, 1 = perfectly uniform.
    private func shannonEntropy(_ items: [String]) -> Double {
        guard items.count > 1 else { return 0 }
        var counts: [String: Int] = [:]
        for item in items { counts[item, default: 0] += 1 }
        guard counts.count > 1 else { return 0 }

        let total = Double(items.count)
        let entropy = -counts.values.reduce(0.0) { acc, count in
            let p = Double(count) / total
            return acc + p * log2(p)
        }
        let maxEntropy = log2(Double(counts.count))
        return maxEntropy > 0 ? entropy / maxEntropy : 0
    }

    /// How evenly reading is spread across days in the period. 1.0 = perfectly even.
    private func computeConsistency(_ events: [InsightReadEvent],
                                     start: Date, end: Date) -> Double {
        let cal = Calendar.current
        let df = DateFormatting.isoDate

        // Pre-bucket event counts by date string in a single O(E) pass,
        // avoiding the previous O(days × events) repeated filter+format.
        var eventsByDate: [String: Int] = [:]
        for e in events {
            let key = df.string(from: e.timestamp)
            eventsByDate[key, default: 0] += 1
        }

        var dailyCounts: [Int] = []
        var date = start
        while date <= end {
            let key = df.string(from: date)
            dailyCounts.append(eventsByDate[key] ?? 0)
            date = cal.date(byAdding: .day, value: 1, to: date)!
        }

        guard dailyCounts.count > 1, dailyCounts.reduce(0, +) > 0 else { return 0 }

        let mean = dailyCounts.isEmpty ? 0.0 : Double(dailyCounts.reduce(0, +)) / Double(dailyCounts.count)
        let variance = dailyCounts.reduce(0.0) { $0 + pow(Double($1) - mean, 2) }
            / Double(dailyCounts.count)
        let cv = mean > 0 ? sqrt(variance) / mean : 0  // coefficient of variation

        // Invert: low CV = high consistency. Cap at 1.0.
        return max(0, min(1.0, 1.0 - cv / 2.0))
    }

    // MARK: - Highlight Generation

    private func generateHighlights(current: [InsightReadEvent],
                                     previous: [InsightReadEvent],
                                     trend: TrendComparison,
                                     personality: ReadingPersonality,
                                     diversity: DiversityScore) -> [String] {
        var h: [String] = []

        // Trend highlight
        if let pct = trend.percentChange {
            if pct > 20 {
                h.append("You read \(Int(pct))% more than last period — great momentum!")
            } else if pct < -20 {
                h.append("Reading dipped \(Int(abs(pct)))% vs. last period — busy week?")
            } else {
                h.append("Reading volume held steady compared to last period.")
            }
        } else if current.count > 0 {
            h.append("Welcome to your first insight period! 🎉")
        }

        // New feeds discovered
        let prevFeeds = Set(previous.map { $0.feedName })
        let newFeeds = Set(current.map { $0.feedName }).subtracting(prevFeeds)
        if !newFeeds.isEmpty {
            let names = newFeeds.prefix(3).joined(separator: ", ")
            h.append("Discovered \(newFeeds.count) new feed\(newFeeds.count == 1 ? "" : "s"): \(names)")
        }

        // Diversity note
        if diversity.overall > 0.7 {
            h.append("Impressive topic diversity — you're a true generalist reader.")
        } else if diversity.overall < 0.3 && current.count >= 5 {
            h.append("Very focused reading — consider exploring a new topic or two.")
        }

        // Fun comparisons
        let words = current.reduce(0) { $0 + ($1.wordCount ?? 800) }
        if words > 50000 {
            h.append("You read ~\(formatNumber(words)) words — that's a short novel!")
        } else if words > 20000 {
            h.append("~\(formatNumber(words)) words read — equivalent to \(words / 250) book pages.")
        }

        return h
    }

    // MARK: - Formatting Helpers

    private func trendArrow(_ trend: TrendComparison) -> String {
        switch trend.direction {
        case "up": return "↑ \(Int(trend.percentChange ?? 0))%"
        case "down": return "↓ \(Int(abs(trend.percentChange ?? 0)))%"
        case "steady": return "→"
        default: return "✨ new"
        }
    }

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func formatHour(_ hour: Int) -> String {
        if hour == 0 { return "12 AM" }
        if hour < 12 { return "\(hour) AM" }
        if hour == 12 { return "12 PM" }
        return "\(hour - 12) PM"
    }

    // MARK: - Persistence

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(Self.fileName)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let storage = try? JSONDecoder().decode(Storage.self, from: data) else { return }
        reports = storage.reports
    }

    private func save() {
        let storage = Storage(reports: reports)
        let encoder = JSONCoding.iso8601Encoder
        guard let data = try? encoder.encode(storage) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
