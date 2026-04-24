//
//  SmartFeedManager.swift
//  FeedReader
//
//  Smart Feeds — keyword-based saved searches that auto-filter stories
//  across all enabled feeds. Supports configurable match modes (any/all)
//  and search scopes (title/body/both).
//

import Foundation
import os.log

// MARK: - SmartFeed Model

/// A saved keyword-based filter that auto-matches stories across all feeds.
class SmartFeed: NSObject, NSSecureCoding {
    
    // MARK: - NSSecureCoding
    
    static var supportsSecureCoding: Bool { return true }
    
    // MARK: - Types
    
    enum MatchMode: Int {
        case any = 0   // Match ANY keyword (OR)
        case all = 1   // Match ALL keywords (AND)
    }
    
    enum SearchScope: Int {
        case titleOnly = 0
        case bodyOnly = 1
        case titleAndBody = 2
    }
    
    struct PropertyKey {
        static let nameKey = "smartFeedName"
        static let keywordsKey = "smartFeedKeywords"
        static let matchModeKey = "smartFeedMatchMode"
        static let searchScopeKey = "smartFeedSearchScope"
        static let isEnabledKey = "smartFeedIsEnabled"
        static let createdAtKey = "smartFeedCreatedAt"
    }
    
    // MARK: - Limits
    
    static let maxNameLength = 50
    static let maxKeywords = 10
    static let maxKeywordLength = 100
    
    // MARK: - Properties
    
    var name: String
    var keywords: [String]
    var matchMode: MatchMode
    var searchScope: SearchScope
    var isEnabled: Bool
    var createdAt: Date
    
    // MARK: - Initialization
    
    /// Creates a SmartFeed. Returns nil if name is empty after trimming.
    /// Keywords are normalized: trimmed, lowercased, empty strings removed,
    /// truncated to maxKeywords, each capped at maxKeywordLength.
    init?(name: String, keywords: [String], matchMode: MatchMode = .any,
          searchScope: SearchScope = .titleAndBody, isEnabled: Bool = true,
          createdAt: Date = Date()) {
        
        // Validate name
        let trimmedName = String(name.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(SmartFeed.maxNameLength))
        guard !trimmedName.isEmpty else { return nil }
        
        self.name = trimmedName
        
        // Normalize keywords: trim, lowercase, drop empty, enforce limits
        let normalizedKeywords = keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .map { String($0.prefix(SmartFeed.maxKeywordLength)) }
            .prefix(SmartFeed.maxKeywords)
        self.keywords = Array(normalizedKeywords)
        
        self.matchMode = matchMode
        self.searchScope = searchScope
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        
        super.init()
    }
    
    // MARK: - NSCoding
    
    func encode(with coder: NSCoder) {
        coder.encode(name, forKey: PropertyKey.nameKey)
        coder.encode(keywords as NSArray, forKey: PropertyKey.keywordsKey)
        coder.encode(matchMode.rawValue, forKey: PropertyKey.matchModeKey)
        coder.encode(searchScope.rawValue, forKey: PropertyKey.searchScopeKey)
        coder.encode(isEnabled, forKey: PropertyKey.isEnabledKey)
        coder.encode(createdAt as NSDate, forKey: PropertyKey.createdAtKey)
    }
    
    required convenience init?(coder decoder: NSCoder) {
        guard let name = decoder.decodeObject(of: NSString.self, forKey: PropertyKey.nameKey) as String? else {
            return nil
        }
        
        let keywordsArray = decoder.decodeObject(of: [NSArray.self, NSString.self], forKey: PropertyKey.keywordsKey) as? [String] ?? []
        let matchModeRaw = decoder.decodeInteger(forKey: PropertyKey.matchModeKey)
        let searchScopeRaw = decoder.decodeInteger(forKey: PropertyKey.searchScopeKey)
        let isEnabled = decoder.decodeBool(forKey: PropertyKey.isEnabledKey)
        let createdAt = decoder.decodeObject(of: NSDate.self, forKey: PropertyKey.createdAtKey) as Date? ?? Date()
        
        let matchMode = MatchMode(rawValue: matchModeRaw) ?? .any
        let searchScope = SearchScope(rawValue: searchScopeRaw) ?? .titleAndBody
        
        self.init(name: name, keywords: keywordsArray, matchMode: matchMode,
                  searchScope: searchScope, isEnabled: isEnabled, createdAt: createdAt)
    }
}

// MARK: - SmartFeedManager

/// Manages Smart Feeds — CRUD, persistence, matching.
class SmartFeedManager {
    
    // MARK: - Singleton
    
    static let shared = SmartFeedManager()
    
    // MARK: - Notifications
    
    static let smartFeedsDidChangeNotification = Notification.Name("SmartFeedsDidChange")
    
    // MARK: - Limits
    
    static let maxSmartFeeds = 20
    static let maxKeywordsPerFeed = 10
    static let maxKeywordLength = 100
    
    // MARK: - Properties
    
    private(set) var smartFeeds: [SmartFeed] = []
    
    /// Returns only enabled smart feeds.
    var enabledSmartFeeds: [SmartFeed] {
        return smartFeeds.filter { $0.isEnabled }
    }
    
    /// Number of smart feeds.
    var count: Int {
        return smartFeeds.count
    }
    
    // MARK: - Persistence Keys
    
    private static let userDefaultsKey = "savedSmartFeeds"
    
    // MARK: - Initialization
    
    init() {
        load()
    }
    
    // MARK: - CRUD
    
    /// Add a smart feed. No-op if at limit or duplicate name exists.
    func addSmartFeed(_ smartFeed: SmartFeed) {
        guard smartFeeds.count < SmartFeedManager.maxSmartFeeds else { return }
        
        // Duplicate name check (case-insensitive)
        let lowercasedName = smartFeed.name.lowercased()
        guard !smartFeeds.contains(where: { $0.name.lowercased() == lowercasedName }) else { return }
        
        smartFeeds.append(smartFeed)
        save()
        NotificationCenter.default.post(name: SmartFeedManager.smartFeedsDidChangeNotification, object: nil)
    }
    
    /// Remove a smart feed at a specific index.
    func removeSmartFeed(at index: Int) {
        guard index >= 0 && index < smartFeeds.count else { return }
        smartFeeds.remove(at: index)
        save()
        NotificationCenter.default.post(name: SmartFeedManager.smartFeedsDidChangeNotification, object: nil)
    }
    
    /// Remove a smart feed by name (case-insensitive).
    func removeSmartFeed(byName name: String) {
        let lowercasedName = name.lowercased()
        guard let index = smartFeeds.firstIndex(where: { $0.name.lowercased() == lowercasedName }) else { return }
        smartFeeds.remove(at: index)
        save()
        NotificationCenter.default.post(name: SmartFeedManager.smartFeedsDidChangeNotification, object: nil)
    }
    
    /// Update a smart feed at a specific index.
    func updateSmartFeed(at index: Int, with smartFeed: SmartFeed) {
        guard index >= 0 && index < smartFeeds.count else { return }
        smartFeeds[index] = smartFeed
        save()
        NotificationCenter.default.post(name: SmartFeedManager.smartFeedsDidChangeNotification, object: nil)
    }
    
    /// Look up a smart feed by name (case-insensitive).
    func smartFeed(named name: String) -> SmartFeed? {
        let lowercasedName = name.lowercased()
        return smartFeeds.first(where: { $0.name.lowercased() == lowercasedName })
    }
    
    // MARK: - Matching
    
    /// Returns stories that match the given smart feed's criteria.
    func matchingStories(for smartFeed: SmartFeed, in stories: [Story]) -> [Story] {
        return stories.filter { matchesSmartFeed($0, smartFeed: smartFeed) }
    }
    
    /// Checks if a story matches the smart feed's keywords based on mode and scope.
    func matchesSmartFeed(_ story: Story, smartFeed: SmartFeed) -> Bool {
        // Empty keywords match nothing
        guard !smartFeed.keywords.isEmpty else { return false }
        
        // Build searchable text based on scope
        let searchText: String
        switch smartFeed.searchScope {
        case .titleOnly:
            searchText = story.title.lowercased()
        case .bodyOnly:
            searchText = story.body.lowercased()
        case .titleAndBody:
            searchText = (story.title + " " + story.body).lowercased()
        }
        
        // Match based on mode
        switch smartFeed.matchMode {
        case .any:
            // OR — at least one keyword must be found
            return smartFeed.keywords.contains { keyword in
                searchText.contains(keyword)
            }
        case .all:
            // AND — all keywords must be found
            return smartFeed.keywords.allSatisfy { keyword in
                searchText.contains(keyword)
            }
        }
    }
    
    // MARK: - Convenience
    
    /// Remove all smart feeds.
    func clearAll() {
        smartFeeds.removeAll()
        save()
        NotificationCenter.default.post(name: SmartFeedManager.smartFeedsDidChangeNotification, object: nil)
    }
    
    // MARK: - Persistence
    
    /// Save smart feeds to UserDefaults using NSSecureCoding.
    func save() {
        do {
            let data = try NSKeyedArchiver.archivedData(
                withRootObject: smartFeeds as NSArray,
                requiringSecureCoding: true
            )
            UserDefaults.standard.set(data, forKey: SmartFeedManager.userDefaultsKey)
        } catch {
            os_log("Failed to save smart feeds: %{private}s", log: FeedReaderLogger.smartFeed, type: .error, error.localizedDescription)
        }
    }
    
    /// Load smart feeds from UserDefaults.
    func load() {
        guard let data = UserDefaults.standard.data(forKey: SmartFeedManager.userDefaultsKey) else {
            smartFeeds = []
            return
        }
        
        if let loaded = (try? NSKeyedUnarchiver.unarchivedObject(
            ofClasses: [NSArray.self, SmartFeed.self],
            from: data
        )) as? [SmartFeed] {
            smartFeeds = loaded
        } else {
            smartFeeds = []
        }
    }
}
