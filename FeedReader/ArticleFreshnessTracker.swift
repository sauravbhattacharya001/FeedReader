//
//  ArticleFreshnessTracker.swift
//  FeedReader
//
//  Detects temporal references in article text, classifies content as
//  time-sensitive or evergreen, tracks freshness decay over time, and
//  flags stale articles whose referenced dates have passed.
//
//  Features:
//  - Temporal reference extraction (dates, relative phrases, deadlines)
//  - Freshness classification (breaking/timeSensitive/seasonal/evergreen)
//  - Staleness detection with configurable thresholds
//  - Freshness score (0.0–1.0) with exponential decay
//  - Batch analysis across article collections
//  - JSON persistence for tracked article freshness data
//

import Foundation

// MARK: - Data Types

/// A temporal reference found in article text.
struct TemporalReference: Codable, Equatable {
    /// The matched text from the article.
    let matchedText: String
    /// The type of temporal reference.
    let kind: TemporalReferenceKind
    /// Estimated absolute date, if resolvable.
    let resolvedDate: Date?
    /// Character offset in the source text.
    let offset: Int

    enum TemporalReferenceKind: String, Codable {
        case absoluteDate       // "March 15, 2026", "2026-03-15"
        case relativeDay        // "today", "yesterday", "tomorrow"
        case relativeWeek       // "this week", "next week", "last week"
        case relativeMonth      // "this month", "next month"
        case deadline           // "deadline", "expires", "ends on", "last day"
        case eventReference     // "upcoming", "starting soon", "registration open"
        case limitedOffer       // "limited time", "while supplies last", "act now"
        case seasonal           // "this summer", "holiday season", "back to school"
    }
}

/// Classification of an article's time-sensitivity.
enum FreshnessClassification: String, Codable, Comparable {
    case breaking        // Very time-sensitive (today/tomorrow references)
    case timeSensitive   // Has near-term deadlines or dates
    case seasonal        // Tied to a season or period
    case evergreen       // No significant temporal references

    private var sortOrder: Int {
        switch self {
        case .breaking: return 0
        case .timeSensitive: return 1
        case .seasonal: return 2
        case .evergreen: return 3
        }
    }

    static func < (lhs: FreshnessClassification, rhs: FreshnessClassification) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

/// Complete freshness analysis result for a single article.
struct FreshnessReport: Codable {
    /// Article identifier (URL or title hash).
    let articleId: String
    /// When the analysis was performed.
    let analysisDate: Date
    /// All temporal references found in the text.
    let temporalReferences: [TemporalReference]
    /// Overall classification.
    let classification: FreshnessClassification
    /// Freshness score from 0.0 (completely stale) to 1.0 (perfectly fresh).
    let freshnessScore: Double
    /// Whether the article is considered stale.
    let isStale: Bool
    /// The earliest expiry date found, if any.
    let earliestExpiry: Date?
    /// Human-readable freshness summary.
    let summary: String
    /// Number of temporal indicators detected.
    let temporalDensity: Int
}

/// Configuration for freshness tracking.
struct FreshnessConfig: Codable {
    /// Days after which an article with no temporal refs starts decaying.
    var evergreenDecayStartDays: Int = 90
    /// Half-life in days for freshness score decay.
    var decayHalfLifeDays: Double = 30.0
    /// Days past a referenced date before flagging as stale.
    var staleThresholdDays: Int = 3
    /// Minimum temporal references to classify as time-sensitive.
    var timeSensitiveMinRefs: Int = 1
    /// Minimum temporal references to classify as breaking.
    var breakingMinRefs: Int = 2

    static let `default` = FreshnessConfig()
}

/// Batch analysis summary across multiple articles.
struct FreshnessBatchSummary: Codable {
    /// Total articles analysed.
    let totalArticles: Int
    /// Count by classification.
    let classificationCounts: [String: Int]
    /// Number of stale articles.
    let staleCount: Int
    /// Average freshness score.
    let averageFreshnessScore: Double
    /// Articles with the lowest freshness scores.
    let stalestArticleIds: [String]
    /// Articles expiring soonest.
    let expiringNextIds: [String]
}

// MARK: - Tracker

/// Analyses and tracks article freshness based on temporal content references.
class ArticleFreshnessTracker {

    private let config: FreshnessConfig
    private var reports: [String: FreshnessReport] = [:]

    // MARK: - Temporal Patterns

    /// Relative day phrases mapped to day offsets from "today".
    private static let relativeDayPatterns: [(pattern: String, dayOffset: Int)] = [
        ("today", 0),
        ("tonight", 0),
        ("yesterday", -1),
        ("tomorrow", 1),
        ("day after tomorrow", 2),
    ]

    /// Relative week/month phrases.
    private static let relativeWeekPatterns: [String] = [
        "this week", "next week", "last week",
        "this weekend", "next weekend",
    ]

    private static let relativeMonthPatterns: [String] = [
        "this month", "next month", "last month",
    ]

    /// Deadline / urgency phrases.
    private static let deadlinePatterns: [String] = [
        "deadline", "due date", "expires", "expiring",
        "ends on", "last day", "final day", "closing date",
        "submission deadline", "registration closes",
        "offer ends", "sale ends", "deal expires",
    ]

    /// Event-related phrases.
    private static let eventPatterns: [String] = [
        "upcoming", "starting soon", "launches today",
        "registration open", "tickets available",
        "early bird", "register now", "sign up by",
        "event date", "conference date", "webinar on",
    ]

    /// Limited offer phrases.
    private static let limitedOfferPatterns: [String] = [
        "limited time", "while supplies last", "act now",
        "don't miss", "hurry", "only \\d+ left",
        "flash sale", "one-time offer", "exclusive offer",
        "limited availability", "selling fast",
    ]

    /// Seasonal phrases.
    private static let seasonalPatterns: [String] = [
        "this spring", "this summer", "this fall", "this autumn", "this winter",
        "holiday season", "back to school", "new year",
        "black friday", "cyber monday", "prime day",
        "valentine", "halloween", "thanksgiving",
        "christmas", "easter", "memorial day", "labor day",
    ]

    /// Month names for date parsing.
    private static let monthNames: [String: Int] = [
        "january": 1, "february": 2, "march": 3, "april": 4,
        "may": 5, "june": 6, "july": 7, "august": 8,
        "september": 9, "october": 10, "november": 11, "december": 12,
        "jan": 1, "feb": 2, "mar": 3, "apr": 4,
        "jun": 6, "jul": 7, "aug": 8, "sep": 9, "sept": 9,
        "oct": 10, "nov": 11, "dec": 12,
    ]

    // MARK: - Initialisation

    init(config: FreshnessConfig = .default) {
        self.config = config
    }

    // MARK: - Public API

    /// Analyse a single article's freshness.
    func analyse(articleId: String, text: String, publishDate: Date? = nil,
                 referenceDate: Date = Date()) -> FreshnessReport {
        let temporalRefs = extractTemporalReferences(from: text, referenceDate: referenceDate)
        let classification = classify(references: temporalRefs, referenceDate: referenceDate)
        let score = calculateFreshnessScore(
            references: temporalRefs,
            classification: classification,
            publishDate: publishDate,
            referenceDate: referenceDate
        )
        let earliest = findEarliestExpiry(references: temporalRefs, referenceDate: referenceDate)
        let stale = isArticleStale(
            references: temporalRefs,
            earliestExpiry: earliest,
            referenceDate: referenceDate
        )
        let summary = generateSummary(
            classification: classification,
            score: score,
            isStale: stale,
            temporalCount: temporalRefs.count,
            earliest: earliest,
            referenceDate: referenceDate
        )

        let report = FreshnessReport(
            articleId: articleId,
            analysisDate: referenceDate,
            temporalReferences: temporalRefs,
            classification: classification,
            freshnessScore: score,
            isStale: stale,
            earliestExpiry: earliest,
            summary: summary,
            temporalDensity: temporalRefs.count
        )
        reports[articleId] = report
        return report
    }

    /// Analyse multiple articles and produce a batch summary.
    func analyseBatch(articles: [(id: String, text: String, publishDate: Date?)],
                      referenceDate: Date = Date()) -> FreshnessBatchSummary {
        var articleReports: [FreshnessReport] = []
        for article in articles {
            let report = analyse(
                articleId: article.id,
                text: article.text,
                publishDate: article.publishDate,
                referenceDate: referenceDate
            )
            articleReports.append(report)
        }
        return summariseBatch(reports: articleReports)
    }

    /// Get the cached report for an article.
    func getReport(for articleId: String) -> FreshnessReport? {
        return reports[articleId]
    }

    /// Get all cached reports.
    func getAllReports() -> [FreshnessReport] {
        return Array(reports.values)
    }

    /// Get articles by classification.
    func getArticles(classification: FreshnessClassification) -> [FreshnessReport] {
        return reports.values.filter { $0.classification == classification }
    }

    /// Get all stale articles, sorted by freshness score (stalest first).
    func getStaleArticles() -> [FreshnessReport] {
        return reports.values
            .filter { $0.isStale }
            .sorted { $0.freshnessScore < $1.freshnessScore }
    }

    /// Get articles expiring within a given number of days.
    func getExpiringArticles(withinDays days: Int,
                              referenceDate: Date = Date()) -> [FreshnessReport] {
        let cutoff = Calendar.current.date(byAdding: .day, value: days, to: referenceDate)!
        return reports.values
            .filter { report in
                guard let expiry = report.earliestExpiry else { return false }
                return expiry <= cutoff && expiry >= referenceDate
            }
            .sorted { ($0.earliestExpiry ?? .distantFuture) < ($1.earliestExpiry ?? .distantFuture) }
    }

    /// Recalculate freshness scores using a new reference date.
    func refreshScores(referenceDate: Date = Date()) {
        for (id, report) in reports {
            let newScore = calculateFreshnessScore(
                references: report.temporalReferences,
                classification: report.classification,
                publishDate: nil,
                referenceDate: referenceDate
            )
            let stale = isArticleStale(
                references: report.temporalReferences,
                earliestExpiry: report.earliestExpiry,
                referenceDate: referenceDate
            )
            let summary = generateSummary(
                classification: report.classification,
                score: newScore,
                isStale: stale,
                temporalCount: report.temporalReferences.count,
                earliest: report.earliestExpiry,
                referenceDate: referenceDate
            )
            reports[id] = FreshnessReport(
                articleId: id,
                analysisDate: referenceDate,
                temporalReferences: report.temporalReferences,
                classification: report.classification,
                freshnessScore: newScore,
                isStale: stale,
                earliestExpiry: report.earliestExpiry,
                summary: summary,
                temporalDensity: report.temporalDensity
            )
        }
    }

    /// Remove tracked report for an article.
    func removeReport(for articleId: String) {
        reports.removeValue(forKey: articleId)
    }

    /// Clear all tracked reports.
    func clearAll() {
        reports.removeAll()
    }

    /// Number of tracked articles.
    var trackedCount: Int {
        return reports.count
    }

    // MARK: - Persistence

    /// Export all tracked reports as JSON data.
    func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Array(reports.values))
    }

    /// Import reports from JSON data (merges with existing).
    func importJSON(_ data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let imported = try decoder.decode([FreshnessReport].self, from: data)
        for report in imported {
            reports[report.articleId] = report
        }
    }

    /// Generate a plain-text freshness report.
    func generateTextReport() -> String {
        var lines: [String] = []
        lines.append("=== Article Freshness Report ===")
        lines.append("Tracked articles: \(reports.count)")
        lines.append("")

        let sorted = reports.values.sorted { $0.freshnessScore < $1.freshnessScore }

        let classifications = Dictionary(grouping: sorted, by: { $0.classification })
        for cls in [FreshnessClassification.breaking, .timeSensitive, .seasonal, .evergreen] {
            let count = classifications[cls]?.count ?? 0
            lines.append("\(cls.rawValue): \(count)")
        }

        let staleCount = sorted.filter { $0.isStale }.count
        lines.append("Stale: \(staleCount)")
        lines.append("")

        if !sorted.isEmpty {
            lines.append("--- Stalest Articles ---")
            for report in sorted.prefix(5) {
                let scoreStr = String(format: "%.1f%%", report.freshnessScore * 100)
                lines.append("[\(scoreStr)] \(report.articleId) — \(report.summary)")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Temporal Reference Extraction

    /// Extract all temporal references from article text.
    func extractTemporalReferences(from text: String,
                                    referenceDate: Date = Date()) -> [TemporalReference] {
        let lower = text.lowercased()
        var refs: [TemporalReference] = []
        var usedRanges: [Range<String.Index>] = []

        // 1. Absolute dates: "March 15, 2026" or "March 15"
        refs.append(contentsOf: extractAbsoluteDates(from: text, lower: lower,
                                                      referenceDate: referenceDate,
                                                      usedRanges: &usedRanges))

        // 2. ISO dates: "2026-03-15"
        refs.append(contentsOf: extractISODates(from: text, lower: lower,
                                                 usedRanges: &usedRanges))

        // 3. Relative day references
        refs.append(contentsOf: extractPatternMatches(
            from: lower, sourceText: text,
            patterns: Self.relativeDayPatterns.map { $0.pattern },
            kind: .relativeDay,
            referenceDate: referenceDate,
            usedRanges: &usedRanges
        ))

        // 4. Relative week references
        refs.append(contentsOf: extractPatternMatches(
            from: lower, sourceText: text,
            patterns: Self.relativeWeekPatterns,
            kind: .relativeWeek,
            referenceDate: referenceDate,
            usedRanges: &usedRanges
        ))

        // 5. Relative month references
        refs.append(contentsOf: extractPatternMatches(
            from: lower, sourceText: text,
            patterns: Self.relativeMonthPatterns,
            kind: .relativeMonth,
            referenceDate: referenceDate,
            usedRanges: &usedRanges
        ))

        // 6. Deadline phrases
        refs.append(contentsOf: extractPatternMatches(
            from: lower, sourceText: text,
            patterns: Self.deadlinePatterns,
            kind: .deadline,
            referenceDate: referenceDate,
            usedRanges: &usedRanges
        ))

        // 7. Event references
        refs.append(contentsOf: extractPatternMatches(
            from: lower, sourceText: text,
            patterns: Self.eventPatterns,
            kind: .eventReference,
            referenceDate: referenceDate,
            usedRanges: &usedRanges
        ))

        // 8. Limited offer phrases
        refs.append(contentsOf: extractPatternMatches(
            from: lower, sourceText: text,
            patterns: Self.limitedOfferPatterns,
            kind: .limitedOffer,
            referenceDate: referenceDate,
            usedRanges: &usedRanges
        ))

        // 9. Seasonal references
        refs.append(contentsOf: extractPatternMatches(
            from: lower, sourceText: text,
            patterns: Self.seasonalPatterns,
            kind: .seasonal,
            referenceDate: referenceDate,
            usedRanges: &usedRanges
        ))

        return refs.sorted { $0.offset < $1.offset }
    }

    // MARK: - Classification

    /// Classify an article based on its temporal references.
    func classify(references: [TemporalReference],
                  referenceDate: Date = Date()) -> FreshnessClassification {
        if references.isEmpty {
            return .evergreen
        }

        let hasDayRefs = references.contains { $0.kind == .relativeDay }
        let hasDeadlines = references.contains { $0.kind == .deadline }
        let hasLimited = references.contains { $0.kind == .limitedOffer }
        let hasEvents = references.contains { $0.kind == .eventReference }
        let hasSeasonal = references.contains { $0.kind == .seasonal }

        // Check for near-term absolute dates (within 2 days)
        let hasNearDates = references.contains { ref in
            guard let resolved = ref.resolvedDate else { return false }
            let days = Calendar.current.dateComponents([.day], from: referenceDate, to: resolved).day ?? 0
            return abs(days) <= 2
        }

        let urgentCount = references.filter { ref in
            ref.kind == .relativeDay || ref.kind == .deadline || ref.kind == .limitedOffer
        }.count

        // Breaking: multiple urgent indicators or "today" references
        if (hasDayRefs && (hasDeadlines || hasLimited)) || urgentCount >= config.breakingMinRefs || hasNearDates {
            return .breaking
        }

        // Time-sensitive: has deadlines, events, limited offers, or specific dates
        if hasDeadlines || hasEvents || hasLimited || hasNearDates {
            return .timeSensitive
        }

        // Has specific dates further out
        let hasFutureDates = references.contains { ref in
            guard let resolved = ref.resolvedDate else { return false }
            return resolved >= referenceDate
        }
        if hasFutureDates {
            return .timeSensitive
        }

        // Seasonal
        if hasSeasonal {
            return .seasonal
        }

        // Has temporal references but not urgent
        if references.count >= config.timeSensitiveMinRefs {
            return .timeSensitive
        }

        return .evergreen
    }

    // MARK: - Freshness Score

    /// Calculate a freshness score from 0.0 (stale) to 1.0 (fresh).
    func calculateFreshnessScore(references: [TemporalReference],
                                  classification: FreshnessClassification,
                                  publishDate: Date?,
                                  referenceDate: Date) -> Double {
        switch classification {
        case .evergreen:
            // Evergreen content decays slowly based on publish date
            guard let pubDate = publishDate else { return 1.0 }
            let daysSince = Calendar.current.dateComponents(
                [.day], from: pubDate, to: referenceDate
            ).day ?? 0
            if daysSince < config.evergreenDecayStartDays {
                return 1.0
            }
            let decayDays = Double(daysSince - config.evergreenDecayStartDays)
            return max(0.0, pow(0.5, decayDays / config.decayHalfLifeDays))

        case .seasonal:
            // Seasonal content has moderate decay
            guard let pubDate = publishDate else { return 0.8 }
            let daysSince = Calendar.current.dateComponents(
                [.day], from: pubDate, to: referenceDate
            ).day ?? 0
            let seasonLength = 90.0 // ~3 months
            return max(0.0, 1.0 - (Double(daysSince) / seasonLength))

        case .timeSensitive, .breaking:
            // Score based on proximity to referenced dates
            let resolvedDates = references.compactMap { $0.resolvedDate }
            if resolvedDates.isEmpty {
                // No resolved dates — use publish date with faster decay
                guard let pubDate = publishDate else { return 0.6 }
                let daysSince = Calendar.current.dateComponents(
                    [.day], from: pubDate, to: referenceDate
                ).day ?? 0
                return max(0.0, 1.0 - (Double(daysSince) / 14.0))
            }

            // Find the most relevant date (closest future, or most recent past)
            let futureDates = resolvedDates.filter { $0 >= referenceDate }
            if let nextDate = futureDates.min() {
                // Article references a future date — still fresh
                let daysUntil = Calendar.current.dateComponents(
                    [.day], from: referenceDate, to: nextDate
                ).day ?? 0
                if daysUntil <= 1 { return 1.0 }
                return min(1.0, 0.7 + 0.3 * (1.0 / Double(daysUntil)))
            }

            // All dates are in the past — decay from the most recent one
            let mostRecent = resolvedDates.max()!
            let daysPast = Calendar.current.dateComponents(
                [.day], from: mostRecent, to: referenceDate
            ).day ?? 0
            let threshold = Double(config.staleThresholdDays)
            if daysPast <= 0 { return 1.0 }
            return max(0.0, 1.0 - (Double(daysPast) / (threshold * 3.0)))
        }
    }

    // MARK: - Staleness Detection

    /// Determine if an article should be flagged as stale.
    func isArticleStale(references: [TemporalReference],
                        earliestExpiry: Date?,
                        referenceDate: Date) -> Bool {
        guard let expiry = earliestExpiry else {
            // No expiry — not stale (evergreen)
            return false
        }
        let daysPast = Calendar.current.dateComponents(
            [.day], from: expiry, to: referenceDate
        ).day ?? 0
        return daysPast >= config.staleThresholdDays
    }

    // MARK: - Private Helpers

    /// Find the earliest expiry/deadline date from references.
    private func findEarliestExpiry(references: [TemporalReference],
                                    referenceDate: Date) -> Date? {
        let dates = references.compactMap { $0.resolvedDate }
        return dates.min()
    }

    /// Generate a human-readable summary.
    private func generateSummary(classification: FreshnessClassification,
                                  score: Double,
                                  isStale: Bool,
                                  temporalCount: Int,
                                  earliest: Date?,
                                  referenceDate: Date) -> String {
        let scorePercent = String(format: "%.0f%%", score * 100)

        if isStale {
            if let exp = earliest {
                let days = Calendar.current.dateComponents([.day], from: exp, to: referenceDate).day ?? 0
                return "Stale (\(scorePercent) fresh) — expired \(days) day\(days == 1 ? "" : "s") ago"
            }
            return "Stale (\(scorePercent) fresh)"
        }

        switch classification {
        case .breaking:
            return "Breaking/urgent content (\(scorePercent) fresh, \(temporalCount) temporal ref\(temporalCount == 1 ? "" : "s"))"
        case .timeSensitive:
            if let exp = earliest, exp > referenceDate {
                let days = Calendar.current.dateComponents([.day], from: referenceDate, to: exp).day ?? 0
                return "Time-sensitive (\(scorePercent) fresh) — earliest date in \(days) day\(days == 1 ? "" : "s")"
            }
            return "Time-sensitive (\(scorePercent) fresh, \(temporalCount) temporal ref\(temporalCount == 1 ? "" : "s"))"
        case .seasonal:
            return "Seasonal content (\(scorePercent) fresh)"
        case .evergreen:
            return "Evergreen content (\(scorePercent) fresh)"
        }
    }

    /// Extract "Month Day, Year" and "Month Day" absolute date patterns.
    private func extractAbsoluteDates(from text: String, lower: String,
                                       referenceDate: Date,
                                       usedRanges: inout [Range<String.Index>]) -> [TemporalReference] {
        var results: [TemporalReference] = []

        // Pattern: "Month Day, Year" or "Month Day"
        for (monthName, monthNum) in Self.monthNames {
            // Skip short month names that are common words
            if monthName == "may" { continue }

            // Search for "MonthName DD, YYYY" or "MonthName DD"
            var searchStart = lower.startIndex
            while let range = lower.range(of: monthName, range: searchStart..<lower.endIndex) {
                defer { searchStart = range.upperBound }

                // Check word boundary before
                if range.lowerBound != lower.startIndex {
                    let prevChar = lower[lower.index(before: range.lowerBound)]
                    if prevChar.isLetter { continue }
                }

                // Check for overlapping range
                if usedRanges.contains(where: { $0.overlaps(range) }) { continue }

                // Try to read day number after the month name
                var afterMonth = range.upperBound
                // Skip whitespace
                while afterMonth < lower.endIndex && lower[afterMonth] == " " {
                    afterMonth = lower.index(after: afterMonth)
                }

                // Read digits
                var dayStr = ""
                var cursor = afterMonth
                while cursor < lower.endIndex && lower[cursor].isNumber && dayStr.count < 2 {
                    dayStr.append(lower[cursor])
                    cursor = lower.index(after: cursor)
                }

                guard let day = Int(dayStr), day >= 1, day <= 31 else { continue }

                // Try to read year after optional comma
                var year: Int? = nil
                var endOfMatch = cursor
                var yearCursor = cursor
                if yearCursor < lower.endIndex && lower[yearCursor] == "," {
                    yearCursor = lower.index(after: yearCursor)
                }
                while yearCursor < lower.endIndex && lower[yearCursor] == " " {
                    yearCursor = lower.index(after: yearCursor)
                }
                var yearStr = ""
                var yCursor = yearCursor
                while yCursor < lower.endIndex && lower[yCursor].isNumber && yearStr.count < 4 {
                    yearStr.append(lower[yCursor])
                    yCursor = lower.index(after: yCursor)
                }
                if yearStr.count == 4, let y = Int(yearStr) {
                    year = y
                    endOfMatch = yCursor
                }

                let matchedRange = range.lowerBound..<endOfMatch
                let matchedText = String(text[matchedRange])
                let offset = lower.distance(from: lower.startIndex, to: range.lowerBound)

                var components = DateComponents()
                components.month = monthNum
                components.day = day
                components.year = year ?? Calendar.current.component(.year, from: referenceDate)
                let resolved = Calendar.current.date(from: components)

                usedRanges.append(matchedRange)
                results.append(TemporalReference(
                    matchedText: matchedText,
                    kind: .absoluteDate,
                    resolvedDate: resolved,
                    offset: offset
                ))
            }
        }
        return results
    }

    /// Extract ISO 8601 date patterns: "YYYY-MM-DD".
    private func extractISODates(from text: String, lower: String,
                                  usedRanges: inout [Range<String.Index>]) -> [TemporalReference] {
        var results: [TemporalReference] = []
        guard let regex = try? NSRegularExpression(pattern: "\\b(\\d{4})-(\\d{2})-(\\d{2})\\b") else {
            return results
        }
        let nsRange = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        for match in regex.matches(in: lower, range: nsRange) {
            guard let wholeRange = Range(match.range, in: lower),
                  let yearRange = Range(match.range(at: 1), in: lower),
                  let monthRange = Range(match.range(at: 2), in: lower),
                  let dayRange = Range(match.range(at: 3), in: lower) else { continue }

            if usedRanges.contains(where: { $0.overlaps(wholeRange) }) { continue }

            guard let year = Int(lower[yearRange]),
                  let month = Int(lower[monthRange]),
                  let day = Int(lower[dayRange]),
                  month >= 1, month <= 12, day >= 1, day <= 31 else { continue }

            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            let resolved = Calendar.current.date(from: components)

            let offset = lower.distance(from: lower.startIndex, to: wholeRange.lowerBound)
            usedRanges.append(wholeRange)
            results.append(TemporalReference(
                matchedText: String(text[wholeRange]),
                kind: .absoluteDate,
                resolvedDate: resolved,
                offset: offset
            ))
        }
        return results
    }

    /// Extract phrase-based pattern matches.
    private func extractPatternMatches(from lower: String, sourceText: String,
                                        patterns: [String],
                                        kind: TemporalReference.TemporalReferenceKind,
                                        referenceDate: Date,
                                        usedRanges: inout [Range<String.Index>]) -> [TemporalReference] {
        var results: [TemporalReference] = []
        for pattern in patterns {
            // Check if pattern contains regex metacharacters
            let isRegex = pattern.contains("\\d") || pattern.contains("[") || pattern.contains("(")

            if isRegex {
                guard let regex = try? NSRegularExpression(
                    pattern: "\\b\(pattern)\\b",
                    options: .caseInsensitive
                ) else { continue }
                let nsRange = NSRange(lower.startIndex..<lower.endIndex, in: lower)
                for match in regex.matches(in: lower, range: nsRange) {
                    guard let range = Range(match.range, in: lower) else { continue }
                    if usedRanges.contains(where: { $0.overlaps(range) }) { continue }

                    let offset = lower.distance(from: lower.startIndex, to: range.lowerBound)
                    let resolved = resolveDate(for: pattern, kind: kind, referenceDate: referenceDate)
                    usedRanges.append(range)
                    results.append(TemporalReference(
                        matchedText: String(sourceText[range]),
                        kind: kind,
                        resolvedDate: resolved,
                        offset: offset
                    ))
                }
            } else {
                var searchStart = lower.startIndex
                while let range = lower.range(of: pattern, range: searchStart..<lower.endIndex) {
                    defer { searchStart = range.upperBound }

                    // Word boundary checks
                    if range.lowerBound != lower.startIndex {
                        let prev = lower[lower.index(before: range.lowerBound)]
                        if prev.isLetter { continue }
                    }
                    if range.upperBound != lower.endIndex {
                        let next = lower[range.upperBound]
                        if next.isLetter { continue }
                    }

                    if usedRanges.contains(where: { $0.overlaps(range) }) { continue }

                    let offset = lower.distance(from: lower.startIndex, to: range.lowerBound)
                    let resolved = resolveDate(for: pattern, kind: kind, referenceDate: referenceDate)
                    usedRanges.append(range)
                    results.append(TemporalReference(
                        matchedText: String(sourceText[range]),
                        kind: kind,
                        resolvedDate: resolved,
                        offset: offset
                    ))
                }
            }
        }
        return results
    }

    /// Resolve a matched pattern to an absolute date when possible.
    private func resolveDate(for pattern: String, kind: TemporalReference.TemporalReferenceKind,
                              referenceDate: Date) -> Date? {
        switch kind {
        case .relativeDay:
            if let entry = Self.relativeDayPatterns.first(where: { $0.pattern == pattern }) {
                return Calendar.current.date(byAdding: .day, value: entry.dayOffset, to: referenceDate)
            }
            return nil

        case .relativeWeek:
            switch pattern {
            case "this week", "this weekend":
                return referenceDate
            case "next week", "next weekend":
                return Calendar.current.date(byAdding: .weekOfYear, value: 1, to: referenceDate)
            case "last week":
                return Calendar.current.date(byAdding: .weekOfYear, value: -1, to: referenceDate)
            default:
                return nil
            }

        case .relativeMonth:
            switch pattern {
            case "this month":
                return referenceDate
            case "next month":
                return Calendar.current.date(byAdding: .month, value: 1, to: referenceDate)
            case "last month":
                return Calendar.current.date(byAdding: .month, value: -1, to: referenceDate)
            default:
                return nil
            }

        default:
            return nil
        }
    }

    /// Produce a batch summary from a set of reports.
    private func summariseBatch(reports: [FreshnessReport]) -> FreshnessBatchSummary {
        var counts: [String: Int] = [:]
        for cls in [FreshnessClassification.breaking, .timeSensitive, .seasonal, .evergreen] {
            counts[cls.rawValue] = reports.filter { $0.classification == cls }.count
        }
        let staleCount = reports.filter { $0.isStale }.count
        let avgScore = reports.isEmpty ? 0.0 : reports.map { $0.freshnessScore }.reduce(0, +) / Double(reports.count)

        let stalest = reports
            .sorted { $0.freshnessScore < $1.freshnessScore }
            .prefix(5)
            .map { $0.articleId }

        let expiringNext = reports
            .filter { $0.earliestExpiry != nil && !$0.isStale }
            .sorted { ($0.earliestExpiry ?? .distantFuture) < ($1.earliestExpiry ?? .distantFuture) }
            .prefix(5)
            .map { $0.articleId }

        return FreshnessBatchSummary(
            totalArticles: reports.count,
            classificationCounts: counts,
            staleCount: staleCount,
            averageFreshnessScore: avgScore,
            stalestArticleIds: Array(stalest),
            expiringNextIds: Array(expiringNext)
        )
    }
}
