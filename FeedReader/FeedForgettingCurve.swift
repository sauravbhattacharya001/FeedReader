//
//  FeedForgettingCurve.swift
//  FeedReader
//
//  Autonomous memory retention system based on the Ebbinghaus forgetting
//  curve. Models each read article as a "memory trace" that decays over
//  time using R = e^(-t/S). When retention drops below a threshold the
//  system suggests timely refreshers so the user retains key knowledge.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    static let forgettingCurveDidChange = Notification.Name("ForgettingCurveDidChangeNotification")
    static let memoryRefresherNeeded = Notification.Name("MemoryRefresherNeededNotification")
}

// MARK: - RefresherUrgency

/// How urgently a memory trace needs refreshing.
enum RefresherUrgency: Int, Codable, Comparable {
    case stable = 0      // retention > 0.6
    case weakening = 1   // 0.4 ..< 0.6
    case fading = 2      // 0.2 ..< 0.4
    case critical = 3    // < 0.2

    static func < (lhs: RefresherUrgency, rhs: RefresherUrgency) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func from(retention: Double) -> RefresherUrgency {
        switch retention {
        case ..<0.2:       return .critical
        case 0.2..<0.4:    return .fading
        case 0.4..<0.6:    return .weakening
        default:           return .stable
        }
    }

    var label: String {
        switch self {
        case .critical:   return "Critical"
        case .fading:     return "Fading"
        case .weakening:  return "Weakening"
        case .stable:     return "Stable"
        }
    }
}

// MARK: - MemoryTrace

/// A single article's memory state that decays over time.
class MemoryTrace: Codable, Equatable {
    let id: String
    let articleLink: String
    let articleTitle: String
    let feedTitle: String
    var topics: [String]
    let firstReadDate: Date
    var lastReviewDate: Date
    var reviewCount: Int
    var stability: Double
    var difficulty: Double

    init(articleLink: String, articleTitle: String, feedTitle: String,
         topics: [String], difficulty: Double) {
        self.id = UUID().uuidString
        self.articleLink = articleLink
        self.articleTitle = articleTitle
        self.feedTitle = feedTitle
        self.topics = topics
        self.firstReadDate = Date()
        self.lastReviewDate = Date()
        self.reviewCount = 1
        self.stability = 1.0
        self.difficulty = min(max(difficulty, 0), 1)
    }

    static func == (lhs: MemoryTrace, rhs: MemoryTrace) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: Forgetting Curve Math

    /// Retention at a given date: R = e^(-t / S)
    /// where t = days since last review, S = stability in days.
    func retentionAt(_ date: Date) -> Double {
        let daysSinceReview = date.timeIntervalSince(lastReviewDate) / 86400.0
        guard daysSinceReview >= 0 else { return 1.0 }
        // Adjust stability by difficulty: harder articles decay faster.
        let effectiveStability = stability * (1.0 - 0.5 * difficulty)
        guard effectiveStability > 0 else { return 0.0 }
        return exp(-daysSinceReview / effectiveStability)
    }

    /// Predicted date when retention drops below the given threshold.
    func predictedForgetDate(threshold: Double = 0.3) -> Date {
        let clampedThreshold = min(max(threshold, 0.01), 0.99)
        let effectiveStability = stability * (1.0 - 0.5 * difficulty)
        guard effectiveStability > 0 else { return lastReviewDate }
        // R = e^(-t/S) → t = -S * ln(R)
        let daysUntilForget = -effectiveStability * log(clampedThreshold)
        return lastReviewDate.addingTimeInterval(daysUntilForget * 86400.0)
    }

    /// Record a review: bump count, increase stability, update date.
    func recordReview() {
        reviewCount += 1
        lastReviewDate = Date()
        // Each review doubles stability (diminishing returns after many reviews).
        stability = min(stability * 2.0, 365.0)
    }
}

// MARK: - TopicMemory

/// Aggregated memory state for a single topic across articles.
struct TopicMemory: Codable {
    let topic: String
    var traceIds: [String]
    var averageRetention: Double
    var articlesRead: Int
    var strongestTraceId: String?
    var weakestTraceId: String?
}

// MARK: - RefresherSuggestion

/// A suggestion to re-read an article whose memory is fading.
struct RefresherSuggestion {
    let trace: MemoryTrace
    let currentRetention: Double
    let urgency: RefresherUrgency
    let reason: String
}

// MARK: - ForgettingStatistics

/// Summary statistics for the user's memory state.
struct ForgettingStatistics: Codable {
    let totalTraces: Int
    let averageRetention: Double
    let criticalCount: Int
    let fadingCount: Int
    let weakenCount: Int
    let stableCount: Int
    let topicCount: Int
    let strongestTopic: String?
    let weakestTopic: String?
    let predictedLossIn7Days: Int
    let reviewsNeededToday: Int
}

// MARK: - Stopwords

private let stopwords: Set<String> = [
    "a","about","above","after","again","against","all","also","am","an",
    "and","any","are","aren","as","at","be","because","been","before",
    "being","below","between","both","but","by","can","could","did","do",
    "does","doing","down","during","each","even","few","for","from","further",
    "get","got","had","has","have","having","he","her","here","hers",
    "herself","him","himself","his","how","however","i","if","in","into",
    "is","it","its","itself","just","let","like","may","me","might",
    "more","most","must","my","myself","new","no","nor","not","now",
    "of","off","on","once","only","or","other","our","ours","ourselves",
    "out","over","own","really","said","same","say","she","should","so",
    "some","still","such","take","than","that","the","their","theirs","them",
    "themselves","then","there","these","they","this","those","through","to","too",
    "under","until","up","upon","us","use","very","want","was","we",
    "well","were","what","when","where","which","while","who","whom","why",
    "will","with","won","would","you","your","yours","yourself","yourselves"
]

// MARK: - FeedForgettingCurve

/// Autonomous memory retention manager using the Ebbinghaus forgetting curve.
/// Tracks how well the user retains knowledge from articles and suggests
/// timely refreshers when memories fade.
class FeedForgettingCurve {
    static let shared = FeedForgettingCurve()

    private static let storageKey = "feedForgettingCurveData"
    private static let autoMonitorKey = "feedForgettingCurveAutoMonitor"
    private static let defaultThreshold: Double = 0.3

    private(set) var traces: [MemoryTrace] = []

    /// When enabled the auto-monitor will post notifications for critical traces.
    var autoMonitorEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: FeedForgettingCurve.autoMonitorKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: FeedForgettingCurve.autoMonitorKey)
        }
    }

    // MARK: Init

    private init() {
        load()
    }

    // MARK: Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: FeedForgettingCurve.storageKey) else { return }
        do {
            traces = try JSONDecoder().decode([MemoryTrace].self, from: data)
        } catch {
            traces = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(traces)
            UserDefaults.standard.set(data, forKey: FeedForgettingCurve.storageKey)
            NotificationCenter.default.post(name: .forgettingCurveDidChange, object: self)
        } catch {
            // Silent fail — data will be retried next save.
        }
    }

    // MARK: - Recording

    /// Record that the user read an article. Creates or updates a memory trace.
    @discardableResult
    func recordReading(link: String, title: String, feedTitle: String, content: String) -> MemoryTrace {
        if let existing = traces.first(where: { $0.articleLink == link }) {
            existing.recordReview()
            save()
            return existing
        }
        let topics = extractTopics(from: content)
        let difficulty = estimateDifficulty(content: content)
        let trace = MemoryTrace(articleLink: link, articleTitle: title,
                                feedTitle: feedTitle, topics: topics, difficulty: difficulty)
        traces.append(trace)
        save()
        return trace
    }

    /// Record a deliberate review of a previously read article.
    func recordReview(traceId: String) {
        guard let trace = traces.first(where: { $0.id == traceId }) else { return }
        trace.recordReview()
        save()
    }

    // MARK: - Retention Queries

    /// Current retention for a specific trace.
    func retention(for traceId: String) -> Double {
        guard let trace = traces.first(where: { $0.id == traceId }) else { return 0.0 }
        return trace.retentionAt(Date())
    }

    /// All traces with their current retention, sorted lowest-first.
    func allRetentions() -> [(trace: MemoryTrace, retention: Double)] {
        let now = Date()
        return traces
            .map { ($0, $0.retentionAt(now)) }
            .sorted { $0.1 < $1.1 }
    }

    // MARK: - Refresher Suggestions

    /// Get traces that need refreshing, sorted by urgency (most urgent first).
    func refresherSuggestions(limit: Int = 10,
                              threshold: Double = FeedForgettingCurve.defaultThreshold) -> [RefresherSuggestion] {
        let now = Date()
        return traces
            .compactMap { trace -> RefresherSuggestion? in
                let r = trace.retentionAt(now)
                guard r < threshold else { return nil }
                let urgency = RefresherUrgency.from(retention: r)
                let pct = Int(r * 100)
                let reason: String
                switch urgency {
                case .critical:
                    reason = "Memory nearly gone (\(pct)% retention). Re-read soon to save this knowledge."
                case .fading:
                    reason = "Fading fast (\(pct)% retention). A quick review will strengthen this memory."
                case .weakening:
                    reason = "Starting to weaken (\(pct)% retention). Good time for a refresher."
                case .stable:
                    reason = "Still okay (\(pct)% retention)."
                }
                return RefresherSuggestion(trace: trace, currentRetention: r,
                                           urgency: urgency, reason: reason)
            }
            .sorted { $0.urgency > $1.urgency }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Topic Analysis

    /// Aggregate memory state per topic.
    func topicMemories() -> [TopicMemory] {
        let now = Date()
        var topicMap: [String: (ids: [String], retentions: [(String, Double)])] = [:]
        for trace in traces {
            let r = trace.retentionAt(now)
            for topic in trace.topics {
                var entry = topicMap[topic] ?? (ids: [], retentions: [])
                entry.ids.append(trace.id)
                entry.retentions.append((trace.id, r))
                topicMap[topic] = entry
            }
        }
        return topicMap.map { topic, data in
            let avgR = data.retentions.isEmpty ? 0 : data.retentions.map(\.1).reduce(0, +) / Double(data.retentions.count)
            let strongest = data.retentions.max(by: { $0.1 < $1.1 })?.0
            let weakest = data.retentions.min(by: { $0.1 < $1.1 })?.0
            return TopicMemory(topic: topic, traceIds: data.ids,
                               averageRetention: avgR, articlesRead: data.ids.count,
                               strongestTraceId: strongest, weakestTraceId: weakest)
        }.sorted { $0.averageRetention < $1.averageRetention }
    }

    /// Topics whose average retention is below threshold.
    func fadingTopics(threshold: Double = FeedForgettingCurve.defaultThreshold) -> [TopicMemory] {
        topicMemories().filter { $0.averageRetention < threshold }
    }

    // MARK: - Overall Metrics

    /// Overall memory strength as average retention across all traces.
    func memoryStrength() -> Double {
        guard !traces.isEmpty else { return 1.0 }
        let now = Date()
        let total = traces.reduce(0.0) { $0 + $1.retentionAt(now) }
        return total / Double(traces.count)
    }

    /// Project overall retention over the next N days.
    func forgettingForecast(days: Int = 30) -> [(day: Int, predictedRetention: Double)] {
        guard !traces.isEmpty else { return [] }
        let now = Date()
        return (0...days).map { d in
            let future = now.addingTimeInterval(Double(d) * 86400.0)
            let avg = traces.reduce(0.0) { $0 + $1.retentionAt(future) } / Double(traces.count)
            return (day: d, predictedRetention: avg)
        }
    }

    // MARK: - Auto Monitor

    /// Run the autonomous monitor. Returns critical suggestions and posts a
    /// notification if any memories need urgent refreshing.
    func runAutoMonitor() -> [RefresherSuggestion] {
        let critical = refresherSuggestions(limit: 20, threshold: 0.4)
            .filter { $0.urgency >= .fading }
        if !critical.isEmpty {
            NotificationCenter.default.post(
                name: .memoryRefresherNeeded,
                object: self,
                userInfo: ["suggestions": critical]
            )
        }
        return critical
    }

    // MARK: - Statistics

    /// Comprehensive statistics about memory state.
    func statistics() -> ForgettingStatistics {
        let now = Date()
        let retentions = traces.map { $0.retentionAt(now) }
        let avg = retentions.isEmpty ? 1.0 : retentions.reduce(0, +) / Double(retentions.count)

        let criticalCount = retentions.filter { $0 < 0.2 }.count
        let fadingCount = retentions.filter { $0 >= 0.2 && $0 < 0.4 }.count
        let weakenCount = retentions.filter { $0 >= 0.4 && $0 < 0.6 }.count
        let stableCount = retentions.filter { $0 >= 0.6 }.count

        let topics = topicMemories()
        let strongest = topics.last?.topic
        let weakest = topics.first?.topic

        // Predict how many traces will go critical in 7 days
        let future7 = now.addingTimeInterval(7 * 86400)
        let lossIn7 = traces.filter { trace in
            trace.retentionAt(now) >= 0.2 && trace.retentionAt(future7) < 0.2
        }.count

        // Reviews needed today: traces below threshold
        let reviewsNeeded = retentions.filter { $0 < FeedForgettingCurve.defaultThreshold }.count

        return ForgettingStatistics(
            totalTraces: traces.count,
            averageRetention: avg,
            criticalCount: criticalCount,
            fadingCount: fadingCount,
            weakenCount: weakenCount,
            stableCount: stableCount,
            topicCount: topics.count,
            strongestTopic: strongest,
            weakestTopic: weakest,
            predictedLossIn7Days: lossIn7,
            reviewsNeededToday: reviewsNeeded
        )
    }

    // MARK: - Import / Export

    /// Export all traces as a JSON string.
    func exportJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(traces),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    /// Import traces from a JSON string. Returns true on success.
    @discardableResult
    func importJSON(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8) else { return false }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let imported = try? decoder.decode([MemoryTrace].self, from: data) else { return false }
        // Merge: skip duplicates by articleLink.
        let existingLinks = Set(traces.map(\.articleLink))
        let newTraces = imported.filter { !existingLinks.contains($0.articleLink) }
        traces.append(contentsOf: newTraces)
        save()
        return true
    }

    // MARK: - Removal

    /// Remove a trace by ID.
    func removeTrace(id: String) {
        traces.removeAll { $0.id == id }
        save()
    }

    /// Remove all traces.
    func removeAll() {
        traces.removeAll()
        save()
    }

    // MARK: - Private Helpers

    /// Extract top keywords from content as topic labels.
    private func extractTopics(from content: String, count: Int = 5) -> [String] {
        let words = content.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 && !stopwords.contains($0) }
        var freq: [String: Int] = [:]
        for w in words { freq[w, default: 0] += 1 }
        return freq.sorted { $0.value > $1.value }
            .prefix(count)
            .map(\.key)
    }

    /// Estimate article difficulty from content (0-1).
    /// Uses average word length and average sentence length as proxies.
    private func estimateDifficulty(content: String) -> Double {
        let words = content.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return 0.5 }
        let avgWordLen = Double(words.reduce(0) { $0 + $1.count }) / Double(words.count)
        let sentences = content.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let avgSentenceLen = sentences.isEmpty ? 15.0 : Double(words.count) / Double(sentences.count)

        // Normalize: avgWordLen ~4-8 maps to 0-0.5, avgSentenceLen ~10-30 maps to 0-0.5
        let wordScore = min(max((avgWordLen - 4.0) / 8.0, 0), 0.5)
        let sentScore = min(max((avgSentenceLen - 10.0) / 40.0, 0), 0.5)
        return min(wordScore + sentScore, 1.0)
    }
}
