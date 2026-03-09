//
//  ReadingQueueManager.swift
//  FeedReader
//
//  Manages an ordered reading queue with priority levels, estimated
//  reading time, position management, and completion tracking.
//  Complements BookmarkManager (unordered save) with a structured
//  "read next" workflow.
//

import Foundation

/// Notification posted when the reading queue changes.
extension Notification.Name {
    static let readingQueueDidChange = Notification.Name("ReadingQueueDidChangeNotification")
}

class ReadingQueueManager {

    // MARK: - Singleton

    static let shared = ReadingQueueManager()

    // MARK: - Types

    /// Priority level for queued articles.
    enum Priority: Int, Codable, Comparable, CaseIterable {
        case low = 0
        case normal = 1
        case high = 2
        case urgent = 3

        var label: String {
            switch self {
            case .low: return "Low"
            case .normal: return "Normal"
            case .high: return "High"
            case .urgent: return "Urgent"
            }
        }

        static func < (lhs: Priority, rhs: Priority) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }

    /// A single item in the reading queue.
    struct QueueItem: Codable, Equatable {
        let id: String
        let articleLink: String
        let articleTitle: String
        let sourceFeedName: String
        var priority: Priority
        let addedDate: Date
        var estimatedReadingTimeMinutes: Double
        var isCompleted: Bool
        var completedDate: Date?
        var notes: String?

        /// Words per minute used for time estimation.
        static let wordsPerMinute: Double = 238.0

        init(story: StoryRef, priority: Priority = .normal,
             estimatedMinutes: Double? = nil) {
            self.id = UUID().uuidString
            self.articleLink = story.link
            self.articleTitle = story.title
            self.sourceFeedName = story.sourceFeedName ?? "Unknown"
            self.priority = priority
            self.addedDate = Date()
            self.estimatedReadingTimeMinutes = estimatedMinutes
                ?? QueueItem.estimateReadingTime(wordCount: story.wordCount)
            self.isCompleted = false
            self.completedDate = nil
            self.notes = nil
        }

        static func estimateReadingTime(wordCount: Int) -> Double {
            guard wordCount > 0 else { return 1.0 }
            let minutes = Double(wordCount) / wordsPerMinute
            return max(1.0, (minutes * 10).rounded() / 10)
        }

        static func == (lhs: QueueItem, rhs: QueueItem) -> Bool {
            return lhs.id == rhs.id
        }
    }

    /// Lightweight story reference for queue item creation.
    /// Avoids depending on UIKit's Story class in tests.
    struct StoryRef {
        let title: String
        let link: String
        let sourceFeedName: String?
        let wordCount: Int

        init(title: String, link: String, sourceFeedName: String? = nil,
             wordCount: Int = 0) {
            self.title = title
            self.link = link
            self.sourceFeedName = sourceFeedName
            self.wordCount = wordCount
        }
    }

    /// Queue statistics summary.
    struct QueueStats {
        let totalItems: Int
        let pendingItems: Int
        let completedItems: Int
        let totalEstimatedMinutes: Double
        let pendingEstimatedMinutes: Double
        let completionRate: Double
        let averageReadingTime: Double
        let itemsByPriority: [Priority: Int]
        let oldestPendingDate: Date?
    }

    // MARK: - Properties

    private(set) var items: [QueueItem] = []
    private var linkIndex = Set<String>()

    private static let storageKey = "ReadingQueueItems"

    // MARK: - Initialization

    private init() {
        loadQueue()
    }

    /// Internal initializer for testing (does not load from disk).
    init(testItems: [QueueItem]) {
        self.items = testItems
        rebuildIndex()
    }

    // MARK: - Queue Operations

    /// Add an article to the reading queue. Returns the created item,
    /// or nil if the article is already queued.
    @discardableResult
    func enqueue(story: StoryRef, priority: Priority = .normal,
                 estimatedMinutes: Double? = nil) -> QueueItem? {
        guard !linkIndex.contains(story.link) else { return nil }

        let item = QueueItem(story: story, priority: priority,
                             estimatedMinutes: estimatedMinutes)
        items.append(item)
        linkIndex.insert(story.link)
        save()
        NotificationCenter.default.post(name: .readingQueueDidChange, object: nil)
        return item
    }

    /// Remove an item from the queue by ID.
    @discardableResult
    func dequeue(id: String) -> QueueItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let removed = items.remove(at: index)
        linkIndex.remove(removed.articleLink)
        save()
        NotificationCenter.default.post(name: .readingQueueDidChange, object: nil)
        return removed
    }

    /// Remove an item by article link.
    @discardableResult
    func dequeue(link: String) -> QueueItem? {
        guard let index = items.firstIndex(where: { $0.articleLink == link }) else {
            return nil
        }
        let removed = items.remove(at: index)
        linkIndex.remove(removed.articleLink)
        save()
        NotificationCenter.default.post(name: .readingQueueDidChange, object: nil)
        return removed
    }

    /// Check if an article is already in the queue.
    func isQueued(link: String) -> Bool {
        return linkIndex.contains(link)
    }

    /// Get the next unread item (first pending item in queue order).
    func nextUp() -> QueueItem? {
        return items.first(where: { !$0.isCompleted })
    }

    // MARK: - Completion

    /// Mark an item as completed.
    func markCompleted(id: String) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return false
        }
        guard !items[index].isCompleted else { return false }
        items[index].isCompleted = true
        items[index].completedDate = Date()
        save()
        NotificationCenter.default.post(name: .readingQueueDidChange, object: nil)
        return true
    }

    /// Mark an item as not completed (undo).
    func markIncomplete(id: String) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return false
        }
        guard items[index].isCompleted else { return false }
        items[index].isCompleted = false
        items[index].completedDate = nil
        save()
        NotificationCenter.default.post(name: .readingQueueDidChange, object: nil)
        return true
    }

    /// Remove all completed items from the queue.
    func clearCompleted() -> Int {
        let before = items.count
        let completedLinks = items.filter({ $0.isCompleted }).map({ $0.articleLink })
        items.removeAll(where: { $0.isCompleted })
        for link in completedLinks {
            linkIndex.remove(link)
        }
        let removed = before - items.count
        if removed > 0 {
            save()
            NotificationCenter.default.post(name: .readingQueueDidChange, object: nil)
        }
        return removed
    }

    // MARK: - Reordering

    /// Move an item to a specific position in the queue.
    func move(id: String, to newIndex: Int) -> Bool {
        guard let fromIndex = items.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let clampedIndex = max(0, min(newIndex, items.count - 1))
        guard clampedIndex != fromIndex else { return false }

        let item = items.remove(at: fromIndex)
        items.insert(item, at: clampedIndex)
        save()
        NotificationCenter.default.post(name: .readingQueueDidChange, object: nil)
        return true
    }

    /// Move an item to the top of the queue (position 0).
    func moveToTop(id: String) -> Bool {
        return move(id: id, to: 0)
    }

    /// Move an item to the bottom of the queue.
    func moveToBottom(id: String) -> Bool {
        return move(id: id, to: items.count - 1)
    }

    /// Move an item up one position.
    func moveUp(id: String) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return false
        }
        return move(id: id, to: index - 1)
    }

    /// Move an item down one position.
    func moveDown(id: String) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return false
        }
        return move(id: id, to: index + 1)
    }

    // MARK: - Priority

    /// Update the priority of a queued item.
    func setPriority(id: String, priority: Priority) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return false
        }
        guard items[index].priority != priority else { return false }
        items[index].priority = priority
        save()
        NotificationCenter.default.post(name: .readingQueueDidChange, object: nil)
        return true
    }

    /// Sort the queue by priority (urgent first), preserving relative
    /// order within the same priority level (stable sort).
    func sortByPriority() {
        let before = items
        items.sort { $0.priority.rawValue > $1.priority.rawValue }
        if items.map({ $0.id }) != before.map({ $0.id }) {
            save()
            NotificationCenter.default.post(name: .readingQueueDidChange, object: nil)
        }
    }

    /// Sort the queue by estimated reading time (shortest first).
    func sortByReadingTime() {
        let before = items
        items.sort { $0.estimatedReadingTimeMinutes < $1.estimatedReadingTimeMinutes }
        if items.map({ $0.id }) != before.map({ $0.id }) {
            save()
            NotificationCenter.default.post(name: .readingQueueDidChange, object: nil)
        }
    }

    /// Sort by date added (oldest first — FIFO).
    func sortByDateAdded() {
        let before = items
        items.sort { $0.addedDate < $1.addedDate }
        if items.map({ $0.id }) != before.map({ $0.id }) {
            save()
            NotificationCenter.default.post(name: .readingQueueDidChange, object: nil)
        }
    }

    // MARK: - Notes

    /// Attach or update a note on a queued item.
    func setNote(id: String, note: String?) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return false
        }
        items[index].notes = note
        save()
        return true
    }

    // MARK: - Filtering

    /// Get only pending (unread) items.
    func pendingItems() -> [QueueItem] {
        return items.filter { !$0.isCompleted }
    }

    /// Get only completed items.
    func completedItems() -> [QueueItem] {
        return items.filter { $0.isCompleted }
    }

    /// Get items filtered by priority.
    func items(withPriority priority: Priority) -> [QueueItem] {
        return items.filter { $0.priority == priority }
    }

    /// Get items from a specific feed.
    func items(fromFeed feedName: String) -> [QueueItem] {
        return items.filter { $0.sourceFeedName == feedName }
    }

    // MARK: - Statistics

    /// Generate queue statistics summary.
    func stats() -> QueueStats {
        let pending = items.filter { !$0.isCompleted }
        let completed = items.filter { $0.isCompleted }

        let totalMinutes = items.reduce(0.0) { $0 + $1.estimatedReadingTimeMinutes }
        let pendingMinutes = pending.reduce(0.0) { $0 + $1.estimatedReadingTimeMinutes }

        var byPriority: [Priority: Int] = [:]
        for p in Priority.allCases {
            byPriority[p] = items.filter({ $0.priority == p }).count
        }

        let completionRate = items.isEmpty ? 0.0
            : Double(completed.count) / Double(items.count) * 100.0
        let avgTime = items.isEmpty ? 0.0 : totalMinutes / Double(items.count)
        let oldestPending = pending.min(by: { $0.addedDate < $1.addedDate })?.addedDate

        return QueueStats(
            totalItems: items.count,
            pendingItems: pending.count,
            completedItems: completed.count,
            totalEstimatedMinutes: totalMinutes,
            pendingEstimatedMinutes: pendingMinutes,
            completionRate: completionRate,
            averageReadingTime: avgTime,
            itemsByPriority: byPriority,
            oldestPendingDate: oldestPending
        )
    }

    /// Estimated time to clear the pending queue (formatted).
    func estimatedTimeToEmpty() -> String {
        let minutes = pendingItems().reduce(0.0) { $0 + $1.estimatedReadingTimeMinutes }
        if minutes < 1 { return "Queue empty" }
        if minutes < 60 { return "\(Int(minutes.rounded()))min" }
        let hours = Int(minutes / 60)
        let mins = Int(minutes.truncatingRemainder(dividingBy: 60))
        if hours == 0 { return "\(mins)min" }
        return "\(hours)h \(mins)min"
    }

    // MARK: - Bulk Operations

    /// Clear the entire queue.
    func clearAll() -> Int {
        let count = items.count
        items.removeAll()
        linkIndex.removeAll()
        save()
        NotificationCenter.default.post(name: .readingQueueDidChange, object: nil)
        return count
    }

    /// Enqueue multiple stories at once.
    func enqueueBatch(stories: [StoryRef], priority: Priority = .normal) -> Int {
        var added = 0
        for story in stories {
            guard !linkIndex.contains(story.link) else { continue }
            let item = QueueItem(story: story, priority: priority)
            items.append(item)
            linkIndex.insert(story.link)
            added += 1
        }
        if added > 0 {
            save()
            NotificationCenter.default.post(name: .readingQueueDidChange, object: nil)
        }
        return added
    }

    // MARK: - Persistence

    private func save() {
        let encoder = JSONCoding.epochEncoder
        if let data = try? encoder.encode(items) {
            UserDefaults.standard.set(data, forKey: ReadingQueueManager.storageKey)
        }
    }

    private func loadQueue() {
        guard let data = UserDefaults.standard.data(
            forKey: ReadingQueueManager.storageKey) else { return }
        let decoder = JSONCoding.epochDecoder
        if let loaded = try? decoder.decode([QueueItem].self, from: data) {
            items = loaded
            rebuildIndex()
        }
    }

    private func rebuildIndex() {
        linkIndex = Set(items.map { $0.articleLink })
    }
}
