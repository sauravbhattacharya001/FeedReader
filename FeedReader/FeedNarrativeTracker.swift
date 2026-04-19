//
//  FeedNarrativeTracker.swift
//  FeedReader
//
//  Tracks evolving story narratives across feeds over time. Groups related
//  articles into "narrative threads," detects how stories develop (new info,
//  contradictions, corrections, escalations), and proactively surfaces stories
//  that need follow-up attention.
//
//  Agentic capabilities:
//  - Auto-groups related articles into narrative threads via keyword similarity
//  - Detects narrative shifts (tone changes, contradictions, escalations)
//  - Proactively flags stories needing follow-up ("developing story" alerts)
//  - Generates narrative timeline summaries
//  - Identifies information gaps and unanswered questions
//  - Tracks source diversity per narrative (single-source vs well-covered)
//
//  Fully offline — no network, no dependencies beyond Foundation.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    static let narrativeThreadCreated = Notification.Name("NarrativeThreadCreatedNotification")
    static let narrativeShiftDetected = Notification.Name("NarrativeShiftDetectedNotification")
    static let narrativeFollowUpNeeded = Notification.Name("NarrativeFollowUpNeededNotification")
}

// MARK: - Narrative Shift Types

/// The kind of evolution detected between articles in a narrative.
enum NarrativeShiftType: String, Codable {
    case newInformation       // adds previously unknown details
    case contradiction        // conflicts with earlier reporting
    case correction           // explicitly corrects prior info
    case escalation           // story severity/scope increased
    case deEscalation         // story calming down
    case sourceExpansion      // new sources picking up the story
    case perspectiveShift     // framing or angle changed significantly
    case resolution           // story reached a conclusion
    case stale                // story went quiet — may need follow-up
}

// MARK: - Narrative Article Entry

/// A single article's contribution to a narrative thread.
struct NarrativeEntry: Codable, Identifiable {
    let id: String
    let articleTitle: String
    let articleLink: String
    let sourceFeed: String
    let addedDate: Date
    let keywords: [String]
    let sentimentScore: Double   // -1.0 (negative) to 1.0 (positive)
    let snippetPreview: String   // first ~200 chars

    init(articleTitle: String, articleLink: String, sourceFeed: String,
         addedDate: Date = Date(), keywords: [String], sentimentScore: Double,
         snippetPreview: String) {
        self.id = UUID().uuidString
        self.articleTitle = articleTitle
        self.articleLink = articleLink
        self.sourceFeed = sourceFeed
        self.addedDate = addedDate
        self.keywords = keywords
        self.sentimentScore = sentimentScore
        self.snippetPreview = String(snippetPreview.prefix(200))
    }
}

// MARK: - Narrative Shift Event

/// Records a detected shift between two entries in the same narrative.
struct NarrativeShift: Codable, Identifiable {
    let id: String
    let shiftType: NarrativeShiftType
    let detectedDate: Date
    let fromEntryId: String
    let toEntryId: String
    let confidence: Double       // 0.0–1.0
    let explanation: String

    init(shiftType: NarrativeShiftType, fromEntryId: String, toEntryId: String,
         confidence: Double, explanation: String) {
        self.id = UUID().uuidString
        self.shiftType = shiftType
        self.detectedDate = Date()
        self.fromEntryId = fromEntryId
        self.toEntryId = toEntryId
        self.confidence = min(1.0, max(0.0, confidence))
        self.explanation = explanation
    }
}

// MARK: - Follow-Up Alert

/// A proactive recommendation to revisit a narrative thread.
struct NarrativeFollowUp: Codable, Identifiable {
    let id: String
    let threadId: String
    let reason: FollowUpReason
    let priority: FollowUpPriority
    let createdDate: Date
    var dismissed: Bool

    enum FollowUpReason: String, Codable {
        case developingStory      // rapid new entries
        case contradictionFound   // conflicting reports detected
        case goneQuiet            // was active, now silent
        case singleSource         // only one feed covering it
        case sentimentSwing       // big tone change
        case unansweredQuestion   // narrative has open questions
    }

    enum FollowUpPriority: Int, Codable, Comparable {
        case low = 1
        case medium = 2
        case high = 3
        case critical = 4

        static func < (lhs: FollowUpPriority, rhs: FollowUpPriority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    init(threadId: String, reason: FollowUpReason, priority: FollowUpPriority) {
        self.id = UUID().uuidString
        self.threadId = threadId
        self.reason = reason
        self.priority = priority
        self.createdDate = Date()
        self.dismissed = false
    }
}

// MARK: - Narrative Thread

/// A group of related articles forming an evolving story.
struct NarrativeThread: Codable, Identifiable {
    let id: String
    var title: String                   // auto-generated from first article
    var entries: [NarrativeEntry]
    var shifts: [NarrativeShift]
    var followUps: [NarrativeFollowUp]
    var coreKeywords: [String]          // defining keywords
    let createdDate: Date
    var lastUpdated: Date
    var archived: Bool

    init(title: String, coreKeywords: [String]) {
        self.id = UUID().uuidString
        self.title = title
        self.entries = []
        self.shifts = []
        self.followUps = []
        self.coreKeywords = coreKeywords
        self.createdDate = Date()
        self.lastUpdated = Date()
        self.archived = false
    }

    // MARK: - Computed Properties

    /// Number of unique feeds contributing to this narrative.
    var sourceDiversity: Int {
        Set(entries.map { $0.sourceFeed }).count
    }

    /// Average sentiment across all entries.
    var averageSentiment: Double {
        guard !entries.isEmpty else { return 0.0 }
        return entries.map { $0.sentimentScore }.reduce(0, +) / Double(entries.count)
    }

    /// Sentiment trend: difference between recent and early average.
    var sentimentTrend: Double {
        guard entries.count >= 2 else { return 0.0 }
        let sorted = entries.sorted { $0.addedDate < $1.addedDate }
        let mid = sorted.count / 2
        let earlyAvg = sorted[0..<mid].map { $0.sentimentScore }.reduce(0, +) / Double(mid)
        let lateAvg = sorted[mid...].map { $0.sentimentScore }.reduce(0, +) / Double(sorted.count - mid)
        return lateAvg - earlyAvg
    }

    /// How many hours since the last entry was added.
    var hoursSinceLastUpdate: Double {
        guard let latest = entries.map({ $0.addedDate }).max() else { return .infinity }
        return Date().timeIntervalSince(latest) / 3600.0
    }

    /// Whether this narrative is actively developing (entry in last 24h).
    var isDeveloping: Bool {
        hoursSinceLastUpdate < 24.0
    }

    /// Count of unresolved (non-dismissed) follow-up alerts.
    var activeFollowUpCount: Int {
        followUps.filter { !$0.dismissed }.count
    }
}

// MARK: - Narrative Timeline Entry

/// A point on the narrative's timeline for display.
struct NarrativeTimelinePoint: Codable {
    let date: Date
    let label: String
    let entryId: String?
    let shiftType: NarrativeShiftType?
}

// MARK: - FeedNarrativeTracker

/// Singleton tracker that groups articles into narrative threads,
/// detects shifts, and generates proactive follow-up alerts.
final class FeedNarrativeTracker {

    static let shared = FeedNarrativeTracker()

    private(set) var threads: [NarrativeThread] = []
    private let similarityThreshold: Double = 0.30
    private let staleHoursThreshold: Double = 72.0
    private let sentimentSwingThreshold: Double = 0.6

    // MARK: - Persistence

    private var storageURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("feed_narrative_threads.json")
    }

    private init() {
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        if let decoded = try? JSONDecoder().decode([NarrativeThread].self, from: data) {
            threads = decoded
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(threads) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }

    // MARK: - Keyword Extraction

    /// Extracts significant keywords from text using simple TF heuristics.
    func extractKeywords(from text: String, maxCount: Int = 10) -> [String] {
        let stopWords: Set<String> = [
            "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
            "have", "has", "had", "do", "does", "did", "will", "would", "shall",
            "should", "may", "might", "can", "could", "must", "and", "but", "or",
            "nor", "not", "so", "yet", "both", "either", "neither", "each", "every",
            "all", "any", "few", "more", "most", "other", "some", "such", "no",
            "only", "own", "same", "than", "too", "very", "just", "because",
            "as", "until", "while", "of", "at", "by", "for", "with", "about",
            "against", "between", "through", "during", "before", "after", "above",
            "below", "to", "from", "up", "down", "in", "out", "on", "off", "over",
            "under", "again", "further", "then", "once", "here", "there", "when",
            "where", "why", "how", "what", "which", "who", "whom", "this", "that",
            "these", "those", "it", "its", "he", "she", "they", "them", "his",
            "her", "their", "we", "our", "you", "your", "my", "i", "me", "said",
            "also", "new", "one", "two", "first", "last", "many", "much", "get",
            "like", "make", "know", "take", "come", "think", "say", "see", "go"
        ]

        let lower = text.lowercased()
        let tokens = lower.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }

        var freq: [String: Int] = [:]
        for token in tokens { freq[token, default: 0] += 1 }

        return freq.sorted { $0.value > $1.value }
            .prefix(maxCount)
            .map { $0.key }
    }

    // MARK: - Simple Sentiment

    /// Quick sentiment estimate based on keyword hits. Returns -1.0 to 1.0.
    func estimateSentiment(text: String) -> Double {
        let positiveWords: Set<String> = [
            "good", "great", "excellent", "positive", "success", "win", "improve",
            "growth", "gain", "hope", "recover", "breakthrough", "achievement",
            "progress", "strong", "boost", "surge", "optimistic", "benefit", "praise"
        ]
        let negativeWords: Set<String> = [
            "bad", "worse", "worst", "negative", "failure", "loss", "decline",
            "crisis", "crash", "fear", "threat", "damage", "risk", "concern",
            "weak", "drop", "fall", "pessimistic", "danger", "warn", "attack",
            "kill", "dead", "death", "destroy", "collapse", "scandal", "fraud"
        ]

        let tokens = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }

        guard !tokens.isEmpty else { return 0.0 }

        var pos = 0, neg = 0
        for t in tokens {
            if positiveWords.contains(t) { pos += 1 }
            if negativeWords.contains(t) { neg += 1 }
        }

        let total = Double(pos + neg)
        guard total > 0 else { return 0.0 }
        return (Double(pos) - Double(neg)) / total
    }

    // MARK: - Similarity

    /// Jaccard similarity between two keyword sets.
    private func keywordSimilarity(_ a: [String], _ b: [String]) -> Double {
        let setA = Set(a)
        let setB = Set(b)
        let intersection = setA.intersection(setB).count
        let union = setA.union(setB).count
        guard union > 0 else { return 0.0 }
        return Double(intersection) / Double(union)
    }

    // MARK: - Ingest Article

    /// Process a new article: find or create a narrative thread, detect shifts.
    @discardableResult
    func ingestArticle(title: String, body: String, link: String,
                       sourceFeed: String) -> NarrativeThread {
        let fullText = "\(title) \(body)"
        let keywords = extractKeywords(from: fullText)
        let sentiment = estimateSentiment(text: fullText)
        let snippet = String(body.prefix(200))

        let entry = NarrativeEntry(
            articleTitle: title, articleLink: link, sourceFeed: sourceFeed,
            keywords: keywords, sentimentScore: sentiment, snippetPreview: snippet
        )

        // Find best matching thread
        var bestIdx: Int? = nil
        var bestScore: Double = 0.0

        for (i, thread) in threads.enumerated() where !thread.archived {
            let sim = keywordSimilarity(keywords, thread.coreKeywords)
            if sim > bestScore {
                bestScore = sim
                bestIdx = i
            }
        }

        if let idx = bestIdx, bestScore >= similarityThreshold {
            // Add to existing thread
            let previousEntry = threads[idx].entries.last
            threads[idx].entries.append(entry)
            threads[idx].lastUpdated = Date()

            // Update core keywords (merge top keywords)
            let allKw = threads[idx].entries.flatMap { $0.keywords }
            var kwFreq: [String: Int] = [:]
            for k in allKw { kwFreq[k, default: 0] += 1 }
            threads[idx].coreKeywords = kwFreq.sorted { $0.value > $1.value }
                .prefix(12).map { $0.key }

            // Detect shifts
            if let prev = previousEntry {
                let detectedShifts = detectShifts(from: prev, to: entry, thread: threads[idx])
                threads[idx].shifts.append(contentsOf: detectedShifts)

                for shift in detectedShifts {
                    NotificationCenter.default.post(
                        name: .narrativeShiftDetected,
                        object: nil,
                        userInfo: ["threadId": threads[idx].id, "shift": shift.shiftType.rawValue]
                    )
                }
            }

            // Check follow-ups
            let newFollowUps = evaluateFollowUps(for: threads[idx])
            threads[idx].followUps.append(contentsOf: newFollowUps)

            for fu in newFollowUps {
                NotificationCenter.default.post(
                    name: .narrativeFollowUpNeeded,
                    object: nil,
                    userInfo: ["threadId": threads[idx].id, "reason": fu.reason.rawValue]
                )
            }

            save()
            return threads[idx]
        } else {
            // Create new thread
            var thread = NarrativeThread(title: title, coreKeywords: keywords)
            thread.entries.append(entry)
            threads.append(thread)

            NotificationCenter.default.post(
                name: .narrativeThreadCreated,
                object: nil,
                userInfo: ["threadId": thread.id, "title": title]
            )

            save()
            return thread
        }
    }

    // MARK: - Shift Detection

    /// Compares two consecutive entries to detect narrative shifts.
    private func detectShifts(from prev: NarrativeEntry, to curr: NarrativeEntry,
                              thread: NarrativeThread) -> [NarrativeShift] {
        var shifts: [NarrativeShift] = []

        // Sentiment swing
        let sentimentDelta = curr.sentimentScore - prev.sentimentScore
        if abs(sentimentDelta) >= sentimentSwingThreshold {
            let shiftType: NarrativeShiftType = sentimentDelta > 0 ? .deEscalation : .escalation
            shifts.append(NarrativeShift(
                shiftType: shiftType,
                fromEntryId: prev.id, toEntryId: curr.id,
                confidence: min(1.0, abs(sentimentDelta)),
                explanation: String(format: "Sentiment shifted %.2f → %.2f (%@)",
                                    prev.sentimentScore, curr.sentimentScore,
                                    shiftType == .escalation ? "tone worsened" : "tone improved")
            ))
        }

        // Source expansion
        let existingSources = Set(thread.entries.dropLast().map { $0.sourceFeed })
        if !existingSources.contains(curr.sourceFeed) && existingSources.count >= 1 {
            shifts.append(NarrativeShift(
                shiftType: .sourceExpansion,
                fromEntryId: prev.id, toEntryId: curr.id,
                confidence: 0.8,
                explanation: "New source '\(curr.sourceFeed)' picked up this story (was covered by \(existingSources.count) source(s))"
            ))
        }

        // Perspective shift — low keyword overlap between consecutive entries
        let kwSim = keywordSimilarity(prev.keywords, curr.keywords)
        if kwSim < 0.15 && kwSim > 0.0 {
            shifts.append(NarrativeShift(
                shiftType: .perspectiveShift,
                fromEntryId: prev.id, toEntryId: curr.id,
                confidence: 1.0 - kwSim,
                explanation: String(format: "Keyword overlap only %.0f%% — framing may have changed", kwSim * 100)
            ))
        }

        // Contradiction detection — opposite sentiment + low overlap
        if sentimentDelta < -0.4 && kwSim < 0.25 {
            shifts.append(NarrativeShift(
                shiftType: .contradiction,
                fromEntryId: prev.id, toEntryId: curr.id,
                confidence: min(1.0, abs(sentimentDelta) * (1.0 - kwSim)),
                explanation: "Conflicting tone and different framing suggest possible contradiction"
            ))
        }

        // New information — high keyword novelty
        let prevKwSet = Set(prev.keywords)
        let novelKeywords = curr.keywords.filter { !prevKwSet.contains($0) }
        if novelKeywords.count >= 5 {
            shifts.append(NarrativeShift(
                shiftType: .newInformation,
                fromEntryId: prev.id, toEntryId: curr.id,
                confidence: min(1.0, Double(novelKeywords.count) / 10.0),
                explanation: "New keywords: \(novelKeywords.prefix(5).joined(separator: ", "))"
            ))
        }

        return shifts
    }

    // MARK: - Follow-Up Evaluation

    /// Generate follow-up alerts based on current thread state.
    private func evaluateFollowUps(for thread: NarrativeThread) -> [NarrativeFollowUp] {
        var followUps: [NarrativeFollowUp] = []
        let existingReasons = Set(thread.followUps.filter { !$0.dismissed }.map { $0.reason })

        // Developing story — 3+ entries in last 24h
        let recentCount = thread.entries.filter {
            Date().timeIntervalSince($0.addedDate) < 86400
        }.count
        if recentCount >= 3 && !existingReasons.contains(.developingStory) {
            followUps.append(NarrativeFollowUp(
                threadId: thread.id, reason: .developingStory, priority: .high
            ))
        }

        // Contradiction found
        let recentContradictions = thread.shifts.filter {
            $0.shiftType == .contradiction &&
            Date().timeIntervalSince($0.detectedDate) < 86400
        }
        if !recentContradictions.isEmpty && !existingReasons.contains(.contradictionFound) {
            followUps.append(NarrativeFollowUp(
                threadId: thread.id, reason: .contradictionFound, priority: .critical
            ))
        }

        // Single source
        if thread.sourceDiversity == 1 && thread.entries.count >= 2
            && !existingReasons.contains(.singleSource) {
            followUps.append(NarrativeFollowUp(
                threadId: thread.id, reason: .singleSource, priority: .medium
            ))
        }

        // Sentiment swing
        if abs(thread.sentimentTrend) >= sentimentSwingThreshold
            && !existingReasons.contains(.sentimentSwing) {
            followUps.append(NarrativeFollowUp(
                threadId: thread.id, reason: .sentimentSwing, priority: .high
            ))
        }

        return followUps
    }

    // MARK: - Staleness Check

    /// Run periodic staleness check on all active threads.
    func checkStaleness() {
        for i in threads.indices where !threads[i].archived {
            if threads[i].hoursSinceLastUpdate >= staleHoursThreshold {
                let existingReasons = Set(threads[i].followUps.filter { !$0.dismissed }.map { $0.reason })
                if !existingReasons.contains(.goneQuiet) {
                    let fu = NarrativeFollowUp(
                        threadId: threads[i].id, reason: .goneQuiet, priority: .low
                    )
                    threads[i].followUps.append(fu)
                    NotificationCenter.default.post(
                        name: .narrativeFollowUpNeeded,
                        object: nil,
                        userInfo: ["threadId": threads[i].id, "reason": "goneQuiet"]
                    )
                }
            }
        }
        save()
    }

    // MARK: - Timeline

    /// Generate a chronological timeline for a narrative thread.
    func timeline(for threadId: String) -> [NarrativeTimelinePoint] {
        guard let thread = threads.first(where: { $0.id == threadId }) else { return [] }

        var points: [NarrativeTimelinePoint] = []

        // Add article entries
        for entry in thread.entries {
            points.append(NarrativeTimelinePoint(
                date: entry.addedDate,
                label: "📰 \(entry.articleTitle) [\(entry.sourceFeed)]",
                entryId: entry.id, shiftType: nil
            ))
        }

        // Add shift events
        for shift in thread.shifts {
            let emoji: String
            switch shift.shiftType {
            case .newInformation: emoji = "🆕"
            case .contradiction: emoji = "⚠️"
            case .correction: emoji = "✏️"
            case .escalation: emoji = "🔺"
            case .deEscalation: emoji = "🔻"
            case .sourceExpansion: emoji = "📡"
            case .perspectiveShift: emoji = "🔄"
            case .resolution: emoji = "✅"
            case .stale: emoji = "💤"
            }
            points.append(NarrativeTimelinePoint(
                date: shift.detectedDate,
                label: "\(emoji) \(shift.shiftType.rawValue): \(shift.explanation)",
                entryId: nil, shiftType: shift.shiftType
            ))
        }

        return points.sorted { $0.date < $1.date }
    }

    // MARK: - Queries

    /// Active (non-archived) threads sorted by last updated.
    var activeThreads: [NarrativeThread] {
        threads.filter { !$0.archived }
            .sorted { $0.lastUpdated > $1.lastUpdated }
    }

    /// Threads with unresolved follow-up alerts, highest priority first.
    var threadsNeedingAttention: [NarrativeThread] {
        threads.filter { $0.activeFollowUpCount > 0 && !$0.archived }
            .sorted {
                let maxA = $0.followUps.filter { !$0.dismissed }.map { $0.priority }.max() ?? .low
                let maxB = $1.followUps.filter { !$0.dismissed }.map { $0.priority }.max() ?? .low
                return maxA > maxB
            }
    }

    /// Developing stories (entries in last 24 hours).
    var developingStories: [NarrativeThread] {
        threads.filter { $0.isDeveloping && !$0.archived }
            .sorted { $0.entries.count > $1.entries.count }
    }

    /// Threads that have gone quiet.
    var staleThreads: [NarrativeThread] {
        threads.filter { $0.hoursSinceLastUpdate >= staleHoursThreshold && !$0.archived }
    }

    // MARK: - Thread Management

    /// Dismiss a follow-up alert.
    func dismissFollowUp(id: String, in threadId: String) {
        guard let ti = threads.firstIndex(where: { $0.id == threadId }),
              let fi = threads[ti].followUps.firstIndex(where: { $0.id == id }) else { return }
        threads[ti].followUps[fi].dismissed = true
        save()
    }

    /// Archive a thread (no longer tracked actively).
    func archiveThread(id: String) {
        guard let idx = threads.firstIndex(where: { $0.id == id }) else { return }
        threads[idx].archived = true
        save()
    }

    /// Unarchive a thread.
    func unarchiveThread(id: String) {
        guard let idx = threads.firstIndex(where: { $0.id == id }) else { return }
        threads[idx].archived = false
        save()
    }

    /// Delete a thread permanently.
    func deleteThread(id: String) {
        threads.removeAll { $0.id == id }
        save()
    }

    /// Merge two threads into one.
    func mergeThreads(keepId: String, mergeId: String) {
        guard let keepIdx = threads.firstIndex(where: { $0.id == keepId }),
              let mergeIdx = threads.firstIndex(where: { $0.id == mergeId }) else { return }

        threads[keepIdx].entries.append(contentsOf: threads[mergeIdx].entries)
        threads[keepIdx].entries.sort { $0.addedDate < $1.addedDate }
        threads[keepIdx].shifts.append(contentsOf: threads[mergeIdx].shifts)

        // Recalculate core keywords
        let allKw = threads[keepIdx].entries.flatMap { $0.keywords }
        var kwFreq: [String: Int] = [:]
        for k in allKw { kwFreq[k, default: 0] += 1 }
        threads[keepIdx].coreKeywords = kwFreq.sorted { $0.value > $1.value }
            .prefix(12).map { $0.key }

        threads[keepIdx].lastUpdated = Date()
        threads.remove(at: mergeIdx)
        save()
    }

    // MARK: - Summary Export

    /// Plain-text summary of a narrative thread.
    func textSummary(for threadId: String) -> String {
        guard let thread = threads.first(where: { $0.id == threadId }) else {
            return "Thread not found."
        }

        var lines: [String] = []
        lines.append("═══ NARRATIVE: \(thread.title) ═══")
        lines.append("Status: \(thread.isDeveloping ? "🔴 DEVELOPING" : thread.archived ? "📦 Archived" : "🟢 Active")")
        lines.append("Articles: \(thread.entries.count) | Sources: \(thread.sourceDiversity) | Shifts: \(thread.shifts.count)")
        lines.append(String(format: "Sentiment: %.2f (trend: %+.2f)", thread.averageSentiment, thread.sentimentTrend))

        if !thread.followUps.filter({ !$0.dismissed }).isEmpty {
            lines.append("")
            lines.append("⚡ FOLLOW-UP ALERTS:")
            for fu in thread.followUps where !fu.dismissed {
                let priorityEmoji: String
                switch fu.priority {
                case .low: priorityEmoji = "🟢"
                case .medium: priorityEmoji = "🟡"
                case .high: priorityEmoji = "🟠"
                case .critical: priorityEmoji = "🔴"
                }
                lines.append("  \(priorityEmoji) \(fu.reason.rawValue)")
            }
        }

        lines.append("")
        lines.append("TIMELINE:")
        for point in timeline(for: threadId) {
            let df = DateFormatter()
            df.dateFormat = "MMM d, HH:mm"
            lines.append("  \(df.string(from: point.date)) — \(point.label)")
        }

        return lines.joined(separator: "\n")
    }

    /// JSON export of all threads.
    func exportJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(threads),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    // MARK: - Statistics

    /// Overall narrative tracking statistics.
    func statistics() -> [String: Any] {
        let active = threads.filter { !$0.archived }
        let totalEntries = threads.flatMap { $0.entries }.count
        let totalShifts = threads.flatMap { $0.shifts }.count
        let activeAlerts = threads.flatMap { $0.followUps }.filter { !$0.dismissed }.count

        return [
            "totalThreads": threads.count,
            "activeThreads": active.count,
            "archivedThreads": threads.count - active.count,
            "totalArticlesTracked": totalEntries,
            "totalShiftsDetected": totalShifts,
            "activeFollowUpAlerts": activeAlerts,
            "developingStories": developingStories.count,
            "staleThreads": staleThreads.count,
            "averageSourceDiversity": active.isEmpty ? 0 :
                Double(active.map { $0.sourceDiversity }.reduce(0, +)) / Double(active.count)
        ]
    }
}
