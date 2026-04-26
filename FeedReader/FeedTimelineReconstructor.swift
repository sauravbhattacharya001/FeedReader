//
//  FeedTimelineReconstructor.swift
//  FeedReader
//
//  Autonomous chronological event timeline reconstruction from articles across
//  multiple feeds. Extracts temporal events from article text, clusters them
//  into coherent timelines, detects gaps, and proactively surfaces emerging
//  patterns like acceleration, reversal, or convergence of separate storylines.
//
//  Agentic capabilities:
//  - Auto-extracts temporal events (dates, sequences, milestones) from articles
//  - Clusters events into named timelines via keyword/entity similarity
//  - Detects timeline gaps (missing periods that need investigation)
//  - Identifies acceleration/deceleration patterns in event frequency
//  - Detects storyline convergence (separate timelines merging)
//  - Proactively recommends follow-up when timelines stall or diverge
//  - Auto-monitor mode for continuous timeline updates
//  - Exports timelines as JSON, Markdown, or plain text
//
//  Fully offline — no network, no dependencies beyond Foundation.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    static let timelineCreated = Notification.Name("FeedTimelineCreatedNotification")
    static let timelineGapDetected = Notification.Name("FeedTimelineGapDetectedNotification")
    static let timelineConvergence = Notification.Name("FeedTimelineConvergenceNotification")
    static let timelineAcceleration = Notification.Name("FeedTimelineAccelerationNotification")
    static let timelineStalled = Notification.Name("FeedTimelineStalledNotification")
}

// MARK: - Models

/// A single temporal event extracted from an article.
struct TimelineEvent: Codable, Identifiable {
    let id: String
    let title: String
    let description: String
    let eventDate: Date
    let extractedDate: Date
    let sourceArticleTitle: String
    let sourceArticleLink: String
    let sourceFeed: String
    let keywords: [String]
    let confidence: Double  // 0.0–1.0 how confident the date extraction is
    let eventType: TimelineEventType

    init(title: String, description: String, eventDate: Date,
         sourceArticleTitle: String, sourceArticleLink: String,
         sourceFeed: String, keywords: [String] = [],
         confidence: Double = 0.8, eventType: TimelineEventType = .report) {
        self.id = UUID().uuidString
        self.title = title
        self.description = description
        self.eventDate = eventDate
        self.extractedDate = Date()
        self.sourceArticleTitle = sourceArticleTitle
        self.sourceArticleLink = sourceArticleLink
        self.sourceFeed = sourceFeed
        self.keywords = keywords
        self.confidence = min(1.0, max(0.0, confidence))
        self.eventType = eventType
    }
}

/// Classification of what kind of temporal event this is.
enum TimelineEventType: String, Codable {
    case announcement     // something declared or planned
    case milestone        // a key achievement or marker
    case report           // standard reporting of occurrence
    case prediction       // future-looking claim
    case correction       // correction of a prior event claim
    case escalation       // severity or scope increase
    case resolution       // a conclusion or settlement
}

/// A coherent timeline grouping related events.
struct Timeline: Codable, Identifiable {
    let id: String
    var name: String
    var events: [TimelineEvent]
    let createdDate: Date
    var lastUpdated: Date
    var keywords: [String]
    var status: TimelineStatus

    init(name: String, keywords: [String] = []) {
        self.id = UUID().uuidString
        self.name = name
        self.events = []
        self.createdDate = Date()
        self.lastUpdated = Date()
        self.keywords = keywords
        self.status = .active
    }

    /// Duration from earliest to latest event.
    var span: TimeInterval? {
        guard let first = events.map({ $0.eventDate }).min(),
              let last = events.map({ $0.eventDate }).max() else { return nil }
        return last.timeIntervalSince(first)
    }

    /// Average days between consecutive events.
    var averageCadenceDays: Double? {
        let sorted = events.sorted { $0.eventDate < $1.eventDate }
        guard sorted.count >= 2 else { return nil }
        var gaps: [Double] = []
        for i in 1..<sorted.count {
            gaps.append(sorted[i].eventDate.timeIntervalSince(sorted[i-1].eventDate) / 86400.0)
        }
        return gaps.reduce(0, +) / Double(gaps.count)
    }

    /// Number of unique source feeds.
    var sourceCount: Int {
        Set(events.map { $0.sourceFeed }).count
    }
}

/// Status of a timeline.
enum TimelineStatus: String, Codable {
    case active       // ongoing, receiving new events
    case stalled      // no new events for a while
    case resolved     // story concluded
    case converged    // merged into another timeline
}

/// A detected gap in a timeline.
struct TimelineGap: Codable {
    let timelineId: String
    let timelineName: String
    let gapStart: Date
    let gapEnd: Date
    let expectedCadenceDays: Double
    let actualGapDays: Double
    let severity: GapSeverity
}

enum GapSeverity: String, Codable {
    case minor    // 1.5–2x expected cadence
    case moderate // 2–3x expected cadence
    case major    // >3x expected cadence
}

/// A detected pattern in event frequency.
struct FrequencyPattern: Codable {
    let timelineId: String
    let timelineName: String
    let patternType: FrequencyPatternType
    let recentCadenceDays: Double
    let historicalCadenceDays: Double
    let ratio: Double
    let detectedDate: Date
}

enum FrequencyPatternType: String, Codable {
    case accelerating   // events coming faster
    case decelerating   // events slowing down
    case steady         // consistent pace
    case burst          // sudden cluster of events
}

/// A detected convergence of two timelines.
struct TimelineConvergence: Codable {
    let timelineAId: String
    let timelineAName: String
    let timelineBId: String
    let timelineBName: String
    let sharedKeywords: [String]
    let overlapScore: Double  // 0–1 Jaccard similarity
    let detectedDate: Date
}

/// Proactive recommendation.
struct TimelineRecommendation: Codable {
    let timelineId: String
    let timelineName: String
    let recommendation: String
    let reason: String
    let priority: RecommendationPriority
    let createdDate: Date
}

enum RecommendationPriority: String, Codable {
    case high
    case medium
    case low
}

/// Summary report.
struct TimelineReport: Codable {
    let generatedDate: Date
    let totalTimelines: Int
    let totalEvents: Int
    let activeTimelines: Int
    let stalledTimelines: Int
    let gaps: [TimelineGap]
    let patterns: [FrequencyPattern]
    let convergences: [TimelineConvergence]
    let recommendations: [TimelineRecommendation]
    let timelineSummaries: [TimelineSummary]
}

struct TimelineSummary: Codable {
    let timelineId: String
    let name: String
    let eventCount: Int
    let sourceCount: Int
    let spanDays: Double?
    let averageCadenceDays: Double?
    let status: TimelineStatus
    let latestEventDate: Date?
}

// MARK: - FeedTimelineReconstructor

/// Autonomous chronological event timeline reconstruction engine.
final class FeedTimelineReconstructor {

    // MARK: - Properties

    private(set) var timelines: [Timeline] = []
    private var monitorTimer: Timer?
    private var pendingArticles: [(title: String, link: String, feed: String, text: String, pubDate: Date)] = []

    /// Minimum Jaccard similarity for event-to-timeline matching.
    var matchThreshold: Double = 0.15

    /// Days without new events before marking a timeline as stalled.
    var stallThresholdDays: Double = 14.0

    /// Minimum events needed for gap/pattern detection.
    var minEventsForAnalysis: Int = 3

    // MARK: - Date Extraction

    /// Temporal patterns for extracting dates from text.
    private static let datePatterns: [(pattern: String, format: String?)] = [
        // ISO dates
        ("\\b(\\d{4}-\\d{2}-\\d{2})\\b", "yyyy-MM-dd"),
        // Written dates
        ("\\b(January|February|March|April|May|June|July|August|September|October|November|December)\\s+(\\d{1,2}),?\\s+(\\d{4})\\b", nil),
        // Short written
        ("\\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\\.?\\s+(\\d{1,2}),?\\s+(\\d{4})\\b", nil),
        // Relative: "last week", "yesterday", "today"
        ("\\b(yesterday|today|last week|last month)\\b", nil),
    ]

    private static let monthMap: [String: Int] = [
        "january": 1, "february": 2, "march": 3, "april": 4,
        "may": 5, "june": 6, "july": 7, "august": 8,
        "september": 9, "october": 10, "november": 11, "december": 12,
        "jan": 1, "feb": 2, "mar": 3, "apr": 4,
        "jun": 6, "jul": 7, "aug": 8, "sep": 9,
        "oct": 10, "nov": 11, "dec": 12
    ]

    // MARK: - Keyword Extraction

    /// Extract meaningful keywords from text.
    private func extractKeywords(from text: String, topN: Int = 10) -> [String] {
        let stopWords: Set<String> = [
            "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
            "have", "has", "had", "do", "does", "did", "will", "would", "could",
            "should", "may", "might", "shall", "can", "need", "dare", "ought",
            "used", "to", "of", "in", "for", "on", "with", "at", "by", "from",
            "as", "into", "through", "during", "before", "after", "above",
            "below", "between", "out", "off", "over", "under", "again",
            "further", "then", "once", "here", "there", "when", "where",
            "why", "how", "all", "both", "each", "few", "more", "most",
            "other", "some", "such", "no", "nor", "not", "only", "own",
            "same", "so", "than", "too", "very", "just", "because", "but",
            "and", "or", "if", "while", "about", "up", "it", "its", "this",
            "that", "these", "those", "i", "me", "my", "we", "our", "you",
            "your", "he", "him", "his", "she", "her", "they", "them", "their",
            "what", "which", "who", "whom", "said", "also", "new", "like",
            "one", "two", "many", "much", "well", "even", "still", "get"
        ]

        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }

        var freq: [String: Int] = [:]
        for w in words { freq[w, default: 0] += 1 }

        return freq.sorted { $0.value > $1.value }
            .prefix(topN)
            .map { $0.key }
    }

    /// Jaccard similarity between two keyword sets.
    private func jaccardSimilarity(_ a: [String], _ b: [String]) -> Double {
        let setA = Set(a)
        let setB = Set(b)
        guard !setA.isEmpty || !setB.isEmpty else { return 0 }
        let intersection = setA.intersection(setB).count
        let union = setA.union(setB).count
        return Double(intersection) / Double(union)
    }

    // MARK: - Date Parsing from Text

    /// Extract date mentions from article text.
    private func extractDates(from text: String, relativeTo refDate: Date) -> [(date: Date, snippet: String, confidence: Double)] {
        var results: [(date: Date, snippet: String, confidence: Double)] = []
        let calendar = Calendar.current
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd"

        // ISO dates
        if let regex = try? NSRegularExpression(pattern: "\\b(\\d{4}-\\d{2}-\\d{2})\\b") {
            let nsText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                let dateStr = nsText.substring(with: match.range(at: 1))
                if let date = isoFormatter.date(from: dateStr) {
                    let start = max(0, match.range.location - 30)
                    let len = min(nsText.length - start, match.range.length + 60)
                    let snippet = nsText.substring(with: NSRange(location: start, length: len))
                    results.append((date, snippet.trimmingCharacters(in: .whitespacesAndNewlines), 0.95))
                }
            }
        }

        // Written dates: "January 15, 2024"
        let writtenPattern = "\\b(January|February|March|April|May|June|July|August|September|October|November|December)\\s+(\\d{1,2}),?\\s+(\\d{4})\\b"
        if let regex = try? NSRegularExpression(pattern: writtenPattern, options: .caseInsensitive) {
            let nsText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                let monthStr = nsText.substring(with: match.range(at: 1)).lowercased()
                let dayStr = nsText.substring(with: match.range(at: 2))
                let yearStr = nsText.substring(with: match.range(at: 3))
                if let month = FeedTimelineReconstructor.monthMap[monthStr],
                   let day = Int(dayStr), let year = Int(yearStr) {
                    var comps = DateComponents()
                    comps.year = year; comps.month = month; comps.day = day
                    if let date = calendar.date(from: comps) {
                        let start = max(0, match.range.location - 30)
                        let len = min(nsText.length - start, match.range.length + 60)
                        let snippet = nsText.substring(with: NSRange(location: start, length: len))
                        results.append((date, snippet.trimmingCharacters(in: .whitespacesAndNewlines), 0.9))
                    }
                }
            }
        }

        // Short month: "Jan 15, 2024"
        let shortPattern = "\\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\\.?\\s+(\\d{1,2}),?\\s+(\\d{4})\\b"
        if let regex = try? NSRegularExpression(pattern: shortPattern, options: .caseInsensitive) {
            let nsText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                let monthStr = nsText.substring(with: match.range(at: 1)).lowercased()
                let dayStr = nsText.substring(with: match.range(at: 2))
                let yearStr = nsText.substring(with: match.range(at: 3))
                if let month = FeedTimelineReconstructor.monthMap[monthStr],
                   let day = Int(dayStr), let year = Int(yearStr) {
                    var comps = DateComponents()
                    comps.year = year; comps.month = month; comps.day = day
                    if let date = calendar.date(from: comps) {
                        let start = max(0, match.range.location - 30)
                        let len = min(nsText.length - start, match.range.length + 60)
                        let snippet = nsText.substring(with: NSRange(location: start, length: len))
                        results.append((date, snippet.trimmingCharacters(in: .whitespacesAndNewlines), 0.85))
                    }
                }
            }
        }

        // Relative dates
        let relativePattern = "\\b(yesterday|today|last week|last month)\\b"
        if let regex = try? NSRegularExpression(pattern: relativePattern, options: .caseInsensitive) {
            let nsText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                let term = nsText.substring(with: match.range(at: 1)).lowercased()
                var date: Date?
                switch term {
                case "today": date = refDate
                case "yesterday": date = calendar.date(byAdding: .day, value: -1, to: refDate)
                case "last week": date = calendar.date(byAdding: .weekOfYear, value: -1, to: refDate)
                case "last month": date = calendar.date(byAdding: .month, value: -1, to: refDate)
                default: break
                }
                if let d = date {
                    let start = max(0, match.range.location - 30)
                    let len = min(nsText.length - start, match.range.length + 60)
                    let snippet = nsText.substring(with: NSRange(location: start, length: len))
                    results.append((d, snippet.trimmingCharacters(in: .whitespacesAndNewlines), 0.6))
                }
            }
        }

        return results
    }

    // MARK: - Event Type Inference

    /// Infer event type from surrounding text.
    private func inferEventType(from text: String) -> TimelineEventType {
        let lower = text.lowercased()
        let patterns: [(keywords: [String], type: TimelineEventType)] = [
            (["announced", "unveil", "reveal", "launch", "introduce", "plan to", "set to"], .announcement),
            (["milestone", "achieved", "reached", "record", "breakthrough"], .milestone),
            (["correction", "corrected", "retract", "update:", "editor's note"], .correction),
            (["predict", "forecast", "expect", "anticipate", "projected"], .prediction),
            (["escalat", "worsen", "intensif", "surge", "crisis"], .escalation),
            (["resolv", "settled", "concluded", "ended", "final"], .resolution),
        ]
        for p in patterns {
            if p.keywords.contains(where: { lower.contains($0) }) {
                return p.type
            }
        }
        return .report
    }

    // MARK: - Core: Ingest Article

    /// Ingest an article and extract temporal events into timelines.
    @discardableResult
    func ingestArticle(title: String, link: String, feed: String,
                       text: String, pubDate: Date = Date()) -> [TimelineEvent] {
        let keywords = extractKeywords(from: title + " " + text)
        var extractedEvents: [TimelineEvent] = []

        // Extract date-anchored events
        let dateMentions = extractDates(from: text, relativeTo: pubDate)

        if dateMentions.isEmpty {
            // No explicit dates — use pub date as the event date
            let event = TimelineEvent(
                title: title,
                description: String(text.prefix(200)),
                eventDate: pubDate,
                sourceArticleTitle: title,
                sourceArticleLink: link,
                sourceFeed: feed,
                keywords: keywords,
                confidence: 0.5,
                eventType: inferEventType(from: text)
            )
            extractedEvents.append(event)
        } else {
            // Create events for each date mention
            for mention in dateMentions {
                let event = TimelineEvent(
                    title: title,
                    description: mention.snippet,
                    eventDate: mention.date,
                    sourceArticleTitle: title,
                    sourceArticleLink: link,
                    sourceFeed: feed,
                    keywords: keywords,
                    confidence: mention.confidence,
                    eventType: inferEventType(from: mention.snippet)
                )
                extractedEvents.append(event)
            }
        }

        // Assign events to timelines
        for event in extractedEvents {
            assignToTimeline(event)
        }

        return extractedEvents
    }

    /// Assign an event to the best-matching timeline, or create a new one.
    private func assignToTimeline(_ event: TimelineEvent) {
        var bestIdx = -1
        var bestScore = 0.0

        for (i, tl) in timelines.enumerated() {
            let score = jaccardSimilarity(event.keywords, tl.keywords)
            if score > bestScore {
                bestScore = score
                bestIdx = i
            }
        }

        if bestScore >= matchThreshold && bestIdx >= 0 {
            timelines[bestIdx].events.append(event)
            timelines[bestIdx].lastUpdated = Date()
            // Merge keywords
            let merged = Set(timelines[bestIdx].keywords + event.keywords)
            timelines[bestIdx].keywords = Array(merged.prefix(20))
        } else {
            // Create new timeline named from top keywords
            let name = event.keywords.prefix(3).joined(separator: " / ")
                .capitalized
            var tl = Timeline(name: name.isEmpty ? event.title : name,
                              keywords: event.keywords)
            tl.events.append(event)
            timelines.append(tl)
            NotificationCenter.default.post(name: .timelineCreated, object: nil,
                                            userInfo: ["timelineId": tl.id, "name": tl.name])
        }
    }

    // MARK: - Analysis: Gap Detection

    /// Detect gaps in timelines where events are missing.
    func detectGaps() -> [TimelineGap] {
        var gaps: [TimelineGap] = []

        for tl in timelines where tl.events.count >= minEventsForAnalysis {
            guard let cadence = tl.averageCadenceDays, cadence > 0 else { continue }
            let sorted = tl.events.sorted { $0.eventDate < $1.eventDate }

            for i in 1..<sorted.count {
                let gapDays = sorted[i].eventDate.timeIntervalSince(sorted[i-1].eventDate) / 86400.0
                let ratio = gapDays / cadence

                let severity: GapSeverity?
                if ratio > 3.0 { severity = .major }
                else if ratio > 2.0 { severity = .moderate }
                else if ratio > 1.5 { severity = .minor }
                else { severity = nil }

                if let sev = severity {
                    let gap = TimelineGap(
                        timelineId: tl.id, timelineName: tl.name,
                        gapStart: sorted[i-1].eventDate, gapEnd: sorted[i].eventDate,
                        expectedCadenceDays: cadence, actualGapDays: gapDays,
                        severity: sev
                    )
                    gaps.append(gap)
                    NotificationCenter.default.post(name: .timelineGapDetected, object: nil,
                                                    userInfo: ["gap": gap.timelineName, "severity": sev.rawValue])
                }
            }
        }

        return gaps
    }

    // MARK: - Analysis: Frequency Patterns

    /// Detect acceleration/deceleration patterns in event frequency.
    func detectFrequencyPatterns() -> [FrequencyPattern] {
        var patterns: [FrequencyPattern] = []

        for tl in timelines where tl.events.count >= minEventsForAnalysis {
            let sorted = tl.events.sorted { $0.eventDate < $1.eventDate }
            let midpoint = sorted.count / 2

            // Split into first half and second half
            let firstHalf = Array(sorted.prefix(midpoint))
            let secondHalf = Array(sorted.suffix(from: midpoint))

            guard firstHalf.count >= 2, secondHalf.count >= 2 else { continue }

            let firstGaps = (1..<firstHalf.count).map {
                firstHalf[$0].eventDate.timeIntervalSince(firstHalf[$0-1].eventDate) / 86400.0
            }
            let secondGaps = (1..<secondHalf.count).map {
                secondHalf[$0].eventDate.timeIntervalSince(secondHalf[$0-1].eventDate) / 86400.0
            }

            let firstAvg = firstGaps.reduce(0, +) / Double(firstGaps.count)
            let secondAvg = secondGaps.reduce(0, +) / Double(secondGaps.count)

            guard firstAvg > 0 else { continue }
            let ratio = secondAvg / firstAvg

            let patternType: FrequencyPatternType
            if ratio < 0.5 { patternType = .burst }
            else if ratio < 0.8 { patternType = .accelerating }
            else if ratio > 1.5 { patternType = .decelerating }
            else { patternType = .steady }

            let fp = FrequencyPattern(
                timelineId: tl.id, timelineName: tl.name,
                patternType: patternType,
                recentCadenceDays: secondAvg,
                historicalCadenceDays: firstAvg,
                ratio: ratio,
                detectedDate: Date()
            )
            patterns.append(fp)

            if patternType == .accelerating || patternType == .burst {
                NotificationCenter.default.post(name: .timelineAcceleration, object: nil,
                                                userInfo: ["timeline": tl.name, "ratio": ratio])
            }
        }

        return patterns
    }

    // MARK: - Analysis: Convergence Detection

    /// Detect timelines that may be converging (covering the same story).
    func detectConvergences() -> [TimelineConvergence] {
        var convergences: [TimelineConvergence] = []

        for i in 0..<timelines.count {
            for j in (i+1)..<timelines.count {
                let sim = jaccardSimilarity(timelines[i].keywords, timelines[j].keywords)
                if sim >= 0.3 {
                    let shared = Set(timelines[i].keywords).intersection(Set(timelines[j].keywords))
                    let conv = TimelineConvergence(
                        timelineAId: timelines[i].id, timelineAName: timelines[i].name,
                        timelineBId: timelines[j].id, timelineBName: timelines[j].name,
                        sharedKeywords: Array(shared),
                        overlapScore: sim,
                        detectedDate: Date()
                    )
                    convergences.append(conv)
                    NotificationCenter.default.post(name: .timelineConvergence, object: nil,
                                                    userInfo: ["a": timelines[i].name, "b": timelines[j].name, "overlap": sim])
                }
            }
        }

        return convergences
    }

    // MARK: - Stall Detection

    /// Mark timelines as stalled if no events recently.
    func detectStalls() {
        let now = Date()
        for i in 0..<timelines.count where timelines[i].status == .active {
            let latestEvent = timelines[i].events.map({ $0.eventDate }).max() ?? timelines[i].createdDate
            let daysSince = now.timeIntervalSince(latestEvent) / 86400.0
            if daysSince > stallThresholdDays {
                timelines[i].status = .stalled
                NotificationCenter.default.post(name: .timelineStalled, object: nil,
                                                userInfo: ["timeline": timelines[i].name, "daysSince": daysSince])
            }
        }
    }

    // MARK: - Recommendations

    /// Generate proactive recommendations.
    func generateRecommendations() -> [TimelineRecommendation] {
        var recs: [TimelineRecommendation] = []
        let gaps = detectGaps()
        let patterns = detectFrequencyPatterns()
        let convergences = detectConvergences()

        detectStalls()

        // Gap-based recommendations
        for gap in gaps where gap.severity == .major {
            recs.append(TimelineRecommendation(
                timelineId: gap.timelineId, timelineName: gap.timelineName,
                recommendation: "Investigate the \(Int(gap.actualGapDays))-day gap between events",
                reason: "Expected ~\(Int(gap.expectedCadenceDays))-day cadence but found \(Int(gap.actualGapDays))-day gap",
                priority: .high, createdDate: Date()
            ))
        }

        // Acceleration recommendations
        for pattern in patterns where pattern.patternType == .accelerating || pattern.patternType == .burst {
            recs.append(TimelineRecommendation(
                timelineId: pattern.timelineId, timelineName: pattern.timelineName,
                recommendation: "Story is \(pattern.patternType.rawValue) — monitor closely",
                reason: "Cadence changed from \(String(format: "%.1f", pattern.historicalCadenceDays)) to \(String(format: "%.1f", pattern.recentCadenceDays)) days",
                priority: pattern.patternType == .burst ? .high : .medium, createdDate: Date()
            ))
        }

        // Convergence recommendations
        for conv in convergences {
            recs.append(TimelineRecommendation(
                timelineId: conv.timelineAId, timelineName: conv.timelineAName,
                recommendation: "Consider merging with '\(conv.timelineBName)' — \(Int(conv.overlapScore * 100))% overlap",
                reason: "Shared keywords: \(conv.sharedKeywords.prefix(5).joined(separator: ", "))",
                priority: conv.overlapScore > 0.5 ? .high : .medium, createdDate: Date()
            ))
        }

        // Stalled timeline recommendations
        for tl in timelines where tl.status == .stalled {
            let latestDate = tl.events.map({ $0.eventDate }).max() ?? tl.createdDate
            let daysSince = Int(Date().timeIntervalSince(latestDate) / 86400.0)
            recs.append(TimelineRecommendation(
                timelineId: tl.id, timelineName: tl.name,
                recommendation: "Timeline stalled — search for updates",
                reason: "No events in \(daysSince) days",
                priority: .low, createdDate: Date()
            ))
        }

        // Single-source recommendations
        for tl in timelines where tl.events.count >= 3 && tl.sourceCount == 1 {
            recs.append(TimelineRecommendation(
                timelineId: tl.id, timelineName: tl.name,
                recommendation: "Only one source covering this timeline — seek diverse sources",
                reason: "All \(tl.events.count) events from '\(tl.events.first?.sourceFeed ?? "unknown")'",
                priority: .medium, createdDate: Date()
            ))
        }

        return recs
    }

    // MARK: - Merge Timelines

    /// Merge two timelines into one.
    func mergeTimelines(sourceId: String, targetId: String) -> Bool {
        guard let srcIdx = timelines.firstIndex(where: { $0.id == sourceId }),
              let tgtIdx = timelines.firstIndex(where: { $0.id == targetId }),
              srcIdx != tgtIdx else { return false }

        let source = timelines[srcIdx]
        timelines[tgtIdx].events.append(contentsOf: source.events)
        timelines[tgtIdx].keywords = Array(Set(timelines[tgtIdx].keywords + source.keywords).prefix(20))
        timelines[tgtIdx].lastUpdated = Date()

        timelines[srcIdx].status = .converged
        timelines.remove(at: srcIdx)

        return true
    }

    // MARK: - Report

    /// Generate a full analysis report.
    func generateReport() -> TimelineReport {
        let gaps = detectGaps()
        let patterns = detectFrequencyPatterns()
        let convergences = detectConvergences()
        let recommendations = generateRecommendations()

        let summaries = timelines.map { tl in
            TimelineSummary(
                timelineId: tl.id, name: tl.name,
                eventCount: tl.events.count,
                sourceCount: tl.sourceCount,
                spanDays: tl.span.map { $0 / 86400.0 },
                averageCadenceDays: tl.averageCadenceDays,
                status: tl.status,
                latestEventDate: tl.events.map({ $0.eventDate }).max()
            )
        }

        return TimelineReport(
            generatedDate: Date(),
            totalTimelines: timelines.count,
            totalEvents: timelines.reduce(0) { $0 + $1.events.count },
            activeTimelines: timelines.filter({ $0.status == .active }).count,
            stalledTimelines: timelines.filter({ $0.status == .stalled }).count,
            gaps: gaps, patterns: patterns,
            convergences: convergences,
            recommendations: recommendations,
            timelineSummaries: summaries
        )
    }

    // MARK: - Auto-Monitor

    /// Start autonomous monitoring — periodically analyze and surface insights.
    func startMonitoring(intervalSeconds: TimeInterval = 300,
                         onInsight: @escaping (TimelineRecommendation) -> Void) {
        stopMonitoring()
        monitorTimer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let recs = self.generateRecommendations()
            for rec in recs where rec.priority == .high {
                onInsight(rec)
            }
        }
    }

    /// Stop auto-monitoring.
    func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    // MARK: - Export

    /// Export a timeline as JSON.
    func exportJSON(timelineId: String? = nil) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let id = timelineId {
            guard let tl = timelines.first(where: { $0.id == id }) else { return nil }
            return (try? encoder.encode(tl)).flatMap { String(data: $0, encoding: .utf8) }
        }
        return (try? encoder.encode(timelines)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Export a timeline as Markdown.
    func exportMarkdown(timelineId: String? = nil) -> String {
        let targets = timelineId.flatMap { id in timelines.filter { $0.id == id } } ?? timelines
        var md = "# Feed Timeline Report\n\n"
        md += "Generated: \(ISO8601DateFormatter().string(from: Date()))\n\n"

        let formatter = DateFormatter()
        formatter.dateStyle = .medium

        for tl in targets {
            md += "## \(tl.name)\n\n"
            md += "Status: **\(tl.status.rawValue)** | Events: \(tl.events.count) | Sources: \(tl.sourceCount)\n\n"

            let sorted = tl.events.sorted { $0.eventDate < $1.eventDate }
            for event in sorted {
                let dateStr = formatter.string(from: event.eventDate)
                let conf = Int(event.confidence * 100)
                md += "- **\(dateStr)** [\(event.eventType.rawValue)] \(event.title)\n"
                md += "  > \(event.description.prefix(150))\n"
                md += "  _Source: \(event.sourceFeed) | Confidence: \(conf)%_\n\n"
            }
        }

        return md
    }

    /// Export as plain text.
    func exportText(timelineId: String? = nil) -> String {
        let targets = timelineId.flatMap { id in timelines.filter { $0.id == id } } ?? timelines
        var txt = "FEED TIMELINE REPORT\n"
        txt += String(repeating: "=", count: 60) + "\n\n"

        let formatter = DateFormatter()
        formatter.dateStyle = .medium

        for tl in targets {
            txt += "\(tl.name.uppercased())\n"
            txt += "Status: \(tl.status.rawValue) | Events: \(tl.events.count) | Sources: \(tl.sourceCount)\n"
            txt += String(repeating: "-", count: 40) + "\n"

            let sorted = tl.events.sorted { $0.eventDate < $1.eventDate }
            for event in sorted {
                txt += "  \(formatter.string(from: event.eventDate)) [\(event.eventType.rawValue)]\n"
                txt += "    \(event.title)\n"
                txt += "    \(event.description.prefix(120))\n"
                txt += "    Source: \(event.sourceFeed)\n\n"
            }
            txt += "\n"
        }

        return txt
    }

    // MARK: - Reset

    /// Clear all timelines and events.
    func reset() {
        timelines.removeAll()
        stopMonitoring()
    }
}
