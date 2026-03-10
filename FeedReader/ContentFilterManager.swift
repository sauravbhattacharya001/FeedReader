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
    
    /// Cached compiled regex patterns keyed by (keyword + mode rawValue).
    /// Avoids recompiling NSRegularExpression on every match call — for a feed
    /// with 100 stories and 10 regex/exactWord filters, this eliminates up to
    /// 1000 redundant compilations per filter pass.
    private var regexCache: [String: NSRegularExpression] = [:]
    
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
        let removed = filters.remove(at: index)
        // Evict stale cache entries for the removed filter's keyword
        regexCache.removeValue(forKey: "exact:\(removed.keyword)")
        regexCache.removeValue(forKey: "regex:\(removed.keyword)")
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
        invalidateRegexCache()
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
        regexCache.removeAll()
        save()
        postNotification()
    }
    
    // MARK: - Matching
    
    /// Check if a story should be muted (matches any active filter).
    /// Increments the matching filter's muted count and persists.
    ///
    /// Note: For batch operations, prefer `filteredStories(from:)` or
    /// `mutedStories(from:)` which persist once at the end. This method
    /// persists per call, suitable for single-story checks.
    func shouldMute(_ story: Story) -> Bool {
        let active = activeFilters
        for filter in active {
            if matchesFilter(story, filter: filter) {
                filter.mutedCount += 1
                save()
                return true
            }
        }
        return false
    }
    
    /// Batch version: check which stories should be muted from a list.
    /// Only persists once after processing all stories.
    func shouldMute(_ stories: [Story]) -> [Story] {
        return mutedStories(from: stories)
    }
    
    /// Returns stories that would be hidden by active filters.
    /// Increments muted counts for each matching filter and persists.
    func mutedStories(from stories: [Story]) -> [Story] {
        let (muted, _) = _partitionByFilters(stories)
        return muted
    }
    
    /// Returns stories that pass all active filters (not muted).
    /// Increments muted counts for filtered-out stories and persists.
    func filteredStories(from stories: [Story]) -> [Story] {
        let (_, passed) = _partitionByFilters(stories)
        return passed
    }
    
    /// Partition stories into (muted, passed) by active filters.
    /// Increments muted counts and persists once at the end.
    private func _partitionByFilters(_ stories: [Story]) -> (muted: [Story], passed: [Story]) {
        let active = activeFilters
        var didUpdate = false
        var muted: [Story] = []
        var passed: [Story] = []
        
        for story in stories {
            var matched = false
            for filter in active {
                if matchesFilter(story, filter: filter) {
                    filter.mutedCount += 1
                    didUpdate = true
                    matched = true
                    break
                }
            }
            if matched {
                muted.append(story)
            } else {
                passed.append(story)
            }
        }
        
        if didUpdate { save() }
        return (muted, passed)
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
    
    /// Maximum text length for regex matching (ReDoS protection).
    /// User-supplied regex patterns can exhibit catastrophic backtracking
    /// (e.g. `(a+)+$`). Capping the input size limits worst-case CPU time
    /// to a bounded value. 50 KB covers typical article bodies while
    /// preventing multi-second hangs on pathological inputs.
    private static let maxRegexInputLength = 50_000

    /// Internal: check if text matches keyword using the given mode.
    /// Uses regexCache to avoid recompiling patterns on every call.
    ///
    /// For regex/exactWord modes, input text is capped at `maxRegexInputLength`
    /// characters to mitigate ReDoS (Regular Expression Denial of Service) from
    /// user-supplied patterns with catastrophic backtracking on large inputs.
    /// The `.withoutAnchoringBounds` option is also used to prevent anchored
    /// patterns from forcing the engine to retry at every position.
    private func matchesText(_ text: String, keyword: String, mode: ContentFilter.MatchMode) -> Bool {
        guard !text.isEmpty else { return false }
        
        switch mode {
        case .contains:
            return text.range(of: keyword, options: .caseInsensitive) != nil
            
        case .exactWord:
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b"
            return _cachedRegexMatch(text: text, pattern: pattern,
                                     cacheKey: "exact:\(keyword)")
            
        case .regex:
            return _cachedRegexMatch(text: text, pattern: keyword,
                                     cacheKey: "regex:\(keyword)")
        }
    }
    
    /// Compile-and-cache a regex, then match against length-capped text.
    private func _cachedRegexMatch(text: String, pattern: String,
                                   cacheKey: String) -> Bool {
        let regex: NSRegularExpression
        if let cached = regexCache[cacheKey] {
            regex = cached
        } else {
            guard let compiled = try? NSRegularExpression(
                pattern: pattern, options: [.caseInsensitive]
            ) else { return false }
            regexCache[cacheKey] = compiled
            regex = compiled
        }
        // Cap input length for ReDoS protection
        let safeText = text.count > ContentFilterManager.maxRegexInputLength
            ? String(text.prefix(ContentFilterManager.maxRegexInputLength))
            : text
        let range = NSRange(safeText.startIndex..., in: safeText)
        return regex.firstMatch(in: safeText, options: [.withoutAnchoringBounds],
                                range: range) != nil
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
        let encoder = JSONCoding.iso8601PrettyUnsortedEncoder
        guard let data = try? encoder.encode(filters),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }
    
    /// Import filters from JSON string. Skips duplicates and invalid entries.
    func importFilters(json: String) -> ImportResult {
        // Size guard: reject input larger than 10 MB to prevent OOM
        // on adversarial or accidentally huge payloads (CWE-400).
        guard json.utf8.count <= 10_485_760 else { return ImportResult(added: 0, skipped: 0, errors: 1) }

        var result = ImportResult(added: 0, skipped: 0, errors: 0)
        
        guard let data = json.data(using: .utf8) else {
            result.errors = 1
            return result
        }
        
        let decoder = JSONCoding.iso8601Decoder
        guard let imported = try? decoder.decode([ContentFilter].self, from: data) else {
            result.errors = 1
            return result
        }
        
        for filter in imported {
            // Give new ID to avoid collisions
            let newFilter = ContentFilter(id: UUID().uuidString, keyword: filter.keyword,
                                          isActive: filter.isActive, matchScope: filter.matchScope,
                                          matchMode: filter.matchMode,
                                          createdAt: filter.createdAt, mutedCount: filter.mutedCount)
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
    
    /// Clear the compiled regex cache. Called when filter keywords change.
    private func invalidateRegexCache() {
        regexCache.removeAll()
    }
    
    private func postNotification() {
        NotificationCenter.default.post(name: ContentFilterManager.contentFiltersDidChangeNotification, object: nil)
    }
}
