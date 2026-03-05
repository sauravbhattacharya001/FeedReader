//
//  ReadingAchievementsManager.swift
//  FeedReader
//
//  Gamification layer: unlockable achievements/badges for reading milestones.
//  Tracks progress toward goals like article counts, streaks, diversity,
//  time-of-day patterns, and feed exploration. Integrates with existing
//  managers for automatic progress updates.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when an achievement is unlocked. UserInfo contains "achievement" key.
    static let achievementUnlocked = Notification.Name("ReadingAchievementUnlockedNotification")
    /// Posted when achievement progress updates.
    static let achievementProgressDidChange = Notification.Name("ReadingAchievementProgressDidChangeNotification")
}

// MARK: - Models

/// Category of achievement.
enum AchievementCategory: String, Codable, CaseIterable {
    case volume       // Article count milestones
    case streak       // Consecutive day streaks
    case diversity    // Reading across different feeds/topics
    case speed        // Reading pace achievements
    case exploration  // Discovering new feeds
    case dedication   // Time-based commitments
    case social       // Sharing and collections
    case mastery      // Expert-level accomplishments
}

/// Rarity tier for achievements.
enum AchievementRarity: String, Codable, CaseIterable, Comparable {
    case common
    case uncommon
    case rare
    case epic
    case legendary

    private var sortOrder: Int {
        switch self {
        case .common: return 0
        case .uncommon: return 1
        case .rare: return 2
        case .epic: return 3
        case .legendary: return 4
        }
    }

    static func < (lhs: AchievementRarity, rhs: AchievementRarity) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

/// Definition of an achievement.
struct AchievementDefinition: Codable, Equatable {
    let id: String
    let name: String
    let description: String
    let emoji: String
    let category: AchievementCategory
    let rarity: AchievementRarity
    let targetValue: Int
    let isSecret: Bool

    init(id: String, name: String, description: String, emoji: String,
         category: AchievementCategory, rarity: AchievementRarity,
         targetValue: Int, isSecret: Bool = false) {
        self.id = id
        self.name = name
        self.description = description
        self.emoji = emoji
        self.category = category
        self.rarity = rarity
        self.targetValue = targetValue
        self.isSecret = isSecret
    }
}

/// Progress toward a specific achievement.
struct AchievementProgress: Codable, Equatable {
    let achievementId: String
    var currentValue: Int
    var isUnlocked: Bool
    var unlockedDate: Date?

    var percentage: Double {
        guard let def = AchievementRegistry.definition(for: achievementId) else { return 0 }
        guard def.targetValue > 0 else { return isUnlocked ? 100.0 : 0 }
        return min(100.0, Double(currentValue) / Double(def.targetValue) * 100.0)
    }

    init(achievementId: String, currentValue: Int = 0, isUnlocked: Bool = false, unlockedDate: Date? = nil) {
        self.achievementId = achievementId
        self.currentValue = currentValue
        self.isUnlocked = isUnlocked
        self.unlockedDate = unlockedDate
    }
}

/// Snapshot of reading activity for achievement evaluation.
struct ReadingActivitySnapshot {
    var totalArticlesRead: Int = 0
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var uniqueFeedsRead: Int = 0
    var uniqueCategoriesRead: Int = 0
    var articlesToday: Int = 0
    var articlesThisWeek: Int = 0
    var articlesThisMonth: Int = 0
    var nightOwlArticles: Int = 0       // Read between 10pm-4am
    var earlyBirdArticles: Int = 0      // Read between 5am-7am
    var weekendArticles: Int = 0
    var bookmarkedArticles: Int = 0
    var sharedArticles: Int = 0
    var collectionsCreated: Int = 0
    var totalReadingMinutes: Int = 0
    var longestSessionMinutes: Int = 0
    var feedsSubscribed: Int = 0
    var searchesPerformed: Int = 0
    var tagsUsed: Int = 0
    var highlightsMade: Int = 0
    var notesWritten: Int = 0
}

/// Summary report of all achievements.
struct AchievementReport {
    let totalAchievements: Int
    let unlockedCount: Int
    let lockedCount: Int
    let completionPercentage: Double
    let pointsEarned: Int
    let maxPoints: Int
    let byCategory: [AchievementCategory: CategoryStats]
    let recentUnlocks: [AchievementProgress]
    let nearestToUnlock: [AchievementProgress]
    let rarityBreakdown: [AchievementRarity: RarityStats]

    struct CategoryStats {
        let total: Int
        let unlocked: Int
        let percentage: Double
    }

    struct RarityStats {
        let total: Int
        let unlocked: Int
        let points: Int
    }

    func textSummary() -> String {
        var lines: [String] = []
        lines.append("=== Reading Achievements Report ===")
        lines.append("")
        lines.append("Progress: \(unlockedCount)/\(totalAchievements) (\(String(format: "%.1f", completionPercentage))%)")
        lines.append("Points: \(pointsEarned)/\(maxPoints)")
        lines.append("")

        lines.append("By Category:")
        for cat in AchievementCategory.allCases {
            if let stats = byCategory[cat] {
                lines.append("  \(cat.rawValue): \(stats.unlocked)/\(stats.total) (\(String(format: "%.0f", stats.percentage))%)")
            }
        }
        lines.append("")

        lines.append("By Rarity:")
        for rarity in AchievementRarity.allCases {
            if let stats = rarityBreakdown[rarity] {
                lines.append("  \(rarity.rawValue): \(stats.unlocked)/\(stats.total) (\(stats.points) pts)")
            }
        }

        if !recentUnlocks.isEmpty {
            lines.append("")
            lines.append("Recent Unlocks:")
            for p in recentUnlocks.prefix(5) {
                if let def = AchievementRegistry.definition(for: p.achievementId) {
                    lines.append("  \(def.emoji) \(def.name)")
                }
            }
        }

        if !nearestToUnlock.isEmpty {
            lines.append("")
            lines.append("Almost There:")
            for p in nearestToUnlock.prefix(5) {
                if let def = AchievementRegistry.definition(for: p.achievementId) {
                    lines.append("  \(def.emoji) \(def.name) — \(String(format: "%.0f", p.percentage))%")
                }
            }
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Achievement Registry

/// Static registry of all available achievements.
struct AchievementRegistry {
    private static var definitions: [String: AchievementDefinition] = {
        var map: [String: AchievementDefinition] = [:]
        for def in allDefinitions {
            map[def.id] = def
        }
        return map
    }()

    static func definition(for id: String) -> AchievementDefinition? {
        definitions[id]
    }

    static var all: [AchievementDefinition] {
        allDefinitions
    }

    static var count: Int { allDefinitions.count }

    /// Points awarded per rarity tier.
    static func points(for rarity: AchievementRarity) -> Int {
        switch rarity {
        case .common: return 10
        case .uncommon: return 25
        case .rare: return 50
        case .epic: return 100
        case .legendary: return 250
        }
    }

    // MARK: - All Achievement Definitions

    private static let allDefinitions: [AchievementDefinition] = [
        // Volume
        AchievementDefinition(id: "vol_first", name: "First Steps", description: "Read your first article", emoji: "📖", category: .volume, rarity: .common, targetValue: 1),
        AchievementDefinition(id: "vol_10", name: "Getting Started", description: "Read 10 articles", emoji: "📚", category: .volume, rarity: .common, targetValue: 10),
        AchievementDefinition(id: "vol_50", name: "Avid Reader", description: "Read 50 articles", emoji: "📕", category: .volume, rarity: .uncommon, targetValue: 50),
        AchievementDefinition(id: "vol_100", name: "Bookworm", description: "Read 100 articles", emoji: "🐛", category: .volume, rarity: .uncommon, targetValue: 100),
        AchievementDefinition(id: "vol_500", name: "Knowledge Seeker", description: "Read 500 articles", emoji: "🔍", category: .volume, rarity: .rare, targetValue: 500),
        AchievementDefinition(id: "vol_1000", name: "Scholar", description: "Read 1,000 articles", emoji: "🎓", category: .volume, rarity: .epic, targetValue: 1000),
        AchievementDefinition(id: "vol_5000", name: "Omnivore", description: "Read 5,000 articles", emoji: "🌟", category: .volume, rarity: .legendary, targetValue: 5000),

        // Streaks
        AchievementDefinition(id: "str_3", name: "Three-Peat", description: "Maintain a 3-day reading streak", emoji: "🔥", category: .streak, rarity: .common, targetValue: 3),
        AchievementDefinition(id: "str_7", name: "Week Warrior", description: "Read every day for a week", emoji: "⚔️", category: .streak, rarity: .uncommon, targetValue: 7),
        AchievementDefinition(id: "str_14", name: "Fortnight Force", description: "14-day reading streak", emoji: "💪", category: .streak, rarity: .uncommon, targetValue: 14),
        AchievementDefinition(id: "str_30", name: "Monthly Maven", description: "30-day reading streak", emoji: "📅", category: .streak, rarity: .rare, targetValue: 30),
        AchievementDefinition(id: "str_100", name: "Centurion", description: "100-day reading streak", emoji: "🏛️", category: .streak, rarity: .epic, targetValue: 100),
        AchievementDefinition(id: "str_365", name: "Year of Reading", description: "365-day reading streak", emoji: "🏆", category: .streak, rarity: .legendary, targetValue: 365),

        // Diversity
        AchievementDefinition(id: "div_3feeds", name: "Variety Pack", description: "Read from 3 different feeds", emoji: "🎨", category: .diversity, rarity: .common, targetValue: 3),
        AchievementDefinition(id: "div_10feeds", name: "Well-Rounded", description: "Read from 10 different feeds", emoji: "🌐", category: .diversity, rarity: .uncommon, targetValue: 10),
        AchievementDefinition(id: "div_25feeds", name: "Eclectic Tastes", description: "Read from 25 different feeds", emoji: "🦋", category: .diversity, rarity: .rare, targetValue: 25),
        AchievementDefinition(id: "div_5cats", name: "Category Hopper", description: "Read from 5 different categories", emoji: "🗂️", category: .diversity, rarity: .uncommon, targetValue: 5),
        AchievementDefinition(id: "div_10cats", name: "Renaissance Reader", description: "Read from 10 categories", emoji: "🎭", category: .diversity, rarity: .rare, targetValue: 10),

        // Speed / Dedication
        AchievementDefinition(id: "ded_60min", name: "Deep Dive", description: "Read for 60 minutes in one session", emoji: "🤿", category: .dedication, rarity: .uncommon, targetValue: 60),
        AchievementDefinition(id: "ded_10day", name: "Daily Dozen", description: "Read 10 articles in a single day", emoji: "🔟", category: .dedication, rarity: .uncommon, targetValue: 10),
        AchievementDefinition(id: "ded_25day", name: "Marathon Reader", description: "Read 25 articles in a single day", emoji: "🏃", category: .dedication, rarity: .rare, targetValue: 25),
        AchievementDefinition(id: "ded_500min", name: "Time Invested", description: "Accumulate 500 minutes of reading", emoji: "⏱️", category: .dedication, rarity: .rare, targetValue: 500),
        AchievementDefinition(id: "ded_2000min", name: "Lifetime Reader", description: "2,000 minutes of reading time", emoji: "⌛", category: .dedication, rarity: .epic, targetValue: 2000),

        // Exploration
        AchievementDefinition(id: "exp_sub5", name: "Feed Collector", description: "Subscribe to 5 feeds", emoji: "📡", category: .exploration, rarity: .common, targetValue: 5),
        AchievementDefinition(id: "exp_sub20", name: "Feed Enthusiast", description: "Subscribe to 20 feeds", emoji: "📻", category: .exploration, rarity: .uncommon, targetValue: 20),
        AchievementDefinition(id: "exp_sub50", name: "Feed Connoisseur", description: "Subscribe to 50 feeds", emoji: "🏅", category: .exploration, rarity: .rare, targetValue: 50),
        AchievementDefinition(id: "exp_search10", name: "Curious Mind", description: "Perform 10 searches", emoji: "🔎", category: .exploration, rarity: .common, targetValue: 10),

        // Social
        AchievementDefinition(id: "soc_share1", name: "Sharing is Caring", description: "Share your first article", emoji: "💌", category: .social, rarity: .common, targetValue: 1),
        AchievementDefinition(id: "soc_share25", name: "Town Crier", description: "Share 25 articles", emoji: "📢", category: .social, rarity: .uncommon, targetValue: 25),
        AchievementDefinition(id: "soc_bookmark10", name: "Collector", description: "Bookmark 10 articles", emoji: "🔖", category: .social, rarity: .common, targetValue: 10),
        AchievementDefinition(id: "soc_collection3", name: "Curator", description: "Create 3 article collections", emoji: "🗃️", category: .social, rarity: .uncommon, targetValue: 3),
        AchievementDefinition(id: "soc_highlight50", name: "Highlighter Pro", description: "Make 50 highlights", emoji: "✨", category: .social, rarity: .rare, targetValue: 50),
        AchievementDefinition(id: "soc_notes25", name: "Annotator", description: "Write 25 article notes", emoji: "📝", category: .social, rarity: .uncommon, targetValue: 25),

        // Mastery
        AchievementDefinition(id: "mas_allcats", name: "Jack of All Trades", description: "Read from every category", emoji: "🃏", category: .mastery, rarity: .epic, targetValue: 1),
        AchievementDefinition(id: "mas_tags20", name: "Tag Master", description: "Use 20 different tags", emoji: "🏷️", category: .mastery, rarity: .rare, targetValue: 20),

        // Speed
        AchievementDefinition(id: "spd_fast5", name: "Speed Reader", description: "Read 5 articles in under 30 minutes", emoji: "⚡", category: .speed, rarity: .uncommon, targetValue: 5),

        // Secret achievements
        AchievementDefinition(id: "sec_nightowl", name: "Night Owl", description: "Read 20 articles between 10 PM and 4 AM", emoji: "🦉", category: .dedication, rarity: .rare, targetValue: 20, isSecret: true),
        AchievementDefinition(id: "sec_earlybird", name: "Early Bird", description: "Read 10 articles between 5 AM and 7 AM", emoji: "🐦", category: .dedication, rarity: .rare, targetValue: 10, isSecret: true),
        AchievementDefinition(id: "sec_weekend", name: "Weekend Warrior", description: "Read 50 articles on weekends", emoji: "🎉", category: .dedication, rarity: .uncommon, targetValue: 50, isSecret: true),
    ]
}

// MARK: - ReadingAchievementsManager

class ReadingAchievementsManager {

    // MARK: - Singleton

    static let shared = ReadingAchievementsManager()

    // MARK: - Constants

    private static let userDefaultsKey = "ReadingAchievementsManager.progress"

    // MARK: - Properties

    /// Achievement ID → progress
    private var progressMap: [String: AchievementProgress]

    // MARK: - Init

    init() {
        progressMap = [:]
        loadProgress()
        // Ensure all achievements have a progress entry
        for def in AchievementRegistry.all {
            if progressMap[def.id] == nil {
                progressMap[def.id] = AchievementProgress(achievementId: def.id)
            }
        }
    }

    // MARK: - Public API

    /// Get progress for a specific achievement.
    func progress(for achievementId: String) -> AchievementProgress? {
        progressMap[achievementId]
    }

    /// Get all progress entries.
    func allProgress() -> [AchievementProgress] {
        Array(progressMap.values)
    }

    /// Get unlocked achievements.
    func unlockedAchievements() -> [AchievementProgress] {
        progressMap.values.filter { $0.isUnlocked }.sorted {
            ($0.unlockedDate ?? .distantPast) > ($1.unlockedDate ?? .distantPast)
        }
    }

    /// Get locked achievements (excludes secrets that haven't started).
    func lockedAchievements(includeSecrets: Bool = false) -> [AchievementProgress] {
        progressMap.values.filter { progress in
            guard !progress.isUnlocked else { return false }
            if !includeSecrets, let def = AchievementRegistry.definition(for: progress.achievementId), def.isSecret {
                return progress.currentValue > 0  // Only show secret if user has started it
            }
            return true
        }
    }

    /// Get achievements by category.
    func achievements(in category: AchievementCategory) -> [AchievementProgress] {
        progressMap.values.filter { p in
            AchievementRegistry.definition(for: p.achievementId)?.category == category
        }.sorted { $0.percentage > $1.percentage }
    }

    /// Get achievements by rarity.
    func achievements(ofRarity rarity: AchievementRarity) -> [AchievementProgress] {
        progressMap.values.filter { p in
            AchievementRegistry.definition(for: p.achievementId)?.rarity == rarity
        }
    }

    /// Total points earned.
    func totalPoints() -> Int {
        progressMap.values.reduce(0) { total, p in
            guard p.isUnlocked, let def = AchievementRegistry.definition(for: p.achievementId) else { return total }
            return total + AchievementRegistry.points(for: def.rarity)
        }
    }

    /// Maximum possible points.
    func maxPoints() -> Int {
        AchievementRegistry.all.reduce(0) { $0 + AchievementRegistry.points(for: $1.rarity) }
    }

    /// Achievements closest to unlocking (by percentage).
    func nearestToUnlock(limit: Int = 5) -> [AchievementProgress] {
        progressMap.values
            .filter { !$0.isUnlocked && $0.currentValue > 0 }
            .sorted { $0.percentage > $1.percentage }
            .prefix(limit)
            .map { $0 }
    }

    /// Update progress from a reading activity snapshot.
    /// Returns array of newly unlocked achievement IDs.
    @discardableResult
    func updateProgress(from snapshot: ReadingActivitySnapshot, now: Date = Date()) -> [String] {
        var newlyUnlocked: [String] = []

        let updates: [(String, Int)] = [
            // Volume
            ("vol_first", snapshot.totalArticlesRead),
            ("vol_10", snapshot.totalArticlesRead),
            ("vol_50", snapshot.totalArticlesRead),
            ("vol_100", snapshot.totalArticlesRead),
            ("vol_500", snapshot.totalArticlesRead),
            ("vol_1000", snapshot.totalArticlesRead),
            ("vol_5000", snapshot.totalArticlesRead),

            // Streaks (use longest, not current)
            ("str_3", max(snapshot.currentStreak, snapshot.longestStreak)),
            ("str_7", max(snapshot.currentStreak, snapshot.longestStreak)),
            ("str_14", max(snapshot.currentStreak, snapshot.longestStreak)),
            ("str_30", max(snapshot.currentStreak, snapshot.longestStreak)),
            ("str_100", max(snapshot.currentStreak, snapshot.longestStreak)),
            ("str_365", max(snapshot.currentStreak, snapshot.longestStreak)),

            // Diversity
            ("div_3feeds", snapshot.uniqueFeedsRead),
            ("div_10feeds", snapshot.uniqueFeedsRead),
            ("div_25feeds", snapshot.uniqueFeedsRead),
            ("div_5cats", snapshot.uniqueCategoriesRead),
            ("div_10cats", snapshot.uniqueCategoriesRead),

            // Dedication
            ("ded_60min", snapshot.longestSessionMinutes),
            ("ded_10day", snapshot.articlesToday),
            ("ded_25day", snapshot.articlesToday),
            ("ded_500min", snapshot.totalReadingMinutes),
            ("ded_2000min", snapshot.totalReadingMinutes),

            // Exploration
            ("exp_sub5", snapshot.feedsSubscribed),
            ("exp_sub20", snapshot.feedsSubscribed),
            ("exp_sub50", snapshot.feedsSubscribed),
            ("exp_search10", snapshot.searchesPerformed),

            // Social
            ("soc_share1", snapshot.sharedArticles),
            ("soc_share25", snapshot.sharedArticles),
            ("soc_bookmark10", snapshot.bookmarkedArticles),
            ("soc_collection3", snapshot.collectionsCreated),
            ("soc_highlight50", snapshot.highlightsMade),
            ("soc_notes25", snapshot.notesWritten),

            // Mastery
            ("mas_tags20", snapshot.tagsUsed),

            // Secret
            ("sec_nightowl", snapshot.nightOwlArticles),
            ("sec_earlybird", snapshot.earlyBirdArticles),
            ("sec_weekend", snapshot.weekendArticles),
        ]

        for (id, value) in updates {
            if let unlocked = setProgress(id: id, value: value, now: now) {
                if unlocked { newlyUnlocked.append(id) }
            }
        }

        // Special: mas_allcats — check if all categories are read
        if snapshot.uniqueCategoriesRead >= 10 {
            if let unlocked = setProgress(id: "mas_allcats", value: 1, now: now) {
                if unlocked { newlyUnlocked.append("mas_allcats") }
            }
        }

        if !newlyUnlocked.isEmpty {
            saveProgress()
        }

        return newlyUnlocked
    }

    /// Manually increment progress for a specific achievement.
    @discardableResult
    func incrementProgress(for achievementId: String, by amount: Int = 1, now: Date = Date()) -> Bool {
        guard var p = progressMap[achievementId], !p.isUnlocked else { return false }
        let newValue = p.currentValue + amount
        p.currentValue = newValue

        if let def = AchievementRegistry.definition(for: achievementId), newValue >= def.targetValue {
            p.isUnlocked = true
            p.unlockedDate = now
            progressMap[achievementId] = p
            saveProgress()
            NotificationCenter.default.post(name: .achievementUnlocked, object: self, userInfo: ["achievement": def])
            return true
        }

        progressMap[achievementId] = p
        saveProgress()
        NotificationCenter.default.post(name: .achievementProgressDidChange, object: self)
        return false
    }

    /// Generate a comprehensive report.
    func generateReport() -> AchievementReport {
        let all = AchievementRegistry.all
        let unlocked = unlockedAchievements()
        let points = totalPoints()
        let maxPts = maxPoints()

        var byCategory: [AchievementCategory: AchievementReport.CategoryStats] = [:]
        for cat in AchievementCategory.allCases {
            let catDefs = all.filter { $0.category == cat }
            let catUnlocked = catDefs.filter { progressMap[$0.id]?.isUnlocked == true }
            let pct = catDefs.isEmpty ? 0 : Double(catUnlocked.count) / Double(catDefs.count) * 100.0
            byCategory[cat] = AchievementReport.CategoryStats(
                total: catDefs.count, unlocked: catUnlocked.count, percentage: pct
            )
        }

        var byRarity: [AchievementRarity: AchievementReport.RarityStats] = [:]
        for rarity in AchievementRarity.allCases {
            let rarDefs = all.filter { $0.rarity == rarity }
            let rarUnlocked = rarDefs.filter { progressMap[$0.id]?.isUnlocked == true }
            let pts = rarUnlocked.count * AchievementRegistry.points(for: rarity)
            byRarity[rarity] = AchievementReport.RarityStats(
                total: rarDefs.count, unlocked: rarUnlocked.count, points: pts
            )
        }

        return AchievementReport(
            totalAchievements: all.count,
            unlockedCount: unlocked.count,
            lockedCount: all.count - unlocked.count,
            completionPercentage: all.isEmpty ? 0 : Double(unlocked.count) / Double(all.count) * 100.0,
            pointsEarned: points,
            maxPoints: maxPts,
            byCategory: byCategory,
            recentUnlocks: Array(unlocked.prefix(5)),
            nearestToUnlock: nearestToUnlock(),
            rarityBreakdown: byRarity
        )
    }

    /// Reset all progress.
    func resetAll() {
        for def in AchievementRegistry.all {
            progressMap[def.id] = AchievementProgress(achievementId: def.id)
        }
        saveProgress()
        NotificationCenter.default.post(name: .achievementProgressDidChange, object: self)
    }

    /// Export progress as JSON data.
    func exportJSON() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(Array(progressMap.values))
    }

    /// Import progress from JSON data. Returns number of entries imported.
    @discardableResult
    func importJSON(_ data: Data) -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let entries = try? decoder.decode([AchievementProgress].self, from: data) else { return 0 }
        var count = 0
        for entry in entries {
            guard AchievementRegistry.definition(for: entry.achievementId) != nil else { continue }
            progressMap[entry.achievementId] = entry
            count += 1
        }
        saveProgress()
        return count
    }

    // MARK: - Private Helpers

    /// Set progress, returns nil if achievement unknown, true if newly unlocked, false otherwise.
    private func setProgress(id: String, value: Int, now: Date) -> Bool? {
        guard let def = AchievementRegistry.definition(for: id) else { return nil }
        guard var p = progressMap[id] else { return nil }
        guard !p.isUnlocked else { return false }

        p.currentValue = value
        if value >= def.targetValue {
            p.isUnlocked = true
            p.unlockedDate = now
            progressMap[id] = p
            NotificationCenter.default.post(name: .achievementUnlocked, object: self, userInfo: ["achievement": def])
            return true
        }
        progressMap[id] = p
        return false
    }

    // MARK: - Persistence

    private func saveProgress() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(Array(progressMap.values)) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }

    private func loadProgress() {
        guard let data = UserDefaults.standard.data(forKey: Self.userDefaultsKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let entries = try? decoder.decode([AchievementProgress].self, from: data) {
            for entry in entries {
                progressMap[entry.achievementId] = entry
            }
        }
    }
}
