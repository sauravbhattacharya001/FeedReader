//
//  ReadingReportCard.swift
//  FeedReader
//
//  Generates periodic reading report cards (weekly/monthly) with
//  letter grades across multiple dimensions, trend analysis comparing
//  to previous periods, streaks, achievements, and personalized
//  recommendations for improving reading habits.
//
//  Key features:
//  - Weekly and monthly report generation
//  - 6 graded dimensions: Volume, Consistency, Diversity, Depth,
//    Discovery, and Engagement
//  - Letter grades (A+ through F) with composite GPA
//  - Period-over-period trend comparison (improving/declining/stable)
//  - Top feeds, categories, and reading times
//  - Personalized recommendations based on weak areas
//  - Achievement badges for milestones
//  - Export as JSON, Markdown, or self-contained HTML
//  - Report history with GPA trend tracking
//
//  Persistence: JSON file in Documents directory.
//  Fully offline — no network, no dependencies beyond Foundation.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    static let reportCardGenerated = Notification.Name("ReadingReportCardGeneratedNotification")
}

// MARK: - Report Period

/// The time period a report card covers.
enum ReportPeriod: String, Codable, CaseIterable {
    case weekly = "weekly"
    case monthly = "monthly"

    var label: String {
        switch self {
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }

    /// Number of days in this period.
    var days: Int {
        switch self {
        case .weekly: return 7
        case .monthly: return 30
        }
    }
}

// MARK: - Letter Grade

/// Letter grade with numeric value for GPA calculation.
enum LetterGrade: String, Codable, CaseIterable, Comparable {
    case aPlus = "A+"
    case a = "A"
    case aMinus = "A-"
    case bPlus = "B+"
    case b = "B"
    case bMinus = "B-"
    case cPlus = "C+"
    case c = "C"
    case cMinus = "C-"
    case d = "D"
    case f = "F"

    var numericValue: Double {
        switch self {
        case .aPlus:  return 4.0
        case .a:      return 4.0
        case .aMinus: return 3.7
        case .bPlus:  return 3.3
        case .b:      return 3.0
        case .bMinus: return 2.7
        case .cPlus:  return 2.3
        case .c:      return 2.0
        case .cMinus: return 1.7
        case .d:      return 1.0
        case .f:      return 0.0
        }
    }

    var emoji: String {
        switch self {
        case .aPlus, .a: return "🌟"
        case .aMinus, .bPlus: return "✨"
        case .b, .bMinus: return "👍"
        case .cPlus, .c: return "📖"
        case .cMinus, .d: return "📚"
        case .f: return "💤"
        }
    }

    static func from(score: Double) -> LetterGrade {
        switch score {
        case 95...Double.greatestFiniteMagnitude: return .aPlus
        case 90..<95: return .a
        case 87..<90: return .aMinus
        case 83..<87: return .bPlus
        case 80..<83: return .b
        case 77..<80: return .bMinus
        case 73..<77: return .cPlus
        case 70..<73: return .c
        case 67..<70: return .cMinus
        case 50..<67: return .d
        default: return .f
        }
    }

    static func < (lhs: LetterGrade, rhs: LetterGrade) -> Bool {
        return lhs.numericValue < rhs.numericValue
    }
}

// MARK: - Trend Direction

/// Whether a metric is improving, declining, or stable compared to previous period.
enum TrendDirection: String, Codable {
    case improving = "improving"
    case declining = "declining"
    case stable = "stable"
    case newMetric = "new"

    var emoji: String {
        switch self {
        case .improving: return "📈"
        case .declining: return "📉"
        case .stable:    return "➡️"
        case .newMetric: return "🆕"
        }
    }

    var label: String {
        switch self {
        case .improving: return "Improving"
        case .declining: return "Declining"
        case .stable:    return "Stable"
        case .newMetric: return "New"
        }
    }
}

// MARK: - Grading Dimension

/// The six dimensions on which reading habits are graded.
enum GradingDimension: String, Codable, CaseIterable {
    case volume = "volume"           // How much you read
    case consistency = "consistency" // How regularly you read
    case diversity = "diversity"     // Variety of feeds/categories
    case depth = "depth"             // Average reading time per article
    case discovery = "discovery"     // New feeds explored
    case engagement = "engagement"   // Bookmarks, highlights, notes

    var label: String {
        switch self {
        case .volume:      return "Volume"
        case .consistency: return "Consistency"
        case .diversity:   return "Diversity"
        case .depth:       return "Depth"
        case .discovery:   return "Discovery"
        case .engagement:  return "Engagement"
        }
    }

    var description: String {
        switch self {
        case .volume:      return "How many articles you read"
        case .consistency: return "How regularly you read"
        case .diversity:   return "Variety across feeds and categories"
        case .depth:       return "Time spent per article"
        case .discovery:   return "New feeds and topics explored"
        case .engagement:  return "Bookmarks, highlights, and notes"
        }
    }

    var icon: String {
        switch self {
        case .volume:      return "📊"
        case .consistency: return "📅"
        case .diversity:   return "🌈"
        case .depth:       return "🔍"
        case .discovery:   return "🧭"
        case .engagement:  return "💬"
        }
    }
}

// MARK: - Dimension Score

/// Score and grade for a single dimension.
struct DimensionScore: Codable {
    let dimension: GradingDimension
    let score: Double       // 0-100
    let grade: LetterGrade
    let trend: TrendDirection
    let detail: String      // Human-readable explanation
    let rawValue: Double    // The underlying metric value
    let previousValue: Double? // Previous period value for comparison
}

// MARK: - Achievement Badge

/// Milestone badges earned for reading accomplishments.
struct AchievementBadge: Codable, Identifiable {
    let id: String
    let name: String
    let emoji: String
    let description: String
    let earnedDate: Date

    static let allBadges: [(id: String, name: String, emoji: String, desc: String, check: (ReportCardData) -> Bool)] = [
        ("perfect_week", "Perfect Week", "🏆", "Read every day this week",
         { $0.activeDays >= 7 }),
        ("bookworm", "Bookworm", "🐛", "Read 50+ articles in one period",
         { $0.totalArticlesRead >= 50 }),
        ("explorer", "Explorer", "🗺️", "Read from 10+ different feeds",
         { $0.uniqueFeedsRead >= 10 }),
        ("deep_diver", "Deep Diver", "🤿", "Average reading time over 5 minutes",
         { $0.averageReadingTimeSeconds >= 300 }),
        ("night_owl", "Night Owl", "🦉", "Read 10+ articles between 10pm-4am",
         { $0.nightReads >= 10 }),
        ("early_bird", "Early Bird", "🐦", "Read 10+ articles between 5am-8am",
         { $0.morningReads >= 10 }),
        ("gpa_honor", "Honor Roll", "🎓", "Achieve a GPA of 3.5 or higher",
         { $0.compositeGPA >= 3.5 }),
        ("streak_master", "Streak Master", "🔥", "Maintain a 7+ day reading streak",
         { $0.currentStreak >= 7 }),
        ("curator", "Curator", "🖼️", "Bookmark or highlight 20+ articles",
         { $0.totalEngagements >= 20 }),
        ("speed_reader", "Speed Reader", "⚡", "Read 10+ articles in one day",
         { $0.maxArticlesInOneDay >= 10 }),
        ("category_king", "Category King", "👑", "Read from 5+ categories",
         { $0.uniqueCategories >= 5 }),
        ("improver", "Self-Improver", "📈", "Improve GPA from previous period",
         { $0.gpaTrend == .improving }),
    ]
}

// MARK: - Report Card Data (internal metrics)

/// Raw metrics collected for grading.
struct ReportCardData: Codable {
    let periodStart: Date
    let periodEnd: Date
    let period: ReportPeriod
    let totalArticlesRead: Int
    let activeDays: Int
    let uniqueFeedsRead: Int
    let uniqueCategories: Int
    let averageReadingTimeSeconds: Double
    let totalEngagements: Int   // bookmarks + highlights + notes
    let newFeedsAdded: Int
    let nightReads: Int         // 10pm - 4am
    let morningReads: Int       // 5am - 8am
    let maxArticlesInOneDay: Int
    let currentStreak: Int
    let compositeGPA: Double
    let gpaTrend: TrendDirection
    let feedBreakdown: [String: Int]   // feedName -> count
    let dailyCounts: [String: Int]     // "YYYY-MM-DD" -> count
    let hourlyDistribution: [Int: Int] // hour -> count
}

// MARK: - Report Card

/// A complete reading report card for a period.
struct ReadingReportCardEntry: Codable, Identifiable {
    let id: String
    let generatedDate: Date
    let period: ReportPeriod
    let periodStart: Date
    let periodEnd: Date
    let dimensionScores: [DimensionScore]
    let compositeGPA: Double
    let overallGrade: LetterGrade
    let trend: TrendDirection
    let achievements: [AchievementBadge]
    let recommendations: [String]
    let topFeeds: [(name: String, count: Int)]
    let data: ReportCardData

    // Codable conformance for topFeeds tuple
    enum CodingKeys: String, CodingKey {
        case id, generatedDate, period, periodStart, periodEnd
        case dimensionScores, compositeGPA, overallGrade, trend
        case achievements, recommendations, topFeedsNames, topFeedsCounts, data
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(generatedDate, forKey: .generatedDate)
        try container.encode(period, forKey: .period)
        try container.encode(periodStart, forKey: .periodStart)
        try container.encode(periodEnd, forKey: .periodEnd)
        try container.encode(dimensionScores, forKey: .dimensionScores)
        try container.encode(compositeGPA, forKey: .compositeGPA)
        try container.encode(overallGrade, forKey: .overallGrade)
        try container.encode(trend, forKey: .trend)
        try container.encode(achievements, forKey: .achievements)
        try container.encode(recommendations, forKey: .recommendations)
        try container.encode(topFeeds.map { $0.name }, forKey: .topFeedsNames)
        try container.encode(topFeeds.map { $0.count }, forKey: .topFeedsCounts)
        try container.encode(data, forKey: .data)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        generatedDate = try container.decode(Date.self, forKey: .generatedDate)
        period = try container.decode(ReportPeriod.self, forKey: .period)
        periodStart = try container.decode(Date.self, forKey: .periodStart)
        periodEnd = try container.decode(Date.self, forKey: .periodEnd)
        dimensionScores = try container.decode([DimensionScore].self, forKey: .dimensionScores)
        compositeGPA = try container.decode(Double.self, forKey: .compositeGPA)
        overallGrade = try container.decode(LetterGrade.self, forKey: .overallGrade)
        trend = try container.decode(TrendDirection.self, forKey: .trend)
        achievements = try container.decode([AchievementBadge].self, forKey: .achievements)
        recommendations = try container.decode([String].self, forKey: .recommendations)
        let names = try container.decode([String].self, forKey: .topFeedsNames)
        let counts = try container.decode([Int].self, forKey: .topFeedsCounts)
        topFeeds = zip(names, counts).map { (name: $0, count: $1) }
        data = try container.decode(ReportCardData.self, forKey: .data)
    }

    init(id: String, generatedDate: Date, period: ReportPeriod, periodStart: Date,
         periodEnd: Date, dimensionScores: [DimensionScore], compositeGPA: Double,
         overallGrade: LetterGrade, trend: TrendDirection, achievements: [AchievementBadge],
         recommendations: [String], topFeeds: [(name: String, count: Int)], data: ReportCardData) {
        self.id = id
        self.generatedDate = generatedDate
        self.period = period
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.dimensionScores = dimensionScores
        self.compositeGPA = compositeGPA
        self.overallGrade = overallGrade
        self.trend = trend
        self.achievements = achievements
        self.recommendations = recommendations
        self.topFeeds = topFeeds
        self.data = data
    }
}

// MARK: - ReadingReportCard Manager

/// Generates and stores reading report cards.
class ReadingReportCard {

    // MARK: - Singleton

    static let shared = ReadingReportCard()

    // MARK: - Storage

    private var reports: [ReadingReportCardEntry] = []
    private let fileName = "reading_report_cards.json"

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(fileName)
    }

    init() {
        load()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        reports = (try? decoder.decode([ReadingReportCardEntry].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateDecodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(reports) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Generate Report

    /// Generate a report card for the given period ending now (or at a custom date).
    /// Uses injected reading data for testability.
    func generateReport(
        period: ReportPeriod,
        endDate: Date = Date(),
        readEvents: [ReadEventInput] = [],
        engagementCount: Int = 0,
        newFeedsCount: Int = 0,
        currentStreak: Int = 0
    ) -> ReadingReportCardEntry {
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -period.days, to: endDate)!

        // Filter events to period
        let periodEvents = readEvents.filter { $0.date >= startDate && $0.date <= endDate }

        // Compute daily counts
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        var dailyCounts: [String: Int] = [:]
        var hourly: [Int: Int] = [:]
        var feedCounts: [String: Int] = [:]
        var categories: Set<String> = []
        var nightReads = 0
        var morningReads = 0

        for event in periodEvents {
            let dayKey = dateFormatter.string(from: event.date)
            dailyCounts[dayKey, default: 0] += 1
            let hour = calendar.component(.hour, from: event.date)
            hourly[hour, default: 0] += 1
            feedCounts[event.feedName, default: 0] += 1
            if let cat = event.category { categories.insert(cat) }
            if hour >= 22 || hour < 4 { nightReads += 1 }
            if hour >= 5 && hour < 8 { morningReads += 1 }
        }

        let activeDays = dailyCounts.count
        let totalRead = periodEvents.count
        let uniqueFeeds = Set(periodEvents.map { $0.feedName }).count
        let avgTime = periodEvents.isEmpty ? 0.0 :
            periodEvents.reduce(0.0) { $0 + $1.readingTimeSeconds } / Double(periodEvents.count)
        let maxInDay = dailyCounts.values.max() ?? 0

        // Previous period for comparison
        let prevEnd = startDate
        let prevStart = calendar.date(byAdding: .day, value: -period.days, to: prevEnd)!
        let prevEvents = readEvents.filter { $0.date >= prevStart && $0.date < prevEnd }
        let prevTotal = prevEvents.count
        let prevActiveDays = Set(prevEvents.map { dateFormatter.string(from: $0.date) }).count
        let prevUniqueFeeds = Set(prevEvents.map { $0.feedName }).count
        let prevAvgTime = prevEvents.isEmpty ? 0.0 :
            prevEvents.reduce(0.0) { $0 + $1.readingTimeSeconds } / Double(prevEvents.count)

        // Grade each dimension
        var scores: [DimensionScore] = []

        // 1. Volume: articles per day
        let articlesPerDay = period.days > 0 ? Double(totalRead) / Double(period.days) : 0
        let volumeScore = min(100, articlesPerDay * 20) // 5/day = 100
        let prevArticlesPerDay = period.days > 0 ? Double(prevTotal) / Double(period.days) : 0
        scores.append(DimensionScore(
            dimension: .volume,
            score: volumeScore,
            grade: LetterGrade.from(score: volumeScore),
            trend: trend(current: articlesPerDay, previous: prevArticlesPerDay),
            detail: String(format: "%.1f articles/day (%.0f total)", articlesPerDay, Double(totalRead)),
            rawValue: articlesPerDay,
            previousValue: prevArticlesPerDay
        ))

        // 2. Consistency: % of days with at least 1 read
        let consistencyPct = period.days > 0 ? Double(activeDays) / Double(period.days) * 100 : 0
        let prevConsistencyPct = period.days > 0 ? Double(prevActiveDays) / Double(period.days) * 100 : 0
        scores.append(DimensionScore(
            dimension: .consistency,
            score: consistencyPct,
            grade: LetterGrade.from(score: consistencyPct),
            trend: trend(current: consistencyPct, previous: prevConsistencyPct),
            detail: "\(activeDays)/\(period.days) days active",
            rawValue: consistencyPct,
            previousValue: prevConsistencyPct
        ))

        // 3. Diversity: unique feeds / expected
        let expectedFeeds: Double = period == .weekly ? 5 : 10
        let diversityScore = min(100, Double(uniqueFeeds) / expectedFeeds * 100)
        let prevDiversityScore = min(100, Double(prevUniqueFeeds) / expectedFeeds * 100)
        scores.append(DimensionScore(
            dimension: .diversity,
            score: diversityScore,
            grade: LetterGrade.from(score: diversityScore),
            trend: trend(current: diversityScore, previous: prevDiversityScore),
            detail: "\(uniqueFeeds) different feeds read",
            rawValue: Double(uniqueFeeds),
            previousValue: Double(prevUniqueFeeds)
        ))

        // 4. Depth: average reading time (target: 3 min = 180s)
        let depthScore = min(100, avgTime / 180.0 * 100)
        let prevDepthScore = min(100, prevAvgTime / 180.0 * 100)
        scores.append(DimensionScore(
            dimension: .depth,
            score: depthScore,
            grade: LetterGrade.from(score: depthScore),
            trend: trend(current: depthScore, previous: prevDepthScore),
            detail: String(format: "%.0fs avg reading time", avgTime),
            rawValue: avgTime,
            previousValue: prevAvgTime
        ))

        // 5. Discovery: new feeds added (target: 2/week, 5/month)
        let expectedNew: Double = period == .weekly ? 2 : 5
        let discoveryScore = min(100, Double(newFeedsCount) / expectedNew * 100)
        scores.append(DimensionScore(
            dimension: .discovery,
            score: discoveryScore,
            grade: LetterGrade.from(score: discoveryScore),
            trend: .newMetric,
            detail: "\(newFeedsCount) new feeds explored",
            rawValue: Double(newFeedsCount),
            previousValue: nil
        ))

        // 6. Engagement: interactions per article (target: 30% engagement rate)
        let engagementRate = totalRead > 0 ? Double(engagementCount) / Double(totalRead) * 100 : 0
        let engagementScore = min(100, engagementRate / 30.0 * 100)
        scores.append(DimensionScore(
            dimension: .engagement,
            score: engagementScore,
            grade: LetterGrade.from(score: engagementScore),
            trend: .newMetric,
            detail: "\(engagementCount) interactions (\(String(format: "%.0f%%", engagementRate)) rate)",
            rawValue: engagementRate,
            previousValue: nil
        ))

        // Composite GPA
        let gpa = scores.reduce(0.0) { $0 + $1.grade.numericValue } / Double(scores.count)
        let overallGrade = LetterGrade.from(score: scores.reduce(0.0) { $0 + $1.score } / Double(scores.count))

        // Previous GPA for trend
        let prevReport = reports.filter { $0.period == period }.last
        let gpaTrend: TrendDirection
        if let prev = prevReport {
            gpaTrend = trend(current: gpa, previous: prev.compositeGPA)
        } else {
            gpaTrend = .newMetric
        }

        let reportData = ReportCardData(
            periodStart: startDate, periodEnd: endDate, period: period,
            totalArticlesRead: totalRead, activeDays: activeDays,
            uniqueFeedsRead: uniqueFeeds, uniqueCategories: categories.count,
            averageReadingTimeSeconds: avgTime, totalEngagements: engagementCount,
            newFeedsAdded: newFeedsCount, nightReads: nightReads,
            morningReads: morningReads, maxArticlesInOneDay: maxInDay,
            currentStreak: currentStreak, compositeGPA: gpa, gpaTrend: gpaTrend,
            feedBreakdown: feedCounts, dailyCounts: dailyCounts,
            hourlyDistribution: hourly
        )

        // Check achievements
        var earned: [AchievementBadge] = []
        let existingBadgeIDs = Set(reports.flatMap { $0.achievements.map { $0.id } })
        for badge in AchievementBadge.allBadges {
            if !existingBadgeIDs.contains(badge.id) && badge.check(reportData) {
                earned.append(AchievementBadge(
                    id: badge.id, name: badge.name, emoji: badge.emoji,
                    description: badge.desc, earnedDate: endDate
                ))
            }
        }

        // Recommendations
        let recs = generateRecommendations(scores: scores, data: reportData)

        // Top feeds
        let topFeeds = feedCounts.sorted { $0.value > $1.value }.prefix(5).map { (name: $0.key, count: $0.value) }

        let entry = ReadingReportCardEntry(
            id: UUID().uuidString, generatedDate: Date(), period: period,
            periodStart: startDate, periodEnd: endDate,
            dimensionScores: scores, compositeGPA: gpa,
            overallGrade: overallGrade, trend: gpaTrend,
            achievements: earned, recommendations: recs,
            topFeeds: Array(topFeeds), data: reportData
        )

        reports.append(entry)
        save()
        NotificationCenter.default.post(name: .reportCardGenerated, object: entry)
        return entry
    }

    // MARK: - Recommendations

    private func generateRecommendations(scores: [DimensionScore], data: ReportCardData) -> [String] {
        var recs: [String] = []

        for score in scores.sorted(by: { $0.score < $1.score }) {
            if score.score >= 90 { continue }

            switch score.dimension {
            case .volume:
                if score.score < 50 {
                    recs.append("📊 Try reading at least 2-3 articles per day to build momentum.")
                } else {
                    recs.append("📊 You're reading well — push for 5 articles/day for top marks.")
                }
            case .consistency:
                if score.score < 50 {
                    recs.append("📅 Set a daily reading reminder — even 1 article counts toward consistency.")
                } else {
                    recs.append("📅 You read most days — try to fill in the gaps for a perfect streak.")
                }
            case .diversity:
                if score.score < 50 {
                    recs.append("🌈 Branch out! Subscribe to feeds in categories you don't usually read.")
                } else {
                    recs.append("🌈 Good variety — try adding one new feed from an unfamiliar topic.")
                }
            case .depth:
                if score.score < 50 {
                    recs.append("🔍 Slow down and spend more time with each article — quality over speed.")
                } else {
                    recs.append("🔍 Good depth — try the occasional long-form article for deeper learning.")
                }
            case .discovery:
                if score.score < 50 {
                    recs.append("🧭 Explore new feeds! Use the discovery feature to find fresh content.")
                } else {
                    recs.append("🧭 Keep exploring — each new feed brings fresh perspectives.")
                }
            case .engagement:
                if score.score < 50 {
                    recs.append("💬 Interact more — bookmark, highlight, or take notes on what you read.")
                } else {
                    recs.append("💬 Good engagement — try writing notes to deepen retention.")
                }
            }

            if recs.count >= 3 { break } // Top 3 recommendations
        }

        if recs.isEmpty {
            recs.append("🌟 Outstanding! You're excelling in all dimensions. Keep it up!")
        }

        return recs
    }

    // MARK: - Trend Calculation

    private func trend(current: Double, previous: Double) -> TrendDirection {
        let threshold = max(abs(previous) * 0.1, 0.5) // 10% or 0.5 absolute
        if current > previous + threshold { return .improving }
        if current < previous - threshold { return .declining }
        return .stable
    }

    // MARK: - Report Access

    /// All stored report cards, newest first.
    func allReports() -> [ReadingReportCardEntry] {
        return reports.sorted { $0.generatedDate > $1.generatedDate }
    }

    /// Reports filtered by period.
    func reports(for period: ReportPeriod) -> [ReadingReportCardEntry] {
        return allReports().filter { $0.period == period }
    }

    /// Most recent report for a period.
    func latestReport(for period: ReportPeriod) -> ReadingReportCardEntry? {
        return reports(for: period).first
    }

    /// GPA history for trend tracking.
    func gpaHistory(period: ReportPeriod) -> [(date: Date, gpa: Double)] {
        return reports.filter { $0.period == period }
            .sorted { $0.periodEnd < $1.periodEnd }
            .map { (date: $0.periodEnd, gpa: $0.compositeGPA) }
    }

    /// All earned achievement badges across all reports.
    func allAchievements() -> [AchievementBadge] {
        var seen: Set<String> = []
        var result: [AchievementBadge] = []
        for report in reports.sorted(by: { $0.generatedDate < $1.generatedDate }) {
            for badge in report.achievements {
                if !seen.contains(badge.id) {
                    seen.insert(badge.id)
                    result.append(badge)
                }
            }
        }
        return result
    }

    /// Delete all reports.
    func clearAll() {
        reports.removeAll()
        save()
    }

    /// Report count.
    var reportCount: Int { reports.count }

    // MARK: - Export

    /// Export a report as JSON.
    func exportJSON(report: ReadingReportCardEntry) -> String {
        let encoder = JSONEncoder()
        encoder.dateDecodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(report) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Export a report as Markdown.
    func exportMarkdown(report: ReadingReportCardEntry) -> String {
        var md = "# 📋 Reading Report Card\n\n"
        md += "**Period:** \(report.period.label) (\(formatDate(report.periodStart)) – \(formatDate(report.periodEnd)))\n"
        md += "**Overall Grade:** \(report.overallGrade.emoji) \(report.overallGrade.rawValue) (GPA: \(String(format: "%.2f", report.compositeGPA)))\n"
        md += "**Trend:** \(report.trend.emoji) \(report.trend.label)\n\n"

        md += "## 📊 Dimension Grades\n\n"
        md += "| Dimension | Grade | Score | Trend | Detail |\n"
        md += "|-----------|-------|-------|-------|--------|\n"
        for s in report.dimensionScores {
            md += "| \(s.dimension.icon) \(s.dimension.label) | \(s.grade.rawValue) | \(String(format: "%.0f", s.score)) | \(s.trend.emoji) | \(s.detail) |\n"
        }

        md += "\n## 📈 Top Feeds\n\n"
        for (i, feed) in report.topFeeds.enumerated() {
            md += "\(i + 1). **\(feed.name)** — \(feed.count) articles\n"
        }

        if !report.achievements.isEmpty {
            md += "\n## 🏅 New Achievements\n\n"
            for badge in report.achievements {
                md += "- \(badge.emoji) **\(badge.name)** — \(badge.description)\n"
            }
        }

        md += "\n## 💡 Recommendations\n\n"
        for rec in report.recommendations {
            md += "- \(rec)\n"
        }

        md += "\n## 📊 Quick Stats\n\n"
        md += "- Articles read: \(report.data.totalArticlesRead)\n"
        md += "- Active days: \(report.data.activeDays)/\(report.period.days)\n"
        md += "- Feeds read: \(report.data.uniqueFeedsRead)\n"
        md += "- Avg reading time: \(String(format: "%.0fs", report.data.averageReadingTimeSeconds))\n"
        md += "- Current streak: \(report.data.currentStreak) days\n"

        return md
    }

    /// Export a report as self-contained HTML.
    func exportHTML(report: ReadingReportCardEntry) -> String {
        let gradeColor: String
        switch report.overallGrade {
        case .aPlus, .a, .aMinus: gradeColor = "#22c55e"
        case .bPlus, .b, .bMinus: gradeColor = "#3b82f6"
        case .cPlus, .c, .cMinus: gradeColor = "#f59e0b"
        case .d: gradeColor = "#f97316"
        case .f: gradeColor = "#ef4444"
        }

        var dimensionBars = ""
        for s in report.dimensionScores {
            let barColor: String
            switch s.grade {
            case .aPlus, .a, .aMinus: barColor = "#22c55e"
            case .bPlus, .b, .bMinus: barColor = "#3b82f6"
            case .cPlus, .c, .cMinus: barColor = "#f59e0b"
            case .d: barColor = "#f97316"
            case .f: barColor = "#ef4444"
            }
            dimensionBars += """
            <div class="dim-row">
              <span class="dim-label">\(s.dimension.icon) \(s.dimension.label)</span>
              <div class="bar-bg"><div class="bar-fill" style="width:\(s.score)%;background:\(barColor)"></div></div>
              <span class="dim-grade">\(s.grade.rawValue) \(s.trend.emoji)</span>
            </div>
            """
        }

        var feedsList = ""
        for (i, f) in report.topFeeds.enumerated() {
            feedsList += "<li><strong>\(f.name)</strong> — \(f.count) articles</li>"
            if i >= 4 { break }
        }

        var badgesList = ""
        for b in report.achievements {
            badgesList += "<span class='badge'>\(b.emoji) \(b.name)</span> "
        }

        var recsList = ""
        for r in report.recommendations {
            recsList += "<li>\(r)</li>"
        }

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Reading Report Card</title>
        <style>
        *{margin:0;padding:0;box-sizing:border-box}
        body{font-family:-apple-system,system-ui,sans-serif;background:#0f172a;color:#e2e8f0;padding:24px}
        .card{background:#1e293b;border-radius:16px;padding:24px;margin-bottom:16px;max-width:600px;margin-left:auto;margin-right:auto}
        h1{text-align:center;font-size:28px;margin-bottom:4px}
        .subtitle{text-align:center;color:#94a3b8;margin-bottom:20px}
        .grade-circle{width:120px;height:120px;border-radius:50%;border:4px solid \(gradeColor);display:flex;flex-direction:column;align-items:center;justify-content:center;margin:0 auto 12px}
        .grade-letter{font-size:36px;font-weight:bold;color:\(gradeColor)}
        .gpa{font-size:14px;color:#94a3b8}
        .trend{text-align:center;font-size:16px;margin-bottom:20px}
        .dim-row{display:flex;align-items:center;gap:8px;margin-bottom:8px}
        .dim-label{width:120px;font-size:14px;flex-shrink:0}
        .bar-bg{flex:1;height:20px;background:#334155;border-radius:10px;overflow:hidden}
        .bar-fill{height:100%;border-radius:10px;transition:width 0.5s}
        .dim-grade{width:50px;font-size:13px;text-align:right;flex-shrink:0}
        h2{font-size:18px;margin-bottom:12px;color:#f8fafc}
        ul{list-style:none;padding-left:8px}
        li{margin-bottom:6px;font-size:14px}
        li::before{content:"•";color:#3b82f6;margin-right:8px}
        .badge{display:inline-block;background:#334155;padding:4px 10px;border-radius:12px;font-size:13px;margin:4px}
        .stats{display:grid;grid-template-columns:1fr 1fr;gap:8px}
        .stat{background:#334155;border-radius:8px;padding:12px;text-align:center}
        .stat-val{font-size:24px;font-weight:bold;color:#f8fafc}
        .stat-lbl{font-size:12px;color:#94a3b8}
        </style>
        </head>
        <body>
        <div class="card">
          <h1>📋 Report Card</h1>
          <p class="subtitle">\(report.period.label): \(formatDate(report.periodStart)) – \(formatDate(report.periodEnd))</p>
          <div class="grade-circle">
            <span class="grade-letter">\(report.overallGrade.rawValue)</span>
            <span class="gpa">GPA \(String(format: "%.2f", report.compositeGPA))</span>
          </div>
          <p class="trend">\(report.trend.emoji) \(report.trend.label)</p>
        </div>
        <div class="card">
          <h2>📊 Dimensions</h2>
          \(dimensionBars)
        </div>
        <div class="card">
          <h2>📈 Top Feeds</h2>
          <ul>\(feedsList)</ul>
        </div>
        \(report.achievements.isEmpty ? "" : """
        <div class="card">
          <h2>🏅 Achievements</h2>
          <div>\(badgesList)</div>
        </div>
        """)
        <div class="card">
          <h2>💡 Recommendations</h2>
          <ul>\(recsList)</ul>
        </div>
        <div class="card">
          <h2>📊 Quick Stats</h2>
          <div class="stats">
            <div class="stat"><div class="stat-val">\(report.data.totalArticlesRead)</div><div class="stat-lbl">Articles Read</div></div>
            <div class="stat"><div class="stat-val">\(report.data.activeDays)/\(report.period.days)</div><div class="stat-lbl">Active Days</div></div>
            <div class="stat"><div class="stat-val">\(report.data.uniqueFeedsRead)</div><div class="stat-lbl">Feeds Read</div></div>
            <div class="stat"><div class="stat-val">\(report.data.currentStreak)</div><div class="stat-lbl">Day Streak</div></div>
          </div>
        </div>
        </body></html>
        """
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }
}

// MARK: - Input Types

/// Input for report generation — lightweight struct for feeding reading data.
struct ReadEventInput: Codable {
    let articleTitle: String
    let feedName: String
    let category: String?
    let date: Date
    let readingTimeSeconds: Double
}
