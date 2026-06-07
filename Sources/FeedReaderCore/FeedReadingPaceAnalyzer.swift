import Foundation
public enum ReadingPace: String, CaseIterable, Sendable, Comparable {
    case skimming = "skimming"; case fast = "fast"; case normal = "normal"
    case slow = "slow"; case deepReading = "deep_reading"
    public var label: String {
        switch self { case .skimming: return "Skimming"; case .fast: return "Fast Reading"
        case .normal: return "Normal Pace"; case .slow: return "Slow / Careful"
        case .deepReading: return "Deep Reading" }
    }
    public var lowerBound: Double {
        switch self { case .skimming: return 600; case .fast: return 350
        case .normal: return 200; case .slow: return 100; case .deepReading: return 0 }
    }
    private var sortOrder: Int {
        switch self { case .deepReading: return 0; case .slow: return 1
        case .normal: return 2; case .fast: return 3; case .skimming: return 4 }
    }
    public static func < (lhs: ReadingPace, rhs: ReadingPace) -> Bool { lhs.sortOrder < rhs.sortOrder }
    public static func classify(_ wpm: Double) -> ReadingPace {
        if wpm >= 600 { return .skimming }; if wpm >= 350 { return .fast }
        if wpm >= 200 { return .normal }; if wpm >= 100 { return .slow }; return .deepReading
    }
}
public struct PaceSession: Sendable {
    public let articleId: String; public let feedName: String; public let topic: String
    public let wordCount: Int; public let readingSeconds: Double; public let readAt: Date
    public init(articleId: String, feedName: String, topic: String,
                wordCount: Int, readingSeconds: Double, readAt: Date) {
        self.articleId = articleId; self.feedName = feedName; self.topic = topic
        self.wordCount = wordCount; self.readingSeconds = readingSeconds; self.readAt = readAt
    }
    public var wpm: Double {
        guard readingSeconds > 0, wordCount > 0 else { return 0 }
        return Double(wordCount) / (readingSeconds / 60.0)
    }
    public var pace: ReadingPace { ReadingPace.classify(wpm) }
}
public struct PaceAnomaly: Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case rushingLongContent = "rushing_long_content"
        case dwellingShortContent = "dwelling_short_content"
        case paceSpike = "pace_spike"; case paceDrop = "pace_drop"
        case fatiguePattern = "fatigue_pattern"; case topicStruggle = "topic_struggle"
    }
    public enum Severity: String, Sendable { case low = "low"; case medium = "medium"; case high = "high" }
    public let kind: Kind; public let severity: Severity; public let severityScore: Int
    public let articleId: String?; public let topic: String?
    public let feedName: String?; public let detail: String
    public init(kind: Kind, severityScore: Int, articleId: String? = nil,
                topic: String? = nil, feedName: String? = nil, detail: String) {
        self.kind = kind; self.severityScore = max(0, min(100, severityScore))
        if self.severityScore <= 33 { self.severity = .low }
        else if self.severityScore <= 66 { self.severity = .medium }
        else { self.severity = .high }
        self.articleId = articleId; self.topic = topic
        self.feedName = feedName; self.detail = detail
    }
}
public struct PaceProfile: Sendable {
    public let name: String; public let sessionCount: Int
    public let averageWPM: Double; public let medianWPM: Double
    public let fastestWPM: Double; public let slowestWPM: Double
    public let dominantPace: ReadingPace
    public let totalWordsRead: Int; public let totalSeconds: Double
    public init(name: String, sessionCount: Int, averageWPM: Double, medianWPM: Double,
                fastestWPM: Double, slowestWPM: Double, dominantPace: ReadingPace,
                totalWordsRead: Int, totalSeconds: Double) {
        self.name = name; self.sessionCount = sessionCount
        self.averageWPM = averageWPM; self.medianWPM = medianWPM
        self.fastestWPM = fastestWPM; self.slowestWPM = slowestWPM
        self.dominantPace = dominantPace; self.totalWordsRead = totalWordsRead
        self.totalSeconds = totalSeconds
    }
}
public struct ReadingTimeEstimate: Sendable {
    public let estimatedMinutes: Double; public let estimatedWPM: Double
    public let confidence: Double; public let source: String
    public init(estimatedMinutes: Double, estimatedWPM: Double, confidence: Double, source: String) {
        self.estimatedMinutes = estimatedMinutes; self.estimatedWPM = estimatedWPM
        self.confidence = confidence; self.source = source
    }
}
public struct PaceRecommendation: Sendable {
    public enum Priority: String, CaseIterable, Sendable, Comparable {
        case p0 = "P0"; case p1 = "P1"; case p2 = "P2"; case p3 = "P3"
        private var sortOrder: Int { switch self { case .p0: return 0; case .p1: return 1; case .p2: return 2; case .p3: return 3 } }
        public static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.sortOrder < rhs.sortOrder }
    }
    public let id: String; public let priority: Priority; public let label: String
    public let reason: String; public let relatedTopics: [String]
    public init(id: String, priority: Priority, label: String, reason: String, relatedTopics: [String] = []) {
        self.id = id; self.priority = priority; self.label = label
        self.reason = reason; self.relatedTopics = relatedTopics
    }
}
public struct PaceTrend: Sendable {
    public enum Direction: String, Sendable { case improving = "improving"; case stable = "stable"; case declining = "declining" }
    public let window: String; public let sessionCount: Int
    public let averageWPM: Double; public let changePercent: Double; public let direction: Direction
    public init(window: String, sessionCount: Int, averageWPM: Double, changePercent: Double, direction: Direction) {
        self.window = window; self.sessionCount = sessionCount
        self.averageWPM = averageWPM; self.changePercent = changePercent; self.direction = direction
    }
}
public struct PaceReport: Sendable {
    public let totalSessions: Int; public let overallWPM: Double; public let medianWPM: Double
    public let dominantPace: ReadingPace; public let paceDistribution: [ReadingPace: Int]
    public let totalWordsRead: Int; public let totalReadingSeconds: Double
    public let trends: [PaceTrend]; public let topicProfiles: [PaceProfile]
    public let feedProfiles: [PaceProfile]; public let anomalies: [PaceAnomaly]
    public let recommendations: [PaceRecommendation]
    public let paceGrade: String; public let headline: String; public let insights: [String]
}
