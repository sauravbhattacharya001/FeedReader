//
//  FeedCategoryManager.swift
//  FeedReader
//
//  Manages feed categories (folders/groups). Users can create named
//  categories and assign feeds to them for organized browsing.
//  Categories are persisted via UserDefaults.
//

import Foundation

/// Notification posted when categories change.
extension Notification.Name {
    static let feedCategoriesDidChange = Notification.Name("FeedCategoriesDidChangeNotification")
}

class FeedCategoryManager {
    
    // MARK: - Singleton
    
    static let shared = FeedCategoryManager()
    
    // MARK: - Properties
    
    /// Ordered list of user-defined category names.
    private(set) var categories: [String] = []
    
    /// UserDefaults key for persisting categories.
    private static let userDefaultsKey = "FeedCategoryManager.categories"
    
    /// The default "uncategorized" label (not stored in the list).
    static let uncategorizedLabel = "Uncategorized"
    
    // MARK: - Initialization
    
    private init() {
        load()
    }
    
    // MARK: - Category Management
    
    /// Add a new category. Returns false if a category with the same name
    /// (case-insensitive) already exists or the name is empty.
    @discardableResult
    func addCategory(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !categories.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            return false
        }
        categories.append(trimmed)
        save()
        NotificationCenter.default.post(name: .feedCategoriesDidChange, object: nil)
        return true
    }
    
    /// Remove a category by name. Feeds assigned to it become uncategorized.
    /// Returns the number of feeds that were unassigned.
    @discardableResult
    func removeCategory(_ name: String) -> Int {
        guard let index = categories.firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else {
            return 0
        }
        let removedName = categories[index]
        categories.remove(at: index)
        
        // Unassign feeds in this category
        var unassignedCount = 0
        for feed in FeedManager.shared.feeds {
            if let cat = feed.category, cat.caseInsensitiveCompare(removedName) == .orderedSame {
                feed.category = nil
                unassignedCount += 1
            }
        }
        
        save()
        NotificationCenter.default.post(name: .feedCategoriesDidChange, object: nil)
        return unassignedCount
    }
    
    /// Rename a category. Updates all feeds assigned to the old name.
    /// Returns false if oldName doesn't exist or newName conflicts.
    @discardableResult
    func renameCategory(from oldName: String, to newName: String) -> Bool {
        let trimmedNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNew.isEmpty else { return false }
        
        guard let index = categories.firstIndex(where: { $0.caseInsensitiveCompare(oldName) == .orderedSame }) else {
            return false
        }
        
        // Check new name doesn't conflict with a different category
        if categories.contains(where: { $0.caseInsensitiveCompare(trimmedNew) == .orderedSame && $0.caseInsensitiveCompare(oldName) != .orderedSame }) {
            return false
        }
        
        let oldCategoryName = categories[index]
        categories[index] = trimmedNew
        
        // Update feeds
        for feed in FeedManager.shared.feeds {
            if let cat = feed.category, cat.caseInsensitiveCompare(oldCategoryName) == .orderedSame {
                feed.category = trimmedNew
            }
        }
        
        save()
        NotificationCenter.default.post(name: .feedCategoriesDidChange, object: nil)
        return true
    }
    
    /// Reorder categories.
    func moveCategory(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex >= 0 && sourceIndex < categories.count,
              destinationIndex >= 0 && destinationIndex < categories.count,
              sourceIndex != destinationIndex else { return }
        let cat = categories.remove(at: sourceIndex)
        categories.insert(cat, at: destinationIndex)
        save()
        NotificationCenter.default.post(name: .feedCategoriesDidChange, object: nil)
    }
    
    /// Check if a category exists (case-insensitive).
    func categoryExists(_ name: String) -> Bool {
        return categories.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame })
    }
    
    /// Number of categories.
    var count: Int {
        return categories.count
    }
    
    // MARK: - Feed Assignment
    
    /// Assign a feed to a category. Creates the category if it doesn't exist.
    func assignFeed(_ feed: Feed, toCategory category: String) {
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        if !categoryExists(trimmed) {
            addCategory(trimmed)
        }
        
        feed.category = trimmed
        save()
        NotificationCenter.default.post(name: .feedCategoriesDidChange, object: nil)
    }
    
    /// Remove a feed from its category (make it uncategorized).
    func unassignFeed(_ feed: Feed) {
        feed.category = nil
        NotificationCenter.default.post(name: .feedCategoriesDidChange, object: nil)
    }
    
    /// Get all feeds in a specific category.
    func feeds(inCategory category: String) -> [Feed] {
        return FeedManager.shared.feeds.filter { feed in
            guard let cat = feed.category else { return false }
            return cat.caseInsensitiveCompare(category) == .orderedSame
        }
    }
    
    /// Get all uncategorized feeds.
    func uncategorizedFeeds() -> [Feed] {
        return FeedManager.shared.feeds.filter { $0.category == nil }
    }
    
    /// Get feeds grouped by category. Returns an ordered array of
    /// (category name, feeds) tuples. Uncategorized feeds come last.
    func feedsByCategory() -> [(category: String, feeds: [Feed])] {
        var result: [(category: String, feeds: [Feed])] = []
        
        for category in categories {
            let categoryFeeds = feeds(inCategory: category)
            if !categoryFeeds.isEmpty {
                result.append((category: category, feeds: categoryFeeds))
            }
        }
        
        let uncategorized = uncategorizedFeeds()
        if !uncategorized.isEmpty {
            result.append((category: FeedCategoryManager.uncategorizedLabel, feeds: uncategorized))
        }
        
        return result
    }
    
    /// Get enabled feeds in a specific category.
    func enabledFeeds(inCategory category: String) -> [Feed] {
        return feeds(inCategory: category).filter { $0.isEnabled }
    }
    
    /// Count feeds per category. Returns dictionary of category → count.
    func feedCountByCategory() -> [String: Int] {
        var counts: [String: Int] = [:]
        for feed in FeedManager.shared.feeds {
            let cat = feed.category ?? FeedCategoryManager.uncategorizedLabel
            counts[cat, default: 0] += 1
        }
        return counts
    }
    
    // MARK: - Persistence
    
    private func save() {
        UserDefaults.standard.set(categories, forKey: FeedCategoryManager.userDefaultsKey)
    }
    
    private func load() {
        categories = UserDefaults.standard.stringArray(forKey: FeedCategoryManager.userDefaultsKey) ?? []
    }
    
    /// Reset to empty state (for testing).
    func reset() {
        categories.removeAll()
        UserDefaults.standard.removeObject(forKey: FeedCategoryManager.userDefaultsKey)
    }
    
    /// Force reload from storage.
    func reload() {
        load()
    }
}
