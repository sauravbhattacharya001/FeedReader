//
//  FeedNarrativeArcTracker.swift
//  FeedReaderCore
//
//  Autonomous narrative arc tracker that detects developing storylines
//  across articles over time. Identifies when stories are emerging, building
//  momentum, reaching climax, or resolving — and alerts users when stories
//  they're following reach key turning points.
//
//  Agentic capabilities:
//  - **Story Detection:** Clusters related articles into narrative threads
//  - **Arc Phase Classification:** Maps each story to a narrative phase
//    (Emerging → Rising → Climax → Falling → Resolution → Dormant)
//  - **Momentum Tracking:** Measures publication velocity and sentiment shifts
//  - **Turning Point Detection:** Alerts when stories hit inflection points
//  - **Story Following:** Users mark stories to follow; engine watches for updates
//  - **Narrative Forecasting:** Predicts likely next phase and time-to-resolution
//  - **Cross-Story Linking:** Detects when separate narratives converge
//  - **Health Scoring:** Composite narrative awareness score 0-100
//
//  Fully offline — no network, no dependencies beyond Foundation.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    static let narrativeTurningPointDetected = Notification.Name("NarrativeTurningPointDetectedNotification")
    static let narrativePhaseChanged = Notification.Name("NarrativePhaseChangedNotification")
    static let narrativeNewStoryEmerged = Notification.Name("NarrativeNewStoryEmergedNotification")
}

// MARK: - Narrative Phase

/// The phase of a storyline's narrative arc.
///
/// Phases form an ordered ladder via ``Comparable`` — `emerging < rising <
/// climax < falling < resolution < dormant` — so callers can do simple
/// inequality checks (e.g. `phase >= .climax`) to gate UI affordances such
/// as turning-point banners. Raw values are human-readable strings safe to
/// surface directly in UI.
public enum NarrativePhase: String, Codable, CaseIterable, Comparable {
    /// Few initial articles; the story has just been detected and is not
    /// yet confirmed as a sustained narrative.
    case emerging = "Emerging"
    /// Coverage volume and source diversity are growing — momentum is
    /// building toward a peak.
    case rising = "Rising"
    /// Story has reached peak coverage intensity and source breadth in
    /// the recent window.
    case climax = "Climax"
    /// Post-peak: coverage volume is declining but the story is still
    /// actively reported (aftermath / follow-ups).
    case falling = "Falling"
    /// Coverage has effectively wound down; the story is treated as
    /// concluded but is not yet dormant.
    case resolution = "Resolution"
    /// No activity for at least ``FeedNarrativeArcTracker.dormantDays``;
    /// the story is archived and excluded from active reports.
    case dormant = "Dormant"

    private var ordinal: Int {
        switch self {
        case .emerging: return 0
        case .rising: return 1
        case .climax: return 2
        case .falling: return 3
        case .resolution: return 4
        case .dormant: return 5
        }
    }

    public static func < (lhs: NarrativePhase, rhs: NarrativePhase) -> Bool {
        return lhs.ordinal < rhs.ordinal
    }
}

// MARK: - Turning Point Type

/// Types of turning points detected in narrative arcs.
///
/// Each case corresponds to a distinct heuristic in the tracker. UI layers
/// can switch on the case to pick an icon, banner copy, or notification
/// channel without re-deriving the reason from free text.
public enum TurningPointType: String, Codable, CaseIterable {
    /// First detection of a new story (mirrors ``Notification.Name/narrativeNewStoryEmerged``).
    case emergence
    /// Sudden jump in momentum since the previous ingest.
    case accelerating
    /// Story transitioned into the ``NarrativePhase/climax`` phase.
    case peakReached
    /// Rolling mean sentiment shifted significantly (positive or negative).
    case sentimentShift
    /// A previously unseen named entity entered an established story.
    case newActor
    /// Two distinct stories started overlapping on entities/keywords.
    case convergence
    /// Story direction reversed (reserved for future detectors).
    case reversal
    /// Story transitioned into the ``NarrativePhase/resolution`` phase.
    case resolution
}

// MARK: - Models

/// An article contributing to a narrative.
///
/// Articles are the atomic input to ``FeedNarrativeArcTracker``. Keywords
/// and entities are lower-cased at construction time so callers don't have
/// to normalize them, and `sentiment` is clamped into the documented range.
public struct NarrativeArticle: Sendable {
    /// Stable identifier (typically the article's GUID or canonical URL).
    /// Used to dedupe and to back-reference articles from ``NarrativeThread/articleIds``.
    public let id: String
    /// Human-readable headline; surfaced verbatim in reports.
    public let title: String
    /// Lowercased topical keywords used for Jaccard-based clustering.
    public let keywords: [String]
    /// Lowercased named entities (people, orgs, places). Weighted more
    /// heavily than keywords in the clustering similarity score.
    public let entities: [String]
    /// Feed origin (URL or display name). Drives source-diversity scoring.
    public let feedSource: String
    /// Publication date used for momentum, recency and dormancy windows.
    public let publishDate: Date
    /// Article sentiment in `[-1.0, 1.0]`. Values outside the range are
    /// clamped by the initializer.
    public let sentiment: Double
    /// Approximate word count. Negative values are coerced to `0`.
    public let wordCount: Int

    /// Create a new article record. `keywords` and `entities` are
    /// lower-cased, `sentiment` is clamped to `[-1.0, 1.0]`, and
    /// `wordCount` is floored at `0`.
    public init(id: String, title: String, keywords: [String], entities: [String],
                feedSource: String, publishDate: Date, sentiment: Double = 0.0,
                wordCount: Int = 500) {
        self.id = id
        self.title = title
        self.keywords = keywords.map { $0.lowercased() }
        self.entities = entities.map { $0.lowercased() }
        self.feedSource = feedSource
        self.publishDate = publishDate
        self.sentiment = max(-1.0, min(1.0, sentiment))
        self.wordCount = max(0, wordCount)
    }
}

/// A detected storyline / narrative thread.
///
/// Threads are immutable, point-in-time snapshots derived from internal
/// tracker state by ``FeedNarrativeArcTracker/analyze()`` and
/// ``FeedNarrativeArcTracker/getStories()``. Re-running analysis produces
/// fresh snapshots — do not cache long-term and expect them to mutate.
public struct NarrativeThread: Sendable {
    /// Tracker-assigned stable story identifier (e.g. `"story_42"`).
    public let id: String
    /// Human-readable story name auto-generated from top entity + keyword.
    public let label: String
    /// Up to ten defining keywords, snapshot at report time.
    public let coreKeywords: [String]
    /// Up to ten key entities involved, snapshot at report time.
    public let coreEntities: [String]
    /// IDs of every ``NarrativeArticle`` that has been clustered into this
    /// story, in ingest order.
    public let articleIds: [String]
    /// Publish date of the earliest article in the cluster.
    public let firstSeen: Date
    /// Publish date of the most recent article in the cluster.
    public let lastSeen: Date
    /// Current narrative phase (see ``NarrativePhase``).
    public let phase: NarrativePhase
    /// Composite momentum in `[0, 100]` combining publication frequency,
    /// recency and source diversity. Higher = more active.
    public let momentum: Double
    /// Difference between the late-window and early-window mean sentiment.
    /// Positive = trending positive, negative = trending negative, ~0 = flat.
    public let sentimentTrajectory: Double
    /// Number of unique feed sources covering this story.
    public let sourceCount: Int
    /// Whether the user has explicitly opted in to follow this story.
    public let isFollowed: Bool
}

/// A detected turning point in a narrative.
///
/// Turning points are append-only events emitted as articles are ingested
/// or phases recomputed. They are the primary signal surfaced to users
/// following a story ("the story just hit climax", "sentiment flipped
negative", etc.).
public struct NarrativeTurningPoint: Sendable {
    /// Story this turning point belongs to.
    public let storyId: String
    /// Category of turning point (see ``TurningPointType``).
    public let type: TurningPointType
    /// Wall-clock time the turning point was emitted (typically the
    /// triggering article's `publishDate`).
    public let detectedAt: Date
    /// Short human-readable description suitable for notification copy.
    public let description: String
    /// Significance score in `[0, 100]`; higher = more newsworthy.
    public let significance: Double
    /// Phase the story was in immediately before this turning point.
    public let beforePhase: NarrativePhase
    /// Phase the story moved into as a result of this turning point.
    /// Equal to `beforePhase` when the event did not cause a phase change.
    public let afterPhase: NarrativePhase
}

/// Cross-story convergence detection result.
///
/// Emitted when two otherwise-separate stories start sharing enough
/// entities (and, to a lesser degree, keywords) that they are likely
/// describing the same evolving situation from different angles.
public struct NarrativeConvergence: Sendable {
    /// First story in the pair. Pairs are ordered so that `storyIdA <
    /// storyIdB` is not guaranteed — treat as an unordered set.
    public let storyIdA: String
    /// Second story in the pair.
    public let storyIdB: String
    /// Entities present in the core sets of both stories.
    public let sharedEntities: [String]
    /// Keywords present in the core sets of both stories.
    public let sharedKeywords: [String]
    /// Convergence strength in `[0, 1]`; entity overlap is weighted 60%,
    /// keyword overlap 40%.
    public let convergenceStrength: Double
    /// `max(lastSeen)` of the two stories at the time of detection.
    public let detectedAt: Date
}

/// Forecast for a narrative's likely next phase.
///
/// Forecasts are produced only for non-dormant, non-resolved stories with
/// at least three contributing articles — call ``FeedNarrativeArcTracker/analyze()``
/// to refresh.
public struct NarrativeForecast: Sendable {
    /// Story this forecast applies to.
    public let storyId: String
    /// Phase the story is currently in at forecast time.
    public let currentPhase: NarrativePhase
    /// Phase the tracker expects the story to transition into next.
    public let predictedNextPhase: NarrativePhase
    /// Forecast confidence in `[0, 1]`; higher = stronger signal.
    public let confidence: Double
    /// Estimated days until the predicted phase transition occurs.
    public let estimatedDaysToTransition: Int
    /// Short natural-language explanation of the heuristic used.
    public let reasoning: String
}

/// Overall narrative awareness report.
///
/// Produced by ``FeedNarrativeArcTracker/analyze()``. The report is a
/// self-contained snapshot — it does not retain references to internal
/// tracker state and can be serialized or passed across threads freely.
public struct NarrativeReport: Sendable {
    /// All non-dormant stories, sorted by descending momentum.
    public let activeStories: [NarrativeThread]
    /// Up to twenty most recent turning points across all stories,
    /// newest first.
    public let recentTurningPoints: [NarrativeTurningPoint]
    /// Detected cross-story convergences, sorted by descending strength.
    public let convergences: [NarrativeConvergence]
    /// Forecasts for active, non-resolved stories with sufficient history.
    public let forecasts: [NarrativeForecast]
    /// User-followed stories, sorted by most recent activity.
    public let followedStoryUpdates: [NarrativeThread]
    /// Composite narrative-awareness score in `[0, 100]` combining phase
    /// diversity, active count, source breadth and follow engagement.
    public let healthScore: Double
    /// Plain-text insights highlighting climax stories, busy news cycles,
    /// convergences, multi-source confidence and followed turning points.
    public let insights: [String]
}

// MARK: - Internal State

private struct StoryState {
    var id: String
    var label: String
    var coreKeywords: Set<String>
    var coreEntities: Set<String>
    var articleIds: [String]
    var articleDates: [Date]
    var sentiments: [Double]
    var sources: Set<String>
    var firstSeen: Date
    var lastSeen: Date
    var phase: NarrativePhase
    var isFollowed: Bool
    var turningPoints: [NarrativeTurningPoint]
    var previousMomentum: Double
}

// MARK: - Engine

/// Autonomous narrative arc tracking engine.
public final class FeedNarrativeArcTracker: @unchecked Sendable {

    private var stories: [String: StoryState] = [:]
    private var articles: [String: NarrativeArticle] = [:]
    private var turningPoints: [NarrativeTurningPoint] = []
    private let similarityThreshold: Double
    private let dormantDays: Int
    private var nextStoryId: Int = 1

    /// Initialize the narrative arc tracker.
    /// - Parameters:
    ///   - similarityThreshold: Minimum Jaccard similarity to cluster articles (0-1, default 0.3)
    ///   - dormantDays: Days without activity before story becomes dormant (default 14)
    public init(similarityThreshold: Double = 0.3, dormantDays: Int = 14) {
        self.similarityThreshold = max(0.1, min(0.9, similarityThreshold))
        self.dormantDays = max(1, dormantDays)
    }

    // MARK: - Public API

    /// Ingest an article into the tracker. Automatically clusters it into
    /// an existing story or creates a new one.
    @discardableResult
    public func ingest(_ article: NarrativeArticle) -> String {
        articles[article.id] = article

        // Find best matching story
        var bestStoryId: String?
        var bestSimilarity: Double = 0.0

        for (storyId, story) in stories {
            let sim = similarity(articleKeywords: Set(article.keywords),
                                 articleEntities: Set(article.entities),
                                 storyKeywords: story.coreKeywords,
                                 storyEntities: story.coreEntities)
            if sim > bestSimilarity && sim >= similarityThreshold {
                bestSimilarity = sim
                bestStoryId = storyId
            }
        }

        if let storyId = bestStoryId {
            addArticleToStory(article, storyId: storyId)
            return storyId
        } else {
            return createNewStory(from: article)
        }
    }

    /// Ingest multiple articles at once.
    ///
    /// Equivalent to calling ``ingest(_:)`` for each article in order.
    /// Useful for backfilling a freshly-loaded feed without paying the
    /// observer-notification overhead per call site.
    public func ingestBatch(_ articles: [NarrativeArticle]) {
        for article in articles {
            ingest(article)
        }
    }

    /// Mark a story as followed by the user.
    ///
    /// Followed stories appear in ``NarrativeReport/followedStoryUpdates``
    /// and contribute to the engagement component of the health score.
    /// No-op if the story id is unknown.
    public func followStory(_ storyId: String) {
        stories[storyId]?.isFollowed = true
    }

    /// Stop following a previously-followed story. No-op if the id is
    /// unknown or the story is already unfollowed.
    public func unfollowStory(_ storyId: String) {
        stories[storyId]?.isFollowed = false
    }

    /// Snapshot of every story the tracker currently knows about,
    /// including dormant ones, sorted by descending momentum.
    public func getStories() -> [NarrativeThread] {
        return stories.values.map { buildThread(from: $0) }
            .sorted { $0.momentum > $1.momentum }
    }

    /// Snapshot of stories the user is explicitly following, sorted by
    /// descending momentum.
    public func getFollowedStories() -> [NarrativeThread] {
        return stories.values.filter { $0.isFollowed }
            .map { buildThread(from: $0) }
            .sorted { $0.momentum > $1.momentum }
    }

    /// Snapshot of stories currently in the given phase, sorted by
    /// descending momentum. Returns an empty array if no stories match.
    public func getStories(inPhase phase: NarrativePhase) -> [NarrativeThread] {
        return stories.values.filter { $0.phase == phase }
            .map { buildThread(from: $0) }
            .sorted { $0.momentum > $1.momentum }
    }

    /// Run full analysis and produce a fresh ``NarrativeReport``.
    ///
    /// Recomputes phase classifications for every story, regenerates
    /// forecasts, detects cross-story convergences, derives the health
    /// score and rolls up the latest twenty turning points. Safe to call
    /// at any cadence — internal state is not mutated by inspection,
    /// only by phase transitions discovered during this call.
    public func analyze() -> NarrativeReport {
        updateAllPhases()
        let convergences = detectConvergences()
        let forecasts = generateForecasts()
        let active = stories.values.filter { $0.phase != .dormant }
            .map { buildThread(from: $0) }
            .sorted { $0.momentum > $1.momentum }
        let followed = stories.values.filter { $0.isFollowed }
            .map { buildThread(from: $0) }
            .sorted { $0.lastSeen > $1.lastSeen }
        let recentTP = turningPoints.suffix(20).reversed().map { $0 }
        let insights = generateInsights(active: active, convergences: convergences)
        let health = computeHealthScore(active: active)

        return NarrativeReport(
            activeStories: active,
            recentTurningPoints: Array(recentTP),
            convergences: convergences,
            forecasts: forecasts,
            followedStoryUpdates: followed,
            healthScore: health,
            insights: insights
        )
    }

    /// Number of distinct stories the tracker currently holds, including
    /// dormant and resolved ones.
    public var storyCount: Int { stories.count }

    /// Total number of articles ingested across the tracker's lifetime,
    /// minus any cleared by ``reset()``.
    public var articleCount: Int { articles.count }

    /// Discard every story, article and turning point and reset the
    /// internal story-id counter to `1`. Used by tests and by callers
    /// that want to rebuild the tracker from scratch.
    public func reset() {
        stories.removeAll()
        articles.removeAll()
        turningPoints.removeAll()
        nextStoryId = 1
    }

    // MARK: - Private: Clustering

    private func similarity(articleKeywords: Set<String>, articleEntities: Set<String>,
                            storyKeywords: Set<String>, storyEntities: Set<String>) -> Double {
        let kwJaccard = jaccardSimilarity(articleKeywords, storyKeywords)
        let entJaccard = jaccardSimilarity(articleEntities, storyEntities)
        // Entities weighted higher since they're more specific
        return kwJaccard * 0.4 + entJaccard * 0.6
    }

    private func jaccardSimilarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 0.0 }
        let intersection = a.intersection(b).count
        let union = a.union(b).count
        return Double(intersection) / Double(union)
    }

    private func createNewStory(from article: NarrativeArticle) -> String {
        let id = "story_\(nextStoryId)"
        nextStoryId += 1

        let label = generateLabel(keywords: article.keywords, entities: article.entities)

        let story = StoryState(
            id: id,
            label: label,
            coreKeywords: Set(article.keywords),
            coreEntities: Set(article.entities),
            articleIds: [article.id],
            articleDates: [article.publishDate],
            sentiments: [article.sentiment],
            sources: [article.feedSource],
            firstSeen: article.publishDate,
            lastSeen: article.publishDate,
            phase: .emerging,
            isFollowed: false,
            turningPoints: [],
            previousMomentum: 0.0
        )

        stories[id] = story

        let tp = NarrativeTurningPoint(
            storyId: id,
            type: .emergence,
            detectedAt: article.publishDate,
            description: "New story emerged: \(label)",
            significance: 30.0,
            beforePhase: .dormant,
            afterPhase: .emerging
        )
        turningPoints.append(tp)
        stories[id]?.turningPoints.append(tp)

        NotificationCenter.default.post(name: .narrativeNewStoryEmerged, object: nil,
                                        userInfo: ["storyId": id])
        return id
    }

    private func addArticleToStory(_ article: NarrativeArticle, storyId: String) {
        guard var story = stories[storyId] else { return }

        let oldPhase = story.phase
        let oldMomentum = computeMomentum(for: story)

        story.articleIds.append(article.id)
        story.articleDates.append(article.publishDate)
        story.sentiments.append(article.sentiment)
        story.sources.insert(article.feedSource)
        story.lastSeen = max(story.lastSeen, article.publishDate)

        // Expand core keywords/entities (keep most frequent)
        story.coreKeywords.formUnion(article.keywords)
        story.coreEntities.formUnion(article.entities)

        story.previousMomentum = oldMomentum
        stories[storyId] = story

        // Check for turning points
        detectTurningPoints(storyId: storyId, article: article, oldPhase: oldPhase,
                            oldMomentum: oldMomentum)
    }

    // MARK: - Private: Phase Classification

    private func updateAllPhases() {
        let now = stories.values.map { $0.lastSeen }.max() ?? Date()
        for storyId in stories.keys {
            updatePhase(storyId: storyId, referenceDate: now)
        }
    }

    private func updatePhase(storyId: String, referenceDate: Date) {
        guard var story = stories[storyId] else { return }

        let oldPhase = story.phase
        let daysSinceLastSeen = Calendar.current.dateComponents(
            [.day], from: story.lastSeen, to: referenceDate).day ?? 0
        let articleCount = story.articleIds.count
        let momentum = computeMomentum(for: story)

        // Phase determination logic
        let newPhase: NarrativePhase
        if daysSinceLastSeen >= dormantDays {
            newPhase = .dormant
        } else if articleCount <= 2 {
            newPhase = .emerging
        } else if momentum > story.previousMomentum && momentum > 50.0 {
            newPhase = .climax
        } else if momentum > story.previousMomentum && momentum > 20.0 {
            newPhase = .rising
        } else if momentum < story.previousMomentum && articleCount > 5 {
            if momentum < 15.0 {
                newPhase = .resolution
            } else {
                newPhase = .falling
            }
        } else if story.phase == .climax && momentum <= story.previousMomentum {
            newPhase = .falling
        } else {
            newPhase = story.phase
        }

        story.phase = newPhase
        story.previousMomentum = momentum
        stories[storyId] = story

        if oldPhase != newPhase {
            let tp = NarrativeTurningPoint(
                storyId: storyId,
                type: newPhase == .climax ? .peakReached : (newPhase == .resolution ? .resolution : .accelerating),
                detectedAt: referenceDate,
                description: "Story '\(story.label)' moved from \(oldPhase.rawValue) to \(newPhase.rawValue)",
                significance: phaseTransitionSignificance(from: oldPhase, to: newPhase),
                beforePhase: oldPhase,
                afterPhase: newPhase
            )
            turningPoints.append(tp)
            stories[storyId]?.turningPoints.append(tp)

            NotificationCenter.default.post(name: .narrativePhaseChanged, object: nil,
                                            userInfo: ["storyId": storyId, "phase": newPhase.rawValue])
        }
    }

    private func phaseTransitionSignificance(from: NarrativePhase, to: NarrativePhase) -> Double {
        switch (from, to) {
        case (.rising, .climax): return 85.0
        case (.emerging, .rising): return 60.0
        case (.climax, .falling): return 70.0
        case (.falling, .resolution): return 50.0
        case (_, .dormant): return 30.0
        default: return 40.0
        }
    }

    // MARK: - Private: Momentum

    private func computeMomentum(for story: StoryState) -> Double {
        guard story.articleIds.count >= 2 else { return 10.0 }

        let sortedDates = story.articleDates.sorted()
        let totalDays = max(1.0, Calendar.current.dateComponents(
            [.day], from: sortedDates.first!, to: sortedDates.last!).day.map(Double.init) ?? 1.0)

        // Frequency component: articles per day (normalized)
        let frequency = Double(story.articleIds.count) / totalDays
        let frequencyScore = min(100.0, frequency * 30.0)

        // Recency component: recent articles weighted higher
        let recentCount = sortedDates.suffix(5).count
        let recencyScore = Double(recentCount) / 5.0 * 50.0

        // Source diversity component
        let diversityScore = min(30.0, Double(story.sources.count) * 10.0)

        // Composite momentum
        return min(100.0, frequencyScore * 0.4 + recencyScore * 0.3 + diversityScore * 0.3)
    }

    // MARK: - Private: Turning Points

    private func detectTurningPoints(storyId: String, article: NarrativeArticle,
                                     oldPhase: NarrativePhase, oldMomentum: Double) {
        guard let story = stories[storyId] else { return }

        let newMomentum = computeMomentum(for: story)

        // Acceleration detection
        if newMomentum - oldMomentum > 20.0 {
            let tp = NarrativeTurningPoint(
                storyId: storyId,
                type: .accelerating,
                detectedAt: article.publishDate,
                description: "Coverage of '\(story.label)' is accelerating rapidly",
                significance: min(90.0, 50.0 + (newMomentum - oldMomentum)),
                beforePhase: oldPhase,
                afterPhase: story.phase
            )
            turningPoints.append(tp)
            stories[storyId]?.turningPoints.append(tp)

            NotificationCenter.default.post(name: .narrativeTurningPointDetected, object: nil,
                                            userInfo: ["storyId": storyId, "type": "accelerating"])
        }

        // Sentiment shift detection
        if story.sentiments.count >= 3 {
            let recentSentiments = Array(story.sentiments.suffix(3))
            let oldSentiments = Array(story.sentiments.prefix(max(1, story.sentiments.count - 3)))
            let recentAvg = recentSentiments.reduce(0.0, +) / Double(recentSentiments.count)
            let oldAvg = oldSentiments.reduce(0.0, +) / Double(oldSentiments.count)

            if abs(recentAvg - oldAvg) > 0.5 {
                let direction = recentAvg > oldAvg ? "positive" : "negative"
                let tp = NarrativeTurningPoint(
                    storyId: storyId,
                    type: .sentimentShift,
                    detectedAt: article.publishDate,
                    description: "Sentiment shifted \(direction) for '\(story.label)'",
                    significance: min(80.0, abs(recentAvg - oldAvg) * 80.0),
                    beforePhase: oldPhase,
                    afterPhase: story.phase
                )
                turningPoints.append(tp)
                stories[storyId]?.turningPoints.append(tp)
            }
        }

        // New entity detection
        let newEntities = Set(article.entities).subtracting(story.coreEntities)
        if newEntities.count >= 2 && story.articleIds.count > 3 {
            let tp = NarrativeTurningPoint(
                storyId: storyId,
                type: .newActor,
                detectedAt: article.publishDate,
                description: "New entities in '\(story.label)': \(newEntities.prefix(3).joined(separator: ", "))",
                significance: 55.0,
                beforePhase: oldPhase,
                afterPhase: story.phase
            )
            turningPoints.append(tp)
            stories[storyId]?.turningPoints.append(tp)
        }
    }

    // MARK: - Private: Convergence Detection

    private func detectConvergences() -> [NarrativeConvergence] {
        var convergences: [NarrativeConvergence] = []
        let storyList = Array(stories.values)

        for i in 0..<storyList.count {
            for j in (i+1)..<storyList.count {
                let a = storyList[i]
                let b = storyList[j]

                let sharedEntities = Array(a.coreEntities.intersection(b.coreEntities))
                let sharedKeywords = Array(a.coreKeywords.intersection(b.coreKeywords))

                let entityOverlap = a.coreEntities.isEmpty || b.coreEntities.isEmpty ? 0.0 :
                    Double(sharedEntities.count) / Double(min(a.coreEntities.count, b.coreEntities.count))
                let keywordOverlap = a.coreKeywords.isEmpty || b.coreKeywords.isEmpty ? 0.0 :
                    Double(sharedKeywords.count) / Double(min(a.coreKeywords.count, b.coreKeywords.count))

                let strength = entityOverlap * 0.6 + keywordOverlap * 0.4
                if strength >= 0.3 && !sharedEntities.isEmpty {
                    convergences.append(NarrativeConvergence(
                        storyIdA: a.id,
                        storyIdB: b.id,
                        sharedEntities: sharedEntities,
                        sharedKeywords: sharedKeywords,
                        convergenceStrength: strength,
                        detectedAt: max(a.lastSeen, b.lastSeen)
                    ))
                }
            }
        }

        return convergences.sorted { $0.convergenceStrength > $1.convergenceStrength }
    }

    // MARK: - Private: Forecasting

    private func generateForecasts() -> [NarrativeForecast] {
        return stories.values.compactMap { story -> NarrativeForecast? in
            guard story.phase != .dormant && story.phase != .resolution else { return nil }
            guard story.articleIds.count >= 3 else { return nil }

            let momentum = computeMomentum(for: story)
            let (nextPhase, confidence, days, reasoning) = predictNextPhase(story: story, momentum: momentum)

            return NarrativeForecast(
                storyId: story.id,
                currentPhase: story.phase,
                predictedNextPhase: nextPhase,
                confidence: confidence,
                estimatedDaysToTransition: days,
                reasoning: reasoning
            )
        }
    }

    private func predictNextPhase(story: StoryState, momentum: Double)
        -> (NarrativePhase, Double, Int, String) {
        switch story.phase {
        case .emerging:
            if momentum > 30.0 {
                return (.rising, 0.7, 3, "Momentum building steadily with \(story.sources.count) sources")
            }
            return (.dormant, 0.4, 10, "Low momentum may lead to story fading")

        case .rising:
            if momentum > 60.0 {
                return (.climax, 0.75, 5, "High momentum suggests peak approaching")
            }
            return (.climax, 0.5, 10, "Continued coverage likely to peak soon")

        case .climax:
            return (.falling, 0.8, 4, "Peak coverage typically followed by decline")

        case .falling:
            if momentum < 15.0 {
                return (.resolution, 0.7, 7, "Declining coverage suggests resolution approaching")
            }
            return (.resolution, 0.5, 14, "Story gradually winding down")

        case .resolution, .dormant:
            return (.dormant, 0.6, 7, "Story likely to remain inactive")
        }
    }

    // MARK: - Private: Insights & Health

    private func generateInsights(active: [NarrativeThread],
                                  convergences: [NarrativeConvergence]) -> [String] {
        var insights: [String] = []

        let climaxStories = active.filter { $0.phase == .climax }
        if !climaxStories.isEmpty {
            insights.append("\(climaxStories.count) story/stories at peak coverage — pay attention to: " +
                            climaxStories.prefix(3).map { $0.label }.joined(separator: ", "))
        }

        let risingStories = active.filter { $0.phase == .rising }
        if risingStories.count >= 3 {
            insights.append("\(risingStories.count) stories building momentum — busy news cycle")
        }

        if !convergences.isEmpty {
            let top = convergences.first!
            if let storyA = stories[top.storyIdA], let storyB = stories[top.storyIdB] {
                insights.append("Stories '\(storyA.label)' and '\(storyB.label)' are converging")
            }
        }

        let multiSourceStories = active.filter { $0.sourceCount >= 3 }
        if !multiSourceStories.isEmpty {
            insights.append("\(multiSourceStories.count) stories covered by 3+ sources — high confidence topics")
        }

        let followed = active.filter { $0.isFollowed }
        let followedClimaxing = followed.filter { $0.phase == .climax || $0.phase == .rising }
        if !followedClimaxing.isEmpty {
            insights.append("⚡ \(followedClimaxing.count) followed story/stories hitting turning points")
        }

        if active.isEmpty {
            insights.append("No active narratives detected — consider expanding feed sources")
        }

        return insights
    }

    private func computeHealthScore(active: [NarrativeThread]) -> Double {
        guard !active.isEmpty else { return 0.0 }

        // Diversity of phases
        let phases = Set(active.map { $0.phase })
        let phaseDiversity = Double(phases.count) / 5.0 * 25.0

        // Active story count (more tracked = better awareness)
        let countScore = min(25.0, Double(active.count) * 5.0)

        // Source coverage (stories from multiple sources)
        let avgSources = active.map { Double($0.sourceCount) }.reduce(0, +) / Double(active.count)
        let sourceScore = min(25.0, avgSources * 10.0)

        // Followed story ratio (user engagement)
        let followedCount = active.filter { $0.isFollowed }.count
        let engagementScore = active.isEmpty ? 0.0 :
            min(25.0, Double(followedCount) / Double(active.count) * 50.0)

        return min(100.0, phaseDiversity + countScore + sourceScore + engagementScore)
    }

    // MARK: - Private: Utilities

    private func generateLabel(keywords: [String], entities: [String]) -> String {
        // Use top entity + keyword for a readable label
        let entity = entities.first ?? ""
        let keyword = keywords.first ?? "story"
        if entity.isEmpty {
            return keyword.capitalized
        }
        return "\(entity.capitalized): \(keyword)"
    }

    private func buildThread(from story: StoryState) -> NarrativeThread {
        return NarrativeThread(
            id: story.id,
            label: story.label,
            coreKeywords: Array(story.coreKeywords.prefix(10)),
            coreEntities: Array(story.coreEntities.prefix(10)),
            articleIds: story.articleIds,
            firstSeen: story.firstSeen,
            lastSeen: story.lastSeen,
            phase: story.phase,
            momentum: computeMomentum(for: story),
            sentimentTrajectory: computeSentimentTrajectory(story.sentiments),
            sourceCount: story.sources.count,
            isFollowed: story.isFollowed
        )
    }

    private func computeSentimentTrajectory(_ sentiments: [Double]) -> Double {
        guard sentiments.count >= 2 else { return 0.0 }
        let half = sentiments.count / 2
        let firstHalf = Array(sentiments.prefix(half))
        let secondHalf = Array(sentiments.suffix(half))
        let firstAvg = firstHalf.reduce(0.0, +) / Double(firstHalf.count)
        let secondAvg = secondHalf.reduce(0.0, +) / Double(secondHalf.count)
        return secondAvg - firstAvg
    }
}
