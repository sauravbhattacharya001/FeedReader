//
//  ReadingChallengeManager.swift
//  FeedReader
//
//  Time-limited reading challenges that gamify and motivate reading habits.
//  Users create challenges with specific targets (article count, time spent,
//  feed diversity, streak maintenance) and deadlines. Tracks progress,
//  completion rates, and personal bests.
//
//  Unlike ReadingGoalsManager (open-ended daily/weekly targets) or
//  ReadingStreakTracker (consecutive-day tracking), challenges are
//  finite, deadline-driven events with specific completion criteria.
//
//  Persistence: UserDefaults via Codable JSON.
//  Fully offline — no network, no dependencies beyond Foundation.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when any challenge is created, updated, or completed.
    static let readingChallengesDidChange = Notification.Name("ReadingChallengesDidChangeNotification")
    /// Posted when a challenge is completed (check userInfo for challenge ID).
    static let readingChallengeCompleted = Notification.Name("ReadingChallengeCompletedNotification")
}

// MARK: - ChallengeType

/// The kind of reading activity a challenge measures.
enum ChallengeType: String, Codable, CaseIterable {
    /// Read N articles total.
    case articleCount = "article_count"
    /// Spend N minutes reading total.
    case timeSpent = "time_spent"
    /// Read from N distinct feeds.
    case feedDiversity = "feed_diversity"
    /// Maintain a reading streak of N consecutive days.
    case streakDays = "streak_days"
    /// Read N articles from a specific feed.
    case feedSpecific = "feed_specific"
    /// Read articles on N distinct calendar days.
    case activeDays = "active_days"

    /// Human-readable label.
    var label: String {
        switch self {
        case .articleCount: return "Article Count"
        case .timeSpent: return "Reading Time"
        case .feedDiversity: return "Feed Diversity"
        case .streakDays: return "Streak Days"
        case .feedSpecific: return "Feed Focus"
        case .activeDays: return "Active Days"
        }
    }

    /// Describes what the target number means.
    func targetUnit(value: Int) -> String {
        switch self {
        case .articleCount: return value == 1 ? "article" : "articles"
        case .timeSpent: return value == 1 ? "minute" : "minutes"
        case .feedDiversity: return value == 1 ? "feed" : "feeds"
        case .streakDays: return value == 1 ? "day" : "consecutive days"
        case .feedSpecific: return value == 1 ? "article" : "articles"
        case .activeDays: return value == 1 ? "day" : "days"
        }
    }
}

// MARK: - ChallengeDuration

/// Preset durations for challenges.
enum ChallengeDuration: String, Codable, CaseIterable {
    case threeDay = "3_day"
    case oneWeek = "1_week"
    case twoWeek = "2_week"
    case oneMonth = "1_month"
    case custom = "custom"

    /// Number of seconds for preset durations.
    var seconds: TimeInterval? {
        switch self {
        case .threeDay: return 3 * 24 * 3600
        case .oneWeek: return 7 * 24 * 3600
        case .twoWeek: return 14 * 24 * 3600
        case .oneMonth: return 30 * 24 * 3600
        case .custom: return nil
        }
    }

    /// Human-readable label.
    var label: String {
        switch self {
        case .threeDay: return "3 Days"
        case .oneWeek: return "1 Week"
        case .twoWeek: return "2 Weeks"
        case .oneMonth: return "1 Month"
        case .custom: return "Custom"
        }
    }
}

// MARK: - ChallengeStatus

/// Current state of a challenge.
enum ChallengeStatus: String, Codable {
    case active = "active"
    case completed = "completed"
    case failed = "failed"
    case abandoned = "abandoned"

    /// Whether the challenge is still in progress.
    var isOngoing: Bool { return self == .active }
}

// MARK: - ReadingChallenge

/// A single reading challenge with target, deadline, and progress.
struct ReadingChallenge: Codable, Equatable {
    /// Unique identifier.
    let id: String
    /// User-chosen name for the challenge.
    var name: String
    /// What kind of reading activity is measured.
    let type: ChallengeType
    /// Target value to reach (e.g. 50 articles, 120 minutes).
    let target: Int
    /// Current progress toward the target.
    var progress: Int
    /// When the challenge was created.
    let createdAt: Date
    /// When the challenge starts (may be future-dated).
    let startDate: Date
    /// Deadline for completion.
    let endDate: Date
    /// Current status.
    var status: ChallengeStatus
    /// When the challenge was completed (nil if not yet).
    var completedAt: Date?
    /// For feedSpecific type: the feed URL to focus on.
    var feedURL: String?
    /// Emoji icon for the challenge.
    var icon: String
    /// Distinct feed URLs read during this challenge (for diversity tracking).
    var distinctFeedURLs: Set<String>
    /// Distinct calendar day strings (yyyy-MM-dd) with reading activity.
    var activeDayStrings: Set<String>
    /// Longest consecutive-day streak during this challenge.
    var longestStreak: Int
    /// Current consecutive-day streak.
    var currentStreak: Int
    /// Last day a reading was recorded (yyyy-MM-dd).
    var lastActiveDay: String?

    /// Percentage complete (0.0 to 1.0, clamped).
    var percentComplete: Double {
        guard target > 0 else { return 0.0 }
        return min(Double(progress) / Double(target), 1.0)
    }

    /// Whether the deadline has passed.
    func isExpired(now: Date = Date()) -> Bool {
        return now >= endDate
    }

    /// Time remaining until deadline.
    func timeRemaining(now: Date = Date()) -> TimeInterval {
        return max(endDate.timeIntervalSince(now), 0)
    }

    /// Whether the target has been reached.
    var isTargetReached: Bool {
        return progress >= target
    }

    /// Days elapsed since start.
    func daysElapsed(now: Date = Date(), calendar: Calendar = .current) -> Int {
        let start = max(startDate, createdAt)
        return max(calendar.dateComponents([.day], from: start, to: now).day ?? 0, 0)
    }

    /// Total duration in days.
    func totalDays(calendar: Calendar = .current) -> Int {
        return max(calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 1, 1)
    }

    /// Pace: current progress rate vs required rate to finish on time.
    /// Returns > 1.0 if ahead of schedule, < 1.0 if behind.
    func pace(now: Date = Date(), calendar: Calendar = .current) -> Double {
        let elapsed = daysElapsed(now: now, calendar: calendar)
        let total = totalDays(calendar: calendar)
        guard total > 0 && elapsed > 0 else { return 0.0 }
        let expectedProgress = Double(target) * Double(elapsed) / Double(total)
        guard expectedProgress > 0 else { return 0.0 }
        return Double(progress) / expectedProgress
    }

    static func == (lhs: ReadingChallenge, rhs: ReadingChallenge) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - ChallengeTemplate

/// Pre-built challenge templates users can start with one tap.
struct ChallengeTemplate {
    let name: String
    let icon: String
    let type: ChallengeType
    let target: Int
    let duration: ChallengeDuration
    let description: String
}

// MARK: - ChallengeStats

/// Aggregate statistics across all challenges.
struct ChallengeStats: Equatable {
    /// Total challenges ever created.
    let totalCreated: Int
    /// Challenges completed successfully.
    let totalCompleted: Int
    /// Challenges that expired without completion.
    let totalFailed: Int
    /// Challenges abandoned by the user.
    let totalAbandoned: Int
    /// Currently active challenges.
    let activeCount: Int
    /// Completion rate (completed / finished, where finished = completed + failed).
    let completionRate: Double
    /// Average pace at completion (> 1.0 means finishing early on average).
    let averagePaceAtCompletion: Double
    /// Best streak achieved across all streak challenges.
    let bestStreak: Int
    /// Most articles read in a single challenge.
    let mostArticlesInChallenge: Int
    /// Current active challenge with highest progress percentage.
    let leadingChallenge: ReadingChallenge?
}

// MARK: - ReadingChallengeManager

class ReadingChallengeManager {

    // MARK: - Singleton

    static let shared = ReadingChallengeManager()

    // MARK: - Constants

    /// Maximum number of concurrent active challenges.
    static let maxActiveChallenges = 5
    /// Maximum target value for any challenge type.
    static let maxTarget = 10000
    /// UserDefaults key for persisted challenges.
    static let storageKey = "ReadingChallengeManager.challenges"

    // MARK: - Properties

    /// All challenges (active, completed, failed, abandoned).
    private(set) var challenges: [ReadingChallenge] = []

    /// Calendar used for date calculations.
    private let calendar: Calendar

    /// Persistence store.
    private let store = UserDefaultsCodableStore<[ReadingChallenge]>(
        key: ReadingChallengeManager.storageKey
    )

    /// Date formatter for day strings.
    private let dayFormatter = DateFormatting.isoDate

    // MARK: - Templates

    /// Pre-built challenge templates for quick starts.
    static let templates: [ChallengeTemplate] = [
        ChallengeTemplate(
            name: "Weekend Reader",
            icon: "📖",
            type: .articleCount,
            target: 20,
            duration: .threeDay,
            description: "Read 20 articles over a long weekend."
        ),
        ChallengeTemplate(
            name: "Weekly Deep Dive",
            icon: "🏊",
            type: .timeSpent,
            target: 120,
            duration: .oneWeek,
            description: "Spend 2 hours reading this week."
        ),
        ChallengeTemplate(
            name: "Feed Explorer",
            icon: "🧭",
            type: .feedDiversity,
            target: 10,
            duration: .twoWeek,
            description: "Read from 10 different feeds in 2 weeks."
        ),
        ChallengeTemplate(
            name: "Streak Builder",
            icon: "🔥",
            type: .streakDays,
            target: 7,
            duration: .oneWeek,
            description: "Read every day for a full week."
        ),
        ChallengeTemplate(
            name: "Monthly Marathon",
            icon: "🏃",
            type: .articleCount,
            target: 100,
            duration: .oneMonth,
            description: "Read 100 articles in 30 days."
        ),
        ChallengeTemplate(
            name: "Consistency Check",
            icon: "📅",
            type: .activeDays,
            target: 20,
            duration: .oneMonth,
            description: "Read on at least 20 of the next 30 days."
        ),
    ]

    // MARK: - Initialization

    init(calendar: Calendar = .current) {
        self.calendar = calendar
        load()
    }

    // MARK: - Challenge Creation

    /// Create a new reading challenge.
    ///
    /// - Parameters:
    ///   - name: User-chosen name for the challenge.
    ///   - type: What kind of reading activity to measure.
    ///   - target: Numeric target to reach.
    ///   - startDate: When the challenge begins (default: now).
    ///   - endDate: Deadline for completion.
    ///   - feedURL: For `.feedSpecific` type, the feed to focus on.
    ///   - icon: Emoji icon (default: "🎯").
    /// - Returns: The created challenge, or nil if validation fails.
    @discardableResult
    func createChallenge(
        name: String,
        type: ChallengeType,
        target: Int,
        startDate: Date = Date(),
        endDate: Date,
        feedURL: String? = nil,
        icon: String = "🎯"
    ) -> ReadingChallenge? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validation
        guard !trimmedName.isEmpty else { return nil }
        guard target > 0 && target <= ReadingChallengeManager.maxTarget else { return nil }
        guard endDate > startDate else { return nil }

        // Check active challenge limit
        let activeCount = challenges.filter { $0.status == .active }.count
        guard activeCount < ReadingChallengeManager.maxActiveChallenges else { return nil }

        // feedSpecific requires a feed URL
        if type == .feedSpecific && (feedURL == nil || feedURL!.isEmpty) {
            return nil
        }

        let challenge = ReadingChallenge(
            id: UUID().uuidString,
            name: trimmedName,
            type: type,
            target: target,
            progress: 0,
            createdAt: Date(),
            startDate: startDate,
            endDate: endDate,
            status: .active,
            completedAt: nil,
            feedURL: feedURL,
            icon: icon,
            distinctFeedURLs: [],
            activeDayStrings: [],
            longestStreak: 0,
            currentStreak: 0,
            lastActiveDay: nil
        )

        challenges.append(challenge)
        save()
        NotificationCenter.default.post(name: .readingChallengesDidChange, object: nil)
        return challenge
    }

    /// Create a challenge from a template.
    @discardableResult
    func createFromTemplate(_ template: ChallengeTemplate, startDate: Date = Date()) -> ReadingChallenge? {
        guard let durationSeconds = template.duration.seconds else { return nil }
        let endDate = startDate.addingTimeInterval(durationSeconds)
        return createChallenge(
            name: template.name,
            type: template.type,
            target: template.target,
            startDate: startDate,
            endDate: endDate,
            icon: template.icon
        )
    }

    // MARK: - Progress Recording

    /// Record a reading event that may advance active challenges.
    ///
    /// Call this when a user reads an article. The manager determines which
    /// active challenges are affected and updates their progress.
    ///
    /// - Parameters:
    ///   - feedURL: URL of the feed the article belongs to.
    ///   - feedName: Display name of the feed (for logging).
    ///   - minutesSpent: Time spent reading (for timeSpent challenges).
    ///   - date: When the reading occurred (default: now).
    func recordReading(
        feedURL: String,
        feedName: String = "",
        minutesSpent: Int = 0,
        date: Date = Date()
    ) {
        let dayString = dayFormatter.string(from: date)
        var changed = false

        for i in 0..<challenges.count {
            guard challenges[i].status == .active else { continue }
            guard date >= challenges[i].startDate else { continue }
            // Don't count readings past the challenge deadline — without
            // this check, readings recorded after expiry (but before
            // checkExpiration() runs) could inflate progress or even
            // flip a failed challenge to completed.
            guard date <= challenges[i].endDate else { continue }

            // Update auxiliary tracking regardless of type
            challenges[i].distinctFeedURLs.insert(feedURL)

            let isNewDay = !challenges[i].activeDayStrings.contains(dayString)
            if isNewDay {
                challenges[i].activeDayStrings.insert(dayString)
                updateStreak(index: i, dayString: dayString)
            }

            // Update type-specific progress
            switch challenges[i].type {
            case .articleCount:
                challenges[i].progress += 1
                changed = true

            case .timeSpent:
                challenges[i].progress += minutesSpent
                changed = true

            case .feedDiversity:
                challenges[i].progress = challenges[i].distinctFeedURLs.count
                changed = true

            case .streakDays:
                challenges[i].progress = challenges[i].longestStreak
                changed = true

            case .feedSpecific:
                if feedURL.lowercased() == challenges[i].feedURL?.lowercased() {
                    challenges[i].progress += 1
                    changed = true
                }

            case .activeDays:
                challenges[i].progress = challenges[i].activeDayStrings.count
                changed = true
            }

            // Check for completion
            if challenges[i].isTargetReached && challenges[i].status == .active {
                challenges[i].status = .completed
                challenges[i].completedAt = date
                NotificationCenter.default.post(
                    name: .readingChallengeCompleted,
                    object: nil,
                    userInfo: ["challengeId": challenges[i].id]
                )
            }
        }

        if changed {
            save()
            NotificationCenter.default.post(name: .readingChallengesDidChange, object: nil)
        }
    }

    // MARK: - Streak Tracking (private)

    /// Update the consecutive-day streak for a challenge.
    private func updateStreak(index: Int, dayString: String) {
        guard let lastDay = challenges[index].lastActiveDay else {
            challenges[index].currentStreak = 1
            challenges[index].longestStreak = max(challenges[index].longestStreak, 1)
            challenges[index].lastActiveDay = dayString
            return
        }

        // Check if this day is consecutive to the last active day
        guard let lastDate = dayFormatter.date(from: lastDay),
              let thisDate = dayFormatter.date(from: dayString) else {
            challenges[index].lastActiveDay = dayString
            return
        }

        let daysBetween = calendar.dateComponents([.day], from: lastDate, to: thisDate).day ?? 0

        if daysBetween == 1 {
            // Consecutive
            challenges[index].currentStreak += 1
        } else if daysBetween > 1 {
            // Gap — streak broken
            challenges[index].currentStreak = 1
        }
        // daysBetween == 0 means same day — no streak change

        challenges[index].longestStreak = max(
            challenges[index].longestStreak,
            challenges[index].currentStreak
        )
        challenges[index].lastActiveDay = dayString
    }

    // MARK: - Expiration Check

    /// Check all active challenges for expiration and mark them as failed.
    /// Call this periodically (e.g., on app launch or timer).
    ///
    /// - Parameter now: Current date (default: Date()).
    /// - Returns: Array of challenge IDs that just expired.
    @discardableResult
    func checkExpiration(now: Date = Date()) -> [String] {
        var expired: [String] = []

        for i in 0..<challenges.count {
            guard challenges[i].status == .active else { continue }
            if challenges[i].isExpired(now: now) && !challenges[i].isTargetReached {
                challenges[i].status = .failed
                expired.append(challenges[i].id)
            }
        }

        if !expired.isEmpty {
            save()
            NotificationCenter.default.post(name: .readingChallengesDidChange, object: nil)
        }

        return expired
    }

    // MARK: - Abandon

    /// Abandon an active challenge.
    /// - Returns: true if the challenge was found and abandoned.
    @discardableResult
    func abandonChallenge(id: String) -> Bool {
        guard let index = challenges.firstIndex(where: { $0.id == id && $0.status == .active }) else {
            return false
        }
        challenges[index].status = .abandoned
        save()
        NotificationCenter.default.post(name: .readingChallengesDidChange, object: nil)
        return true
    }

    // MARK: - Queries

    /// Get all active challenges.
    func activeChallenges() -> [ReadingChallenge] {
        return challenges.filter { $0.status == .active }
    }

    /// Get challenges by status.
    func challenges(withStatus status: ChallengeStatus) -> [ReadingChallenge] {
        return challenges.filter { $0.status == status }
    }

    /// Get a specific challenge by ID.
    func challenge(id: String) -> ReadingChallenge? {
        return challenges.first { $0.id == id }
    }

    /// Get completed challenges sorted by completion date (most recent first).
    func completedChallenges() -> [ReadingChallenge] {
        return challenges
            .filter { $0.status == .completed }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    /// Get the challenge closest to completion among active ones.
    func closestToCompletion() -> ReadingChallenge? {
        return activeChallenges()
            .max(by: { $0.percentComplete < $1.percentComplete })
    }

    /// Get the challenge closest to its deadline among active ones.
    func mostUrgent(now: Date = Date()) -> ReadingChallenge? {
        return activeChallenges()
            .filter { !$0.isExpired(now: now) }
            .min(by: { $0.timeRemaining(now: now) < $1.timeRemaining(now: now) })
    }

    // MARK: - Statistics

    /// Compute aggregate statistics across all challenges.
    func stats() -> ChallengeStats {
        let completed = challenges.filter { $0.status == .completed }
        let failed = challenges.filter { $0.status == .failed }
        let abandoned = challenges.filter { $0.status == .abandoned }
        let active = challenges.filter { $0.status == .active }

        let finished = completed.count + failed.count
        let completionRate = finished > 0 ? Double(completed.count) / Double(finished) : 0.0

        let avgPace: Double
        if completed.isEmpty {
            avgPace = 0.0
        } else {
            let paceSum = completed.reduce(0.0) { sum, c in
                sum + c.pace(now: c.completedAt ?? c.endDate)
            }
            avgPace = paceSum / Double(completed.count)
        }

        let bestStreak = challenges.map { $0.longestStreak }.max() ?? 0
        let mostArticles = challenges
            .filter { $0.type == .articleCount }
            .map { $0.progress }
            .max() ?? 0

        return ChallengeStats(
            totalCreated: challenges.count,
            totalCompleted: completed.count,
            totalFailed: failed.count,
            totalAbandoned: abandoned.count,
            activeCount: active.count,
            completionRate: completionRate,
            averagePaceAtCompletion: avgPace,
            bestStreak: bestStreak,
            mostArticlesInChallenge: mostArticles,
            leadingChallenge: closestToCompletion()
        )
    }

    // MARK: - Summary

    /// Generate a human-readable summary of a challenge.
    func summary(for challenge: ReadingChallenge, now: Date = Date()) -> String {
        var lines: [String] = []

        lines.append("\(challenge.icon) \(challenge.name)")
        lines.append("Type: \(challenge.type.label)")
        lines.append("Progress: \(challenge.progress)/\(challenge.target) \(challenge.type.targetUnit(value: challenge.target))")
        lines.append(String(format: "Completion: %.0f%%", challenge.percentComplete * 100))

        switch challenge.status {
        case .active:
            let remaining = challenge.timeRemaining(now: now)
            let days = Int(remaining / 86400)
            let hours = Int((remaining.truncatingRemainder(dividingBy: 86400)) / 3600)
            if days > 0 {
                lines.append("Time left: \(days)d \(hours)h")
            } else {
                lines.append("Time left: \(hours)h")
            }
            let paceValue = challenge.pace(now: now)
            if paceValue > 1.2 {
                lines.append("Pace: Ahead of schedule ⚡")
            } else if paceValue >= 0.8 {
                lines.append("Pace: On track ✅")
            } else {
                lines.append("Pace: Behind schedule ⚠️")
            }

        case .completed:
            lines.append("Status: Completed ✅")
            if let completedAt = challenge.completedAt {
                let elapsed = challenge.daysElapsed(now: completedAt)
                let total = challenge.totalDays()
                lines.append("Finished in \(elapsed)/\(total) days")
            }

        case .failed:
            lines.append("Status: Expired ❌")
            lines.append("Reached \(challenge.progress)/\(challenge.target)")

        case .abandoned:
            lines.append("Status: Abandoned 🏳️")
        }

        if challenge.type == .feedDiversity || challenge.distinctFeedURLs.count > 1 {
            lines.append("Feeds touched: \(challenge.distinctFeedURLs.count)")
        }
        if challenge.longestStreak > 1 {
            lines.append("Best streak: \(challenge.longestStreak) days")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - JSON Export

    /// Export all challenges as a JSON string.
    func exportJSON(prettyPrint: Bool = true) -> String? {
        let encoder = JSONCoding.iso8601Encoder
        if prettyPrint {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        guard let data = try? encoder.encode(challenges) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Import challenges from a JSON string (appends, does not replace).
    /// - Returns: Number of challenges imported (skips duplicates by ID).
    @discardableResult
    func importJSON(_ jsonString: String) -> Int {
        let decoder = JSONCoding.iso8601Decoder
        guard let data = jsonString.data(using: .utf8),
              let imported = try? decoder.decode([ReadingChallenge].self, from: data) else {
            return 0
        }

        let existingIDs = Set(challenges.map { $0.id })
        let newChallenges = imported.filter { !existingIDs.contains($0.id) }
        challenges.append(contentsOf: newChallenges)

        if !newChallenges.isEmpty {
            save()
            NotificationCenter.default.post(name: .readingChallengesDidChange, object: nil)
        }

        return newChallenges.count
    }

    // MARK: - Delete

    /// Remove a challenge by ID.
    /// - Returns: true if found and removed.
    @discardableResult
    func deleteChallenge(id: String) -> Bool {
        let before = challenges.count
        challenges.removeAll { $0.id == id }
        if challenges.count < before {
            save()
            NotificationCenter.default.post(name: .readingChallengesDidChange, object: nil)
            return true
        }
        return false
    }

    /// Remove all non-active challenges (completed, failed, abandoned).
    /// - Returns: Number of challenges removed.
    @discardableResult
    func clearHistory() -> Int {
        let before = challenges.count
        challenges.removeAll { $0.status != .active }
        let removed = before - challenges.count
        if removed > 0 {
            save()
            NotificationCenter.default.post(name: .readingChallengesDidChange, object: nil)
        }
        return removed
    }

    // MARK: - Reset

    /// Remove all challenges and reset to empty state.
    func reset() {
        challenges.removeAll()
        save()
        NotificationCenter.default.post(name: .readingChallengesDidChange, object: nil)
    }

    // MARK: - Persistence

    private func save() {
        store.save(challenges)
    }

    private func load() {
        if let loaded = store.load() {
            challenges = loaded
        }
    }
}
