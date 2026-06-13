import Foundation

/// A coarse classification of how fast an article was read, derived from words
/// per minute (WPM).
///
/// Buckets are defined by `lowerBound` and assigned by `classify(_:)`:
/// `deepReading` < 100 ≤ `slow` < 200 ≤ `normal` < 350 ≤ `fast` < 600 ≤ `skimming`.
/// `Comparable` orders the cases from slowest (`deepReading`) to fastest
/// (`skimming`), so `min`/`max`/`sorted` reflect reading speed rather than the
/// declaration order.
public enum ReadingPace: String, CaseIterable, Sendable, Comparable {
    case skimming = "skimming"; case fast = "fast"; case normal = "normal"
    case slow = "slow"; case deepReading = "deep_reading"
    /// Human-readable name suitable for display in a UI.
    public var label: String {
        switch self { case .skimming: return "Skimming"; case .fast: return "Fast Reading"
        case .normal: return "Normal Pace"; case .slow: return "Slow / Careful"
        case .deepReading: return "Deep Reading" }
    }
    /// The inclusive lower WPM bound of this bucket. A reader at exactly this
    /// many words per minute is classified as this pace (see `classify(_:)`).
    public var lowerBound: Double {
        switch self { case .skimming: return 600; case .fast: return 350
        case .normal: return 200; case .slow: return 100; case .deepReading: return 0 }
    }
    /// Slow-to-fast ordinal used only to back `Comparable`; not part of the API.
    private var sortOrder: Int {
        switch self { case .deepReading: return 0; case .slow: return 1
        case .normal: return 2; case .fast: return 3; case .skimming: return 4 }
    }
    public static func < (lhs: ReadingPace, rhs: ReadingPace) -> Bool { lhs.sortOrder < rhs.sortOrder }
    /// Maps a raw words-per-minute value to its pace bucket. Values are matched
    /// against descending thresholds, so any non-negative WPM resolves to
    /// exactly one case (0 WPM → `deepReading`).
    public static func classify(_ wpm: Double) -> ReadingPace {
        if wpm >= 600 { return .skimming }; if wpm >= 350 { return .fast }
        if wpm >= 200 { return .normal }; if wpm >= 100 { return .slow }; return .deepReading
    }
}

/// A single observed reading event: one article read once, with the time spent
/// on it. This is the raw input unit consumed by `FeedReadingPaceAnalyzer`.
public struct PaceSession: Sendable {
    public let articleId: String; public let feedName: String; public let topic: String
    public let wordCount: Int; public let readingSeconds: Double; public let readAt: Date
    /// Creates a reading session.
    /// - Parameters:
    ///   - articleId: Stable identifier of the article that was read.
    ///   - feedName: Name of the feed/source the article came from.
    ///   - topic: Topic label used to group sessions for per-topic profiles.
    ///   - wordCount: Number of words in the article body.
    ///   - readingSeconds: Wall-clock seconds the reader spent on the article.
    ///   - readAt: When the article was read (used for trend windows).
    public init(articleId: String, feedName: String, topic: String,
                wordCount: Int, readingSeconds: Double, readAt: Date) {
        self.articleId = articleId; self.feedName = feedName; self.topic = topic
        self.wordCount = wordCount; self.readingSeconds = readingSeconds; self.readAt = readAt
    }
    /// Effective reading speed in words per minute. Returns `0` when the word
    /// count or reading time is non-positive, which is how the analyzer filters
    /// out unusable sessions.
    public var wpm: Double {
        guard readingSeconds > 0, wordCount > 0 else { return 0 }
        return Double(wordCount) / (readingSeconds / 60.0)
    }
    /// The pace bucket this session falls into, derived from `wpm`.
    public var pace: ReadingPace { ReadingPace.classify(wpm) }
}

/// A detected irregularity in reading behaviour, such as rushing a long
/// article or a sustained slowdown across a session. Produced by the analyzer
/// and surfaced in `PaceReport.anomalies`.
public struct PaceAnomaly: Sendable {
    /// The category of irregularity that was detected.
    public enum Kind: String, CaseIterable, Sendable {
        case rushingLongContent = "rushing_long_content"
        case dwellingShortContent = "dwelling_short_content"
        case paceSpike = "pace_spike"; case paceDrop = "pace_drop"
        case fatiguePattern = "fatigue_pattern"; case topicStruggle = "topic_struggle"
    }
    /// Bucketed severity, derived from `severityScore` (see `init`).
    public enum Severity: String, Sendable { case low = "low"; case medium = "medium"; case high = "high" }
    public let kind: Kind; public let severity: Severity; public let severityScore: Int
    public let articleId: String?; public let topic: String?
    public let feedName: String?; public let detail: String
    /// Creates an anomaly.
    ///
    /// `severityScore` is clamped to `0...100`, then mapped to `severity`:
    /// `0...33` → `.low`, `34...66` → `.medium`, `67...100` → `.high`.
    /// - Parameters:
    ///   - kind: What kind of irregularity this is.
    ///   - severityScore: Raw 0–100 score; out-of-range values are clamped.
    ///   - articleId: Article the anomaly relates to, if session-specific.
    ///   - topic: Topic the anomaly relates to, if topic-specific.
    ///   - feedName: Feed the anomaly relates to, if feed-specific.
    ///   - detail: Human-readable explanation of the finding.
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

/// Aggregate reading statistics for one grouping key (a single topic or a
/// single feed). Profiles are only built once a group has enough sessions to be
/// meaningful, so a sparsely-read topic will not appear.
public struct PaceProfile: Sendable {
    /// The topic or feed name this profile summarises.
    public let name: String; public let sessionCount: Int
    public let averageWPM: Double; public let medianWPM: Double
    public let fastestWPM: Double; public let slowestWPM: Double
    /// Pace bucket implied by the group's median WPM.
    public let dominantPace: ReadingPace
    public let totalWordsRead: Int; public let totalSeconds: Double
    /// Creates a profile. All WPM figures are expected to be pre-rounded by the
    /// caller; this initializer only stores the values.
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

/// A predicted time-to-read for an article, returned by
/// `FeedReadingPaceAnalyzer.estimateReadingTime(...)`.
public struct ReadingTimeEstimate: Sendable {
    public let estimatedMinutes: Double; public let estimatedWPM: Double
    /// Confidence in the estimate, `0...1`. Higher when more of the reader's own
    /// history backs the figure; lowest for the library default fallback.
    public let confidence: Double
    /// Where the estimate came from: `"topic"`, `"feed"`, `"global"`, or
    /// `"default"` (the built-in average when no history is available).
    public let source: String
    /// Creates a reading-time estimate.
    public init(estimatedMinutes: Double, estimatedWPM: Double, confidence: Double, source: String) {
        self.estimatedMinutes = estimatedMinutes; self.estimatedWPM = estimatedWPM
        self.confidence = confidence; self.source = source
    }
}

/// An actionable suggestion for the reader (for example "take reading breaks"
/// after a fatigue pattern is detected). Recommendations are de-duplicated by
/// `id` and surfaced sorted by `priority` in `PaceReport.recommendations`.
public struct PaceRecommendation: Sendable {
    /// Relative importance, `p0` (most urgent) through `p3` (informational).
    /// `Comparable` orders `p0 < p1 < p2 < p3` so ascending sorts put the most
    /// urgent recommendation first.
    public enum Priority: String, CaseIterable, Sendable, Comparable {
        case p0 = "P0"; case p1 = "P1"; case p2 = "P2"; case p3 = "P3"
        private var sortOrder: Int { switch self { case .p0: return 0; case .p1: return 1; case .p2: return 2; case .p3: return 3 } }
        public static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.sortOrder < rhs.sortOrder }
    }
    /// Stable identifier used to de-duplicate recommendations within a report.
    public let id: String; public let priority: Priority; public let label: String
    public let reason: String; public let relatedTopics: [String]
    /// Creates a recommendation.
    /// - Parameters:
    ///   - id: Stable de-duplication key (e.g. `"take_reading_breaks"`).
    ///   - priority: How urgent the suggestion is.
    ///   - label: Short title shown to the reader.
    ///   - reason: One-line justification for the suggestion.
    ///   - relatedTopics: Topics this recommendation refers to, if any.
    public init(id: String, priority: Priority, label: String, reason: String, relatedTopics: [String] = []) {
        self.id = id; self.priority = priority; self.label = label
        self.reason = reason; self.relatedTopics = relatedTopics
    }
}

/// How the reader's pace changed over a recent time window relative to the
/// preceding window of equal length. Emitted per window in `PaceReport.trends`.
public struct PaceTrend: Sendable {
    /// Whether pace went up, held steady, or went down. The analyzer treats a
    /// change of more than ±10% as `improving`/`declining`; otherwise `stable`.
    public enum Direction: String, Sendable { case improving = "improving"; case stable = "stable"; case declining = "declining" }
    /// Identifier of the window, e.g. `"last_7_days"` or `"last_30_days"`.
    public let window: String; public let sessionCount: Int
    /// Average WPM in the window.
    public let averageWPM: Double
    /// Percent change versus the immediately preceding window of equal length;
    /// `0` when there is no prior data to compare against.
    public let changePercent: Double; public let direction: Direction
    /// Creates a trend entry for a single window.
    public init(window: String, sessionCount: Int, averageWPM: Double, changePercent: Double, direction: Direction) {
        self.window = window; self.sessionCount = sessionCount
        self.averageWPM = averageWPM; self.changePercent = changePercent; self.direction = direction
    }
}

/// The complete reading-pace analysis for a set of sessions, returned by
/// `FeedReadingPaceAnalyzer.analyze(sessions:)`.
///
/// Bundles the headline figures (overall/median WPM, dominant pace, letter
/// `paceGrade`), the per-topic and per-feed `PaceProfile`s, recent `PaceTrend`s,
/// detected `PaceAnomaly`s (sorted most-severe first), prioritised
/// `PaceRecommendation`s, and a set of short machine-readable `insights` tags.
public struct PaceReport: Sendable {
    public let totalSessions: Int; public let overallWPM: Double; public let medianWPM: Double
    public let dominantPace: ReadingPace; public let paceDistribution: [ReadingPace: Int]
    public let totalWordsRead: Int; public let totalReadingSeconds: Double
    public let trends: [PaceTrend]; public let topicProfiles: [PaceProfile]
    public let feedProfiles: [PaceProfile]; public let anomalies: [PaceAnomaly]
    public let recommendations: [PaceRecommendation]
    /// Overall letter grade, `"A"` (healthiest) through `"F"`.
    public let paceGrade: String
    /// One-line summary suitable for a header, e.g.
    /// `"Grade A: 238 WPM (Normal Pace)"`.
    public let headline: String
    /// Short, sorted, machine-readable insight tags (e.g. `"pace_declining_last_7_days"`).
    public let insights: [String]
}
