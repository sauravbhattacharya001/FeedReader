//
//  FeedManager.swift
//  FeedReader
//
//  Manages the user's RSS feed sources with persistent storage.
//  Supports adding, removing, reordering, enabling/disabling feeds,
//  and adding custom feeds by URL.
//

import Foundation

/// Notification posted when the feeds list changes (add/remove/toggle/reorder).
extension Notification.Name {
    static let feedsDidChange = Notification.Name("FeedsDidChangeNotification")
}

class FeedManager {
    
    // MARK: - Singleton
    
    static let shared = FeedManager()
    
    // MARK: - Properties
    
    private(set) var feeds: [Feed] = []
    
    /// Returns only enabled feeds.
    var enabledFeeds: [Feed] {
        return feeds.filter { $0.isEnabled }
    }
    
    /// Reusable persistence store — replaces hand-rolled NSKeyedArchiver boilerplate.
    private let store = SecureCodingStore<Feed>(filename: "feedSources")
    
    /// Key to track whether this is the first launch (feeds have been initialized).
    private static let hasInitializedKey = "FeedManager.hasInitialized"
    
    // MARK: - Initialization
    
    private init() {
        loadFeeds()
        
        // On first launch, populate with the default BBC World News feed
        if feeds.isEmpty && !UserDefaults.standard.bool(forKey: FeedManager.hasInitializedKey) {
            feeds = [Feed.presets[0]] // BBC World News, enabled by default
            saveFeeds()
            UserDefaults.standard.set(true, forKey: FeedManager.hasInitializedKey)
        }
    }
    
    // MARK: - Public Methods
    
    /// Add a new feed. Returns false if a feed with the same URL already exists.
    @discardableResult
    func addFeed(_ feed: Feed) -> Bool {
        guard !feeds.contains(where: { $0.identifier == feed.identifier }) else {
            return false
        }
        feeds.append(feed)
        saveFeeds()
        NotificationCenter.default.post(name: .feedsDidChange, object: nil)
        return true
    }
    
    /// Add a custom feed by URL. Validates the URL format and rejects
    /// private/internal network addresses (SSRF protection).
    /// Returns the created Feed if successful, nil if URL is invalid or duplicate.
    @discardableResult
    func addCustomFeed(name: String, url: String) -> Feed? {
        // Validate URL and check for SSRF
        guard URLValidator.validateFeedURL(url) != nil else {
            return nil
        }
        
        let feed = Feed(name: name, url: url, isEnabled: true)
        if addFeed(feed) {
            return feed
        }
        return nil
    }
    
    /// Remove a feed at the specified index.
    func removeFeed(at index: Int) {
        guard index >= 0 && index < feeds.count else { return }
        feeds.remove(at: index)
        saveFeeds()
        NotificationCenter.default.post(name: .feedsDidChange, object: nil)
    }
    
    /// Remove a feed by matching URL.
    func removeFeed(_ feed: Feed) {
        feeds.removeAll { $0.identifier == feed.identifier }
        saveFeeds()
        NotificationCenter.default.post(name: .feedsDidChange, object: nil)
    }
    
    /// Toggle enabled state for a feed at the specified index.
    /// Returns the new enabled state.
    @discardableResult
    func toggleFeed(at index: Int) -> Bool {
        guard index >= 0 && index < feeds.count else { return false }
        feeds[index].isEnabled = !feeds[index].isEnabled
        saveFeeds()
        NotificationCenter.default.post(name: .feedsDidChange, object: nil)
        return feeds[index].isEnabled
    }
    
    /// Move a feed from one position to another (for reordering).
    func moveFeed(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex >= 0 && sourceIndex < feeds.count,
              destinationIndex >= 0 && destinationIndex < feeds.count,
              sourceIndex != destinationIndex else { return }
        let feed = feeds.remove(at: sourceIndex)
        feeds.insert(feed, at: destinationIndex)
        saveFeeds()
        NotificationCenter.default.post(name: .feedsDidChange, object: nil)
    }
    
    /// Check if a feed with the given URL already exists.
    func feedExists(url: String) -> Bool {
        return feeds.contains { $0.identifier == url.lowercased() }
    }
    
    /// Add a preset feed by index (from Feed.presets).
    @discardableResult
    func addPreset(at index: Int) -> Bool {
        guard index >= 0 && index < Feed.presets.count else { return false }
        let preset = Feed.presets[index]
        let feed = Feed(name: preset.name, url: preset.url, isEnabled: true)
        return addFeed(feed)
    }
    
    /// Number of configured feeds.
    var count: Int {
        return feeds.count
    }
    
    /// Get feed URLs for all enabled feeds.
    var enabledURLs: [String] {
        return enabledFeeds.map { $0.url }
    }
    
    // MARK: - Persistence
    
    private func saveFeeds() {
        store.save(feeds)
    }
    
    private func loadFeeds() {
        feeds = store.load()
    }
    
    /// Force reload from disk (useful for testing).
    func reload() {
        loadFeeds()
    }
    
    /// Reset to default state (useful for testing).
    func resetToDefaults() {
        feeds = [Feed.presets[0]]
        saveFeeds()
        NotificationCenter.default.post(name: .feedsDidChange, object: nil)
    }
}
