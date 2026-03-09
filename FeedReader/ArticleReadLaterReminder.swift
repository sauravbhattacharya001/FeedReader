//
//  ArticleReadLaterReminder.swift
//  FeedReader
//
//  Smart reminder system for saved-but-unread articles. Unlike
//  ArticleSpacedReview (spaced repetition for retention), this
//  system helps users actually get to articles they saved but
//  haven't read yet.
//
//  Key features:
//  - Save articles for later with priority levels
//  - Configurable reminder intervals per priority
//  - Snooze reminders with presets or custom dates
//  - Auto-expiration after 90 days of inactivity
//  - Auto-escalation when items are ignored too long
//  - Tag and search saved items
//  - Statistics (completion rate, snooze count, etc.)
//  - Export as JSON or Markdown
//
//  Persistence: JSON file in Documents directory.
//  Fully offline — no network, no dependencies beyond Foundation.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when read-later items are added, removed, or status-changed.
    static let readLaterDidChange = Notification.Name("ReadLaterDidChangeNotification")
    /// Posted when a reminder batch is generated.
    static let readLaterRemindersGenerated = Notification.Name("ReadLaterRemindersGeneratedNotification")
}

// MARK: - ReminderPriority

/// Priority level that determines reminder frequency.
enum ReminderPriority: Int, Codable, CaseIterable, Comparable, CustomStringConvertible {
    case low = 0       // Remind weekly
    case normal = 1    // Remind every 3 days
    case high = 2      // Remind daily
    case urgent = 3    // Remind every 4 hours

    var description: String { label }

    var label: String {
        switch self {
        case .low:    return "Low"
        case .normal: return "Normal"
        case .high:   return "High"
        case .urgent: return "Urgent"
        }
    }

    /// Default reminder interval in seconds.
    var defaultInterval: TimeInterval {
        switch self {
        case .low:    return 7 * 24 * 3600   // 7 days
        case .normal: return 3 * 24 * 3600   // 3 days (72 hours)
        case .high:   return 24 * 3600       // 1 day
        case .urgent: return 4 * 3600        // 4 hours
        }
    }

    /// The next priority level up, or nil if already urgent.
    var escalated: ReminderPriority? {
        switch self {
        case .low:    return .normal
        case .normal: return .high
        case .high:   return .urgent
        case .urgent: return nil
        }
    }

    static func < (lhs: ReminderPriority, rhs: ReminderPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - ReminderStatus

/// Lifecycle status of a read-later item.
enum ReminderStatus: String, Codable, CaseIterable {
    case pending    // Waiting to be read
    case snoozed    // Temporarily silenced
    case completed  // User read it
    case dismissed  // User chose to skip it
    case expired    // Auto-expired after 90 days
}

// MARK: - SnoozePreset

/// Preset durations for snoozing a reminder.
enum SnoozePreset: String, CaseIterable, CustomStringConvertible {
    case oneHour    = "1 Hour"
    case fourHours  = "4 Hours"
    case tomorrow   = "Tomorrow"
    case nextWeek   = "Next Week"
    case nextMonth  = "Next Month"

    var description: String { rawValue }

    /// Calculate the snooze-until date from a given start date.
    func snoozeDate(from date: Date) -> Date {
        switch self {
        case .oneHour:   return date.addingTimeInterval(3600)
        case .fourHours: return date.addingTimeInterval(4 * 3600)
        case .tomorrow:  return date.addingTimeInterval(24 * 3600)
        case .nextWeek:  return date.addingTimeInterval(7 * 24 * 3600)
        case .nextMonth: return date.addingTimeInterval(30 * 24 * 3600)
        }
    }
}

// MARK: - ReadLaterItem

/// A single article saved for later reading.
struct ReadLaterItem: Codable, Equatable {
    /// Unique identifier.
    let id: String
    /// Article URL (also used for dedup).
    let articleLink: String
    /// Article title for display.
    let articleTitle: String
    /// Feed name for context.
    let feedName: String
    /// When the item was saved.
    let savedAt: Date
    /// Current priority level.
    var priority: ReminderPriority
    /// Current lifecycle status.
    var status: ReminderStatus
    /// When the next reminder should fire.
    var nextReminderDate: Date
    /// How many times this item has been snoozed.
    var snoozeCount: Int
    /// User-provided notes/context.
    var notes: String?
    /// When the item was completed (read).
    var completedAt: Date?
    /// When the item was last reminded.
    var lastRemindedAt: Date?
    /// Lowercase tags for categorization.
    var tags: [String]

    /// Maximum number of times an item can be snoozed.
    static let maxSnoozes = 10
    /// Auto-expire after this many days of inactivity.
    static let expirationDays = 90

    /// Whether this item is due for a reminder now.
    func isDue(at now: Date = Date()) -> Bool {
        guard status == .pending || status == .snoozed else { return false }
        return now >= nextReminderDate
    }

    /// Whether this item has exceeded the expiration window.
    func isExpired(at now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(savedAt)
        return age > Double(ReadLaterItem.expirationDays) * 24 * 3600
    }

    /// Age of this item in fractional days.
    func ageInDays(at now: Date = Date()) -> Double {
        now.timeIntervalSince(savedAt) / (24 * 3600)
    }

    static func == (lhs: ReadLaterItem, rhs: ReadLaterItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - ReminderBatch

/// A batch of due reminders grouped by priority.
struct ReminderBatch {
    let urgent: [ReadLaterItem]
    let high: [ReadLaterItem]
    let normal: [ReadLaterItem]
    let low: [ReadLaterItem]
    let generatedAt: Date

    var totalCount: Int { urgent.count + high.count + normal.count + low.count }
    var isEmpty: Bool { totalCount == 0 }
}

// MARK: - ReminderStats

/// Aggregate statistics about the read-later queue.
struct ReminderStats {
    let totalItems: Int
    let pendingCount: Int
    let snoozedCount: Int
    let completedCount: Int
    let dismissedCount: Int
    let expiredCount: Int
    let completionRate: Double
    let averageAgeInDays: Double
    let totalSnoozes: Int
    let topTags: [(tag: String, count: Int)]
    let itemsByPriority: [ReminderPriority: Int]
}

// MARK: - ArticleReadLaterReminder

/// Manages a queue of articles saved for later reading with smart reminders.
class ArticleReadLaterReminder {

    // MARK: - Storage

    private var items: [ReadLaterItem] = []
    private let fileManager = FileManager.default

    private var archiveURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("ReadLaterReminders.json")
    }

    // MARK: - Init

    init() {
        load()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: archiveURL),
              let decoded = try? JSONDecoder().decode([ReadLaterItem].self, from: data) else {
            return
        }
        items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: archiveURL, options: .atomic)
        NotificationCenter.default.post(name: .readLaterDidChange, object: self)
    }

    // MARK: - Save / Remove

    /// Save an article for later reading.
    /// Returns the created item, or nil if the link is already saved.
    @discardableResult
    func saveForLater(link: String, title: String, feedName: String = "",
                      priority: ReminderPriority = .normal, notes: String? = nil,
                      tags: [String] = [], at now: Date = Date()) -> ReadLaterItem? {
        guard !items.contains(where: { $0.articleLink == link }) else { return nil }

        let cleanTags = tags.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                            .filter { !$0.isEmpty }

        let item = ReadLaterItem(
            id: UUID().uuidString,
            articleLink: link,
            articleTitle: title,
            feedName: feedName,
            savedAt: now,
            priority: priority,
            status: .pending,
            nextReminderDate: now.addingTimeInterval(priority.defaultInterval),
            snoozeCount: 0,
            notes: notes,
            completedAt: nil,
            lastRemindedAt: nil,
            tags: cleanTags
        )
        items.append(item)
        save()
        return item
    }

    /// Remove an item by its unique id. Returns true if removed.
    @discardableResult
    func removeItem(id: String) -> Bool {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return false }
        items.remove(at: idx)
        save()
        return true
    }

    /// Remove an item by article link. Returns true if removed.
    @discardableResult
    func removeItem(link: String) -> Bool {
        guard let idx = items.firstIndex(where: { $0.articleLink == link }) else { return false }
        items.remove(at: idx)
        save()
        return true
    }

    /// Remove all items.
    func clearAll() {
        items.removeAll()
        save()
    }

    // MARK: - Status Updates

    /// Mark an item as completed (read). Returns false if already completed.
    @discardableResult
    func markCompleted(id: String, at now: Date = Date()) -> Bool {
        guard let idx = items.firstIndex(where: { $0.id == id }),
              items[idx].status != .completed else { return false }
        items[idx].status = .completed
        items[idx].completedAt = now
        save()
        return true
    }

    /// Mark an item as completed by link.
    @discardableResult
    func markCompleted(link: String, at now: Date = Date()) -> Bool {
        guard let idx = items.firstIndex(where: { $0.articleLink == link }),
              items[idx].status != .completed else { return false }
        items[idx].status = .completed
        items[idx].completedAt = now
        save()
        return true
    }

    /// Dismiss an item (skip it). Returns false if already completed.
    @discardableResult
    func dismiss(id: String) -> Bool {
        guard let idx = items.firstIndex(where: { $0.id == id }),
              items[idx].status != .completed else { return false }
        items[idx].status = .dismissed
        save()
        return true
    }

    // MARK: - Snooze

    /// Snooze a reminder using a preset duration. Returns false if not snoozeable.
    @discardableResult
    func snooze(id: String, preset: SnoozePreset, from now: Date = Date()) -> Bool {
        guard let idx = items.firstIndex(where: { $0.id == id }),
              items[idx].status == .pending || items[idx].status == .snoozed,
              items[idx].snoozeCount < ReadLaterItem.maxSnoozes else { return false }
        items[idx].status = .snoozed
        items[idx].snoozeCount += 1
        items[idx].nextReminderDate = preset.snoozeDate(from: now)
        save()
        return true
    }

    /// Snooze a reminder until a specific date. Returns false if date is in the past.
    @discardableResult
    func snoozeUntil(id: String, date: Date, from now: Date = Date()) -> Bool {
        guard date > now else { return false }
        guard let idx = items.firstIndex(where: { $0.id == id }),
              items[idx].status == .pending || items[idx].status == .snoozed,
              items[idx].snoozeCount < ReadLaterItem.maxSnoozes else { return false }
        items[idx].status = .snoozed
        items[idx].snoozeCount += 1
        items[idx].nextReminderDate = date
        save()
        return true
    }

    // MARK: - Priority & Tags

    /// Update an item's priority. Returns false if item not found.
    @discardableResult
    func updatePriority(id: String, to priority: ReminderPriority) -> Bool {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return false }
        items[idx].priority = priority
        save()
        return true
    }

    /// Update an item's notes. Returns false if item not found.
    @discardableResult
    func updateNotes(id: String, notes: String?) -> Bool {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return false }
        items[idx].notes = notes
        save()
        return true
    }

    /// Add a tag to an item. Returns false if already tagged or not found.
    @discardableResult
    func addTag(id: String, tag: String) -> Bool {
        let normalized = tag.trimmingCharacters(in: .whitespaces).lowercased()
        guard !normalized.isEmpty,
              let idx = items.firstIndex(where: { $0.id == id }),
              !items[idx].tags.contains(normalized) else { return false }
        items[idx].tags.append(normalized)
        save()
        return true
    }

    /// Remove a tag from an item. Returns false if tag not present or item not found.
    @discardableResult
    func removeTag(id: String, tag: String) -> Bool {
        let normalized = tag.trimmingCharacters(in: .whitespaces).lowercased()
        guard let idx = items.firstIndex(where: { $0.id == id }),
              let tagIdx = items[idx].tags.firstIndex(of: normalized) else { return false }
        items[idx].tags.remove(at: tagIdx)
        save()
        return true
    }

    // MARK: - Queries

    /// Look up an item by its unique id.
    func item(withId id: String) -> ReadLaterItem? {
        items.first(where: { $0.id == id })
    }

    /// Look up an item by article link.
    func item(forLink link: String) -> ReadLaterItem? {
        items.first(where: { $0.articleLink == link })
    }

    /// Whether an article link is currently saved (pending or snoozed).
    func isSaved(link: String) -> Bool {
        items.contains(where: {
            $0.articleLink == link && ($0.status == .pending || $0.status == .snoozed)
        })
    }

    /// All items sorted by priority (descending) then saved date (ascending).
    func allItemsSorted() -> [ReadLaterItem] {
        items.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.savedAt < $1.savedAt
        }
    }

    /// Items filtered by status.
    func items(withStatus status: ReminderStatus) -> [ReadLaterItem] {
        items.filter { $0.status == status }
    }

    /// Items filtered by priority.
    func items(withPriority priority: ReminderPriority) -> [ReadLaterItem] {
        items.filter { $0.priority == priority }
    }

    /// Items that have a specific tag.
    func items(taggedWith tag: String) -> [ReadLaterItem] {
        let normalized = tag.lowercased()
        return items.filter { $0.tags.contains(normalized) }
    }

    /// Items from a specific feed.
    func items(fromFeed feedName: String) -> [ReadLaterItem] {
        items.filter { $0.feedName == feedName }
    }

    /// Search items by title, notes, and tags.
    func search(query: String) -> [ReadLaterItem] {
        let q = query.lowercased()
        return items.filter {
            $0.articleTitle.lowercased().contains(q) ||
            ($0.notes?.lowercased().contains(q) ?? false) ||
            $0.tags.contains(where: { $0.contains(q) })
        }
    }

    // MARK: - Reminder Generation

    /// Generate a batch of all currently due reminders, grouped by priority.
    func dueReminders(at now: Date = Date()) -> ReminderBatch {
        let due = items.filter { $0.isDue(at: now) }
        return ReminderBatch(
            urgent: due.filter { $0.priority == .urgent },
            high:   due.filter { $0.priority == .high },
            normal: due.filter { $0.priority == .normal },
            low:    due.filter { $0.priority == .low },
            generatedAt: now
        )
    }

    /// Acknowledge a reminder — resets the next reminder date based on priority interval.
    @discardableResult
    func acknowledgeReminder(id: String, at now: Date = Date()) -> Bool {
        guard let idx = items.firstIndex(where: { $0.id == id }),
              items[idx].status == .pending || items[idx].status == .snoozed else { return false }
        items[idx].status = .pending
        items[idx].lastRemindedAt = now
        items[idx].nextReminderDate = now.addingTimeInterval(items[idx].priority.defaultInterval)
        save()
        return true
    }

    // MARK: - Expiration & Escalation

    /// Expire items older than the expiration window. Returns count of expired items.
    @discardableResult
    func processExpirations(at now: Date = Date()) -> Int {
        var count = 0
        for idx in items.indices {
            if items[idx].isExpired(at: now) &&
               (items[idx].status == .pending || items[idx].status == .snoozed) {
                items[idx].status = .expired
                count += 1
            }
        }
        if count > 0 { save() }
        return count
    }

    /// Auto-escalate items that have been pending longer than 2× their priority's
    /// default interval without being read. Returns count of escalated items.
    @discardableResult
    func autoEscalate(at now: Date = Date()) -> Int {
        var count = 0
        for idx in items.indices {
            guard items[idx].status == .pending || items[idx].status == .snoozed,
                  let next = items[idx].priority.escalated else { continue }
            let age = now.timeIntervalSince(items[idx].savedAt)
            let threshold = items[idx].priority.defaultInterval * 2
            if age > threshold {
                items[idx].priority = next
                count += 1
            }
        }
        if count > 0 { save() }
        return count
    }

    // MARK: - Statistics

    /// Compute aggregate statistics about the read-later queue.
    func statistics(at now: Date = Date()) -> ReminderStats {
        let completed = items.filter { $0.status == .completed }.count
        let dismissed = items.filter { $0.status == .dismissed }.count
        let pending = items.filter { $0.status == .pending }.count
        let snoozed = items.filter { $0.status == .snoozed }.count
        let expired = items.filter { $0.status == .expired }.count
        let finished = completed + dismissed
        let rate = finished > 0 ? Double(completed) / Double(finished) : 0

        let totalAge = items.reduce(0.0) { $0 + $1.ageInDays(at: now) }
        let avgAge = items.isEmpty ? 0 : totalAge / Double(items.count)
        let totalSnoozes = items.reduce(0) { $0 + $1.snoozeCount }

        // Tag frequency
        var tagCounts: [String: Int] = [:]
        for item in items {
            for tag in item.tags {
                tagCounts[tag, default: 0] += 1
            }
        }
        let topTags = tagCounts.sorted { $0.value > $1.value }
                               .prefix(10)
                               .map { (tag: $0.key, count: $0.value) }

        // Priority breakdown
        var byPriority: [ReminderPriority: Int] = [:]
        for p in ReminderPriority.allCases {
            byPriority[p] = items.filter { $0.priority == p }.count
        }

        return ReminderStats(
            totalItems: items.count,
            pendingCount: pending,
            snoozedCount: snoozed,
            completedCount: completed,
            dismissedCount: dismissed,
            expiredCount: expired,
            completionRate: rate,
            averageAgeInDays: avgAge,
            totalSnoozes: totalSnoozes,
            topTags: topTags,
            itemsByPriority: byPriority
        )
    }

    // MARK: - Export

    /// Export all items as JSON. Returns nil on encoding failure.
    func exportJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Export items as a Markdown reading list.
    func exportMarkdown() -> String {
        var md = "# Read Later\n\n"
        let sorted = allItemsSorted()

        if sorted.isEmpty {
            md += "_No items saved._\n"
            return md
        }

        // Group by priority
        for priority in ReminderPriority.allCases.reversed() {
            let group = sorted.filter { $0.priority == priority }
            if group.isEmpty { continue }

            md += "## \(priority.label) Priority\n\n"
            for item in group {
                let status: String
                switch item.status {
                case .completed: status = "✅"
                case .dismissed: status = "⏭️"
                case .expired:   status = "⏰"
                case .snoozed:   status = "💤"
                case .pending:   status = "📖"
                }
                md += "- \(status) [\(item.articleTitle)](\(item.articleLink))"
                if !item.feedName.isEmpty {
                    md += " — _\(item.feedName)_"
                }
                if item.snoozeCount > 0 {
                    md += " (snoozed \(item.snoozeCount)x)"
                }
                md += "\n"
                if let notes = item.notes, !notes.isEmpty {
                    md += "  > \(notes)\n"
                }
            }
            md += "\n"
        }

        return md
    }
}
