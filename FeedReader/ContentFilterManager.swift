//
//  ContentFilterManager.swift
//  FeedReader
//
//  Manages content filters for muting unwanted stories by keyword/phrase.
//  Singleton with CRUD, matching, persistence, import/export.
//

import Foundation

/// Result of importing filters from JSON.
struct ImportResult {
    var added: Int
    var skipped: Int
    var errors: Int
}

/// Manages content filters — CRUD, persistence, matching.
class ContentFilterManager {
    
    // MARK: - Singleton
    
    static let shared = ContentFilterManager()
    
    // MARK: - Notifications
    
    static let contentFiltersDidChangeNotification = Notification.Name("contentFiltersDidChange")
    
    // MARK: - Limits
    
    static let maxFilters = 50
    
    // MARK: - Properties
    
    private(set) var filters: [ContentFilter] = []
    
    /// Returns only active filters.
    var activeFilters: [ContentFilter] {
        return filters.filter { $0.isActive }
    }
    
    /// Number of filters.
    var filterCount: Int {
        return filters.count
    }
    
    /// Number of active filters.
    var activeFilterCount: Int {
        return filters.filter { $0.isActive }.count
    }
    
    // MARK: - Persistence Keys
    
    private static let userDefaultsKey = "savedContentFilters"
    
    // MARK: - Initialization
    
    init() {
        load()
    }
    
    // MARK: - CRUD
    
    /// Add a filter. Returns false if at limit or duplicate keyword exists.
    @discardableResult
    func addFilter(_ filter: ContentFilter) -> Bool {
        guard filters.count < ContentFilterManager.maxFilters else { return false }
        
        // Duplicate keyword check (case-insensitive)
        let lowered = filter.keyword.lowercased()
        guard !filters.contains(where: { $0.keyword.lowercased() == lowered }) else { return false }
        
        filters.append(filter)
        save()
        postNotification()
        return true
    }
    
    /// Remove a filter by id. Returns false if not found.
    @discardableResult
    func removeFilter(id: String) -> Bool {
        guard let index = filters.firstIndex(where: { $0.id == id }) else { return false }
        filters.remove(at: index)
        save()
        postNotification()
        return true
    }
    
    /// Toggle a filter's active state. Returns false if not found.
    @discardableResult
    func toggleFilter(id: String) -> Bool {
        guard let filter = filters.first(where: { $0.id == id }) else { return false }
        filter.isActive = !filter.isActive
        save()
        postNotification()
        return true
    }
    
    /// Update a filter's keyword, scope, and mode. Returns false if not found or invalid.
    @discardableResult
    func updateFilter(id: String, keyword: String, matchScope: ContentFilter.MatchScope, matchMode: ContentFilter.MatchMode) -> Bool {
        guard let filter = filters.first(where: { $0.id == id }) else { return false }
        
        let trimmed = String(keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(ContentFilter.maxKeywordLength))
        guard !trimmed.isEmpty else { return false }
        
        // Check duplicate (excluding self)
        let lowered = trimmed.lowercased()
        if filters.contains(where: { $0.id != id && $0.keyword.lowercased() == lowered }) {
            return false
        }
        
        // Validate regex if needed
        if matchMode == .regex {
            do {
                _ = try NSRegularExpression(pattern: trimmed, options: [.caseInsensitive])
            } catch {
                return false
            }
        }
        
        filter.keyword = trimmed
        filter.matchScope = matchScope
        filter.matchMode = matchMode
        save()
        postNotification()
        return true
    }
    
    /// Get a filter by id.
    func getFilter(id: String) -> ContentFilter? {
        return filters.first(where: { $0.id == id })
    }
    
    /// Remove all filters.
    func clearAll() {
        filters.removeAll()
        save()
        postNotification()
    }
    
    // MARK: - Matching
    
    /// Check if a story should be muted (matches any active filter).
    /// Increments the matching filter's muted count and persists it.
    func shouldMute(_ story: Story) -> Bool {
        for filter in activeFilters {
            if matchesFilter(story, filter: filter) {
                filter.mutedCount += 1
                save()
                return true
            }
        }
        return false
    }
    
    /// Returns stories that would be hidden by active filters.
    /// Increments muted counts for each matching filter and persists.
    func mutedStories(from stories: [Story]) -> [Story] {
        var didUpdate = false
        let result = stories.filter { story in
            for filter in activeFilters {
                if matchesFilter(story, filter: filter) {
                    filter.mutedCount += 1
                    didUpdate = true
                    return true
                }
            }
            return false
        }
        if didUpdate { save() }
        return result
    }
    
    /// Returns stories that pass all active filters (not muted).
    /// Increments muted counts for filtered-out stories and persists.
    func filteredStories(from stories: [Story]) -> [Story] {
        var didUpdate = false
        let result = stories.filter { story in
            for filter in activeFilters {
                if matchesFilter(story, filter: filter) {
                    filter.mutedCount += 1
                    didUpdate = true
                    return false
                }
            }
            return true
        }
        if didUpdate { save() }
        return result
    }
    
    /// Check if a story matches a specific filter.
    func matchesFilter(_ story: Story, filter: ContentFilter) -> Bool {
        let textsToCheck: [String]
        switch filter.matchScope {
        case .title:
            textsToCheck = [story.title]
        case .body:
            textsToCheck = [story.body]
        case .both:
            textsToCheck = [story.title, story.body]
        }
        
        for text in textsToCheck {
            if matchesText(text, keyword: filter.keyword, mode: filter.matchMode) {
                return true
            }
        }
        return false
    }
    
    /// Internal: check if text matches keyword using the given mode.
    private func matchesText(_ text: String, keyword: String, mode: ContentFilter.MatchMode) -> Bool {
        guard !text.isEmpty else { return false }
        
        switch mode {
        case .contains:
            return text.range(of: keyword, options: .caseInsensitive) != nil
            
        case .exactWord:
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b"
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                let range = NSRange(text.startIndex..., in: text)
                return regex.firstMatch(in: text, options: [], range: range) != nil
            } catch {
                return false
            }
            
        case .regex:
            do {
                let regex = try NSRegularExpression(pattern: keyword, options: [.caseInsensitive])
                let range = NSRange(text.startIndex..., in: text)
                return regex.firstMatch(in: text, options: [], range: range) != nil
            } catch {
                return false
            }
        }
    }
    
    // MARK: - Statistics
    
    /// Reset all muted counts to zero.
    func resetMutedCounts() {
        for filter in filters {
            filter.mutedCount = 0
        }
        save()
        postNotification()
    }
    
    /// Top filters by muted count (descending).
    func topFilters(limit: Int = 10) -> [ContentFilter] {
        return Array(filters.sorted { $0.mutedCount > $1.mutedCount }.prefix(limit))
    }
    
    // MARK: - Import / Export
    
    /// Export all filters as JSON string.
    func exportFilters() -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(filters),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }
    
    /// Import filters from JSON string. Skips duplicates and invalid entries.
    func importFilters(json: String) -> ImportResult {
        var result = ImportResult(added: 0, skipped: 0, errors: 0)
        
        guard let data = json.data(using: .utf8) else {
            result.errors = 1
            return result
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        guard let imported = try? decoder.decode([ContentFilter].self, from: data) else {
            result.errors = 1
            return result
        }
        
        for filter in imported {
            // Give new ID to avoid collisions
            let newFilter = ContentFilter(id: UUID().uuidString, keyword: filter.keyword,
                                          isActive: filter.isActive, matchScope: filter.matchScope,
                                          matchMode: filter.matchMode)
            if let f = newFilter {
                if addFilter(f) {
                    result.added += 1
                } else {
                    result.skipped += 1
                }
            } else {
                result.errors += 1
            }
        }
        
        return result
    }
    
    // MARK: - Persistence
    
    /// Save filters to UserDefaults using NSSecureCoding.
    private func save() {
        do {
            let data = try NSKeyedArchiver.archivedData(
                withRootObject: filters as NSArray,
                requiringSecureCoding: true
            )
            UserDefaults.standard.set(data, forKey: ContentFilterManager.userDefaultsKey)
        } catch {
            print("Failed to save content filters: \(error)")
        }
    }
    
    /// Load filters from UserDefaults.
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: ContentFilterManager.userDefaultsKey) else {
            filters = []
            return
        }
        
        if let loaded = (try? NSKeyedUnarchiver.unarchivedObject(
            ofClasses: [NSArray.self, ContentFilter.self],
            from: data
        )) as? [ContentFilter] {
            filters = loaded
        } else {
            filters = []
        }
    }
    
    // MARK: - Helpers
    
    private func postNotification() {
        NotificationCenter.default.post(name: ContentFilterManager.contentFiltersDidChangeNotification, object: nil)
    }
}
