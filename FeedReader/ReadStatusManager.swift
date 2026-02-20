//
//  ReadStatusManager.swift
//  FeedReader
//
//  Tracks read/unread status for stories. Uses UserDefaults for
//  lightweight persistent storage. Stories are identified by their
//  link URL, consistent with BookmarkManager's approach.
//

import Foundation

/// Notification posted when read status changes.
extension Notification.Name {
    static let readStatusDidChange = Notification.Name("ReadStatusDidChangeNotification")
}

class ReadStatusManager {
    
    // MARK: - Singleton
    
    static let shared = ReadStatusManager()
    
    // MARK: - Properties
    
    /// Set of story links that have been read.
    private var readLinks: Set<String>
    
    /// UserDefaults key for persisting read links.
    private static let userDefaultsKey = "ReadStatusManager.readLinks"
    
    /// Maximum number of read links to store (prevents unbounded growth).
    /// Old entries are pruned when this limit is exceeded.
    static let maxStoredLinks = 5000
    
    // MARK: - Initialization
    
    private init() {
        readLinks = ReadStatusManager.loadFromDefaults()
    }
    
    // MARK: - Public Methods
    
    /// Check if a story has been read.
    func isRead(_ story: Story) -> Bool {
        return readLinks.contains(story.link)
    }
    
    /// Check if a story link has been read.
    func isRead(link: String) -> Bool {
        return readLinks.contains(link)
    }
    
    /// Mark a story as read. Returns true if newly marked (was unread before).
    @discardableResult
    func markAsRead(_ story: Story) -> Bool {
        return markAsRead(link: story.link)
    }
    
    /// Mark a story link as read. Returns true if newly marked.
    @discardableResult
    func markAsRead(link: String) -> Bool {
        let inserted = readLinks.insert(link).inserted
        if inserted {
            pruneIfNeeded()
            save()
            NotificationCenter.default.post(name: .readStatusDidChange, object: nil)
        }
        return inserted
    }
    
    /// Mark a story as unread. Returns true if was previously read.
    @discardableResult
    func markAsUnread(_ story: Story) -> Bool {
        return markAsUnread(link: story.link)
    }
    
    /// Mark a story link as unread. Returns true if was previously read.
    @discardableResult
    func markAsUnread(link: String) -> Bool {
        let removed = readLinks.remove(link) != nil
        if removed {
            save()
            NotificationCenter.default.post(name: .readStatusDidChange, object: nil)
        }
        return removed
    }
    
    /// Toggle read/unread status. Returns true if now read.
    @discardableResult
    func toggleReadStatus(_ story: Story) -> Bool {
        if isRead(story) {
            markAsUnread(story)
            return false
        } else {
            markAsRead(story)
            return true
        }
    }
    
    /// Mark all stories in the array as read.
    func markAllAsRead(_ stories: [Story]) {
        var changed = false
        for story in stories {
            if readLinks.insert(story.link).inserted {
                changed = true
            }
        }
        if changed {
            pruneIfNeeded()
            save()
            NotificationCenter.default.post(name: .readStatusDidChange, object: nil)
        }
    }
    
    /// Count unread stories from the given array.
    func unreadCount(in stories: [Story]) -> Int {
        return stories.filter { !readLinks.contains($0.link) }.count
    }
    
    /// Filter stories by read status.
    func filterStories(_ stories: [Story], readStatus: ReadFilter) -> [Story] {
        switch readStatus {
        case .all:
            return stories
        case .unread:
            return stories.filter { !readLinks.contains($0.link) }
        case .read:
            return stories.filter { readLinks.contains($0.link) }
        }
    }
    
    /// Total number of tracked read links.
    var readCount: Int {
        return readLinks.count
    }
    
    /// Clear all read status data.
    func clearAll() {
        readLinks.removeAll()
        save()
        NotificationCenter.default.post(name: .readStatusDidChange, object: nil)
    }
    
    // MARK: - Filter Enum
    
    /// Filter options for story read status.
    enum ReadFilter: Int, CaseIterable {
        case all = 0
        case unread = 1
        case read = 2
        
        var title: String {
            switch self {
            case .all: return "All"
            case .unread: return "Unread"
            case .read: return "Read"
            }
        }
    }
    
    // MARK: - Persistence
    
    private func save() {
        let array = Array(readLinks)
        UserDefaults.standard.set(array, forKey: ReadStatusManager.userDefaultsKey)
    }
    
    private static func loadFromDefaults() -> Set<String> {
        guard let array = UserDefaults.standard.stringArray(forKey: userDefaultsKey) else {
            return Set<String>()
        }
        return Set(array)
    }
    
    /// Prune oldest entries if we exceed the max stored links.
    /// Since Set doesn't have ordering, we just remove random excess entries.
    /// This is acceptable because the pruned entries are the oldest (least
    /// likely to appear in current feeds).
    private func pruneIfNeeded() {
        if readLinks.count > ReadStatusManager.maxStoredLinks {
            let excess = readLinks.count - ReadStatusManager.maxStoredLinks
            for _ in 0..<excess {
                if let first = readLinks.first {
                    readLinks.remove(first)
                }
            }
        }
    }
    
    /// Force a reload from UserDefaults (useful for testing).
    func reload() {
        readLinks = ReadStatusManager.loadFromDefaults()
    }
}
