//
//  ArticleTagManager.swift
//  FeedReader
//
//  Custom article tagging system. Users can tag articles with labels
//  (e.g. "AI", "Tutorial", "Read Later") for personal organization.
//  Provides tag CRUD, article-tag associations, tag suggestions based
//  on frequency, and filtering/search by tag. Persists via NSSecureCoding.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    static let articleTagsDidChange = Notification.Name("ArticleTagsDidChangeNotification")
}

// MARK: - ArticleTag Model

/// A user-defined tag with color and metadata.
class ArticleTag: NSObject, NSSecureCoding, Codable {
    static var supportsSecureCoding: Bool { return true }
    
    /// Unique tag identifier (lowercased, trimmed).
    let id: String
    
    /// Display name (preserves original casing).
    let displayName: String
    
    /// Hex color string (e.g. "#FF5733"). Nil means default color.
    var colorHex: String?
    
    /// When this tag was created.
    let createdAt: Date
    
    /// Number of times this tag has been applied (for suggestions ranking).
    private(set) var useCount: Int
    
    init(name: String, colorHex: String? = nil) {
        self.id = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.colorHex = colorHex
        self.createdAt = Date()
        self.useCount = 0
        super.init()
    }
    
    func incrementUseCount() {
        useCount += 1
    }
    
    func decrementUseCount() {
        useCount = max(0, useCount - 1)
    }
    
    // MARK: - NSSecureCoding
    
    func encode(with coder: NSCoder) {
        coder.encode(id, forKey: "id")
        coder.encode(displayName, forKey: "displayName")
        coder.encode(colorHex, forKey: "colorHex")
        coder.encode(createdAt, forKey: "createdAt")
        coder.encode(useCount, forKey: "useCount")
    }
    
    required init?(coder: NSCoder) {
        guard let id = coder.decodeObject(of: NSString.self, forKey: "id") as String?,
              let displayName = coder.decodeObject(of: NSString.self, forKey: "displayName") as String?,
              let createdAt = coder.decodeObject(of: NSDate.self, forKey: "createdAt") as Date? else {
            return nil
        }
        self.id = id
        self.displayName = displayName
        self.colorHex = coder.decodeObject(of: NSString.self, forKey: "colorHex") as String?
        self.createdAt = createdAt
        self.useCount = coder.decodeInteger(forKey: "useCount")
        super.init()
    }
}

// MARK: - ArticleTagAssociation

/// Maps an article (by link) to its tags.
class ArticleTagAssociation: NSObject, NSSecureCoding, Codable {
    static var supportsSecureCoding: Bool { return true }
    
    /// Article URL (unique identifier).
    let articleLink: String
    
    /// Article title (for display in tag-filtered views).
    let articleTitle: String
    
    /// Feed name the article belongs to.
    let feedName: String
    
    /// Set of tag IDs applied to this article.
    var tagIds: Set<String>
    
    /// When tags were last modified on this article.
    var lastModified: Date
    
    init(articleLink: String, articleTitle: String, feedName: String, tagIds: Set<String> = []) {
        self.articleLink = articleLink
        self.articleTitle = articleTitle
        self.feedName = feedName
        self.tagIds = tagIds
        self.lastModified = Date()
        super.init()
    }
    
    // MARK: - NSSecureCoding
    
    func encode(with coder: NSCoder) {
        coder.encode(articleLink, forKey: "articleLink")
        coder.encode(articleTitle, forKey: "articleTitle")
        coder.encode(feedName, forKey: "feedName")
        coder.encode(Array(tagIds) as NSArray, forKey: "tagIds")
        coder.encode(lastModified, forKey: "lastModified")
    }
    
    required init?(coder: NSCoder) {
        guard let articleLink = coder.decodeObject(of: NSString.self, forKey: "articleLink") as String?,
              let articleTitle = coder.decodeObject(of: NSString.self, forKey: "articleTitle") as String?,
              let feedName = coder.decodeObject(of: NSString.self, forKey: "feedName") as String?,
              let tagIdsArray = coder.decodeObject(of: [NSArray.self, NSString.self], forKey: "tagIds") as? [String],
              let lastModified = coder.decodeObject(of: NSDate.self, forKey: "lastModified") as Date? else {
            return nil
        }
        self.articleLink = articleLink
        self.articleTitle = articleTitle
        self.feedName = feedName
        self.tagIds = Set(tagIdsArray)
        self.lastModified = lastModified
        super.init()
    }
}

// MARK: - ArticleTagManager

/// Manages custom article tags and article-tag associations.
/// Singleton with NSSecureCoding persistence.
class ArticleTagManager {
    
    // MARK: - Singleton
    
    static let shared = ArticleTagManager()
    
    // MARK: - Properties
    
    /// All defined tags, keyed by tag ID.
    private(set) var tags: [String: ArticleTag] = [:]
    
    /// All article-tag associations, keyed by article link.
    private(set) var associations: [String: ArticleTagAssociation] = [:]
    
    /// Reverse index: tag ID → set of article links.
    private var tagToArticles: [String: Set<String>] = [:]
    
    private static let tagsArchiveURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("articleTags")
    }()
    
    private static let associationsArchiveURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("articleTagAssociations")
    }()
    
    // MARK: - Initialization
    
    private init() {
        loadData()
        rebuildReverseIndex()
    }
    
    // MARK: - Tag CRUD
    
    /// Create a new tag. Returns the tag if created, nil if a tag with that name already exists.
    @discardableResult
    func createTag(name: String, colorHex: String? = nil) -> ArticleTag? {
        let tag = ArticleTag(name: name, colorHex: colorHex)
        guard !tag.id.isEmpty else { return nil }
        guard tags[tag.id] == nil else { return nil }
        
        tags[tag.id] = tag
        tagToArticles[tag.id] = []
        saveTags()
        postNotification()
        return tag
    }
    
    /// Delete a tag and remove it from all article associations.
    func deleteTag(id: String) {
        guard tags[id] != nil else { return }
        
        // Remove from all associations
        if let articleLinks = tagToArticles[id] {
            for link in articleLinks {
                associations[link]?.tagIds.remove(id)
                // Remove association if no tags left
                if associations[link]?.tagIds.isEmpty == true {
                    associations.removeValue(forKey: link)
                }
            }
        }
        
        tags.removeValue(forKey: id)
        tagToArticles.removeValue(forKey: id)
        saveTags()
        saveAssociations()
        postNotification()
    }
    
    /// Rename a tag (preserves associations).
    func renameTag(id: String, newName: String) -> ArticleTag? {
        guard let oldTag = tags[id] else { return nil }
        let newId = newName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !newId.isEmpty else { return nil }
        
        // If name maps to same ID, just update display name
        if newId == id {
            let updatedTag = ArticleTag(name: newName, colorHex: oldTag.colorHex)
            tags[id] = updatedTag
            saveTags()
            postNotification()
            return updatedTag
        }
        
        // If new ID already exists, can't rename
        guard tags[newId] == nil else { return nil }
        
        // Create new tag with new name, migrate associations
        let newTag = ArticleTag(name: newName, colorHex: oldTag.colorHex)
        tags[newId] = newTag
        tags.removeValue(forKey: id)
        
        // Update reverse index
        tagToArticles[newId] = tagToArticles[id]
        tagToArticles.removeValue(forKey: id)
        
        // Update associations
        for link in tagToArticles[newId] ?? [] {
            associations[link]?.tagIds.remove(id)
            associations[link]?.tagIds.insert(newId)
        }
        
        saveTags()
        saveAssociations()
        postNotification()
        return newTag
    }
    
    /// Update a tag's color.
    func setTagColor(id: String, colorHex: String?) {
        guard let tag = tags[id] else { return }
        tag.colorHex = colorHex
        saveTags()
        postNotification()
    }
    
    // MARK: - Tagging Articles
    
    /// Add a tag to an article. Creates the association if needed.
    func tagArticle(link: String, title: String, feedName: String, tagId: String) {
        guard let tag = tags[tagId] else { return }
        
        if let assoc = associations[link] {
            guard !assoc.tagIds.contains(tagId) else { return }
            assoc.tagIds.insert(tagId)
            assoc.lastModified = Date()
        } else {
            let assoc = ArticleTagAssociation(
                articleLink: link, articleTitle: title,
                feedName: feedName, tagIds: [tagId]
            )
            associations[link] = assoc
        }
        
        tag.incrementUseCount()
        tagToArticles[tagId, default: []].insert(link)
        
        saveTags()
        saveAssociations()
        postNotification()
    }
    
    /// Remove a tag from an article.
    func untagArticle(link: String, tagId: String) {
        guard let assoc = associations[link], assoc.tagIds.contains(tagId) else { return }
        
        assoc.tagIds.remove(tagId)
        assoc.lastModified = Date()
        tags[tagId]?.decrementUseCount()
        tagToArticles[tagId]?.remove(link)
        
        // Clean up empty associations
        if assoc.tagIds.isEmpty {
            associations.removeValue(forKey: link)
        }
        
        saveTags()
        saveAssociations()
        postNotification()
    }
    
    /// Get all tags for an article.
    func tagsForArticle(link: String) -> [ArticleTag] {
        guard let assoc = associations[link] else { return [] }
        return assoc.tagIds.compactMap { tags[$0] }.sorted { $0.displayName < $1.displayName }
    }
    
    /// Check if an article has a specific tag.
    func articleHasTag(link: String, tagId: String) -> Bool {
        return associations[link]?.tagIds.contains(tagId) ?? false
    }
    
    // MARK: - Querying
    
    /// Get all articles with a specific tag.
    func articlesWithTag(tagId: String) -> [ArticleTagAssociation] {
        guard let links = tagToArticles[tagId] else { return [] }
        return links.compactMap { associations[$0] }
            .sorted { $0.lastModified > $1.lastModified }
    }
    
    /// Get all articles matching ALL of the given tags (intersection).
    func articlesWithAllTags(tagIds: Set<String>) -> [ArticleTagAssociation] {
        guard !tagIds.isEmpty else { return [] }
        
        let linkSets = tagIds.compactMap { tagToArticles[$0] }
        guard linkSets.count == tagIds.count else { return [] }
        
        let intersection = linkSets.reduce(linkSets[0]) { $0.intersection($1) }
        return intersection.compactMap { associations[$0] }
            .sorted { $0.lastModified > $1.lastModified }
    }
    
    /// Get all articles matching ANY of the given tags (union).
    func articlesWithAnyTag(tagIds: Set<String>) -> [ArticleTagAssociation] {
        guard !tagIds.isEmpty else { return [] }
        
        let allLinks = tagIds.reduce(Set<String>()) { result, tagId in
            result.union(tagToArticles[tagId] ?? [])
        }
        return allLinks.compactMap { associations[$0] }
            .sorted { $0.lastModified > $1.lastModified }
    }
    
    /// Get all defined tags sorted by use count (most used first).
    func allTagsByPopularity() -> [ArticleTag] {
        return Array(tags.values).sorted { $0.useCount > $1.useCount }
    }
    
    /// Get all defined tags sorted alphabetically.
    func allTagsAlphabetical() -> [ArticleTag] {
        return Array(tags.values).sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
    
    /// Suggest tags for an article based on usage frequency.
    /// Returns the top N most-used tags that aren't already on this article.
    func suggestTags(forArticle link: String, limit: Int = 5) -> [ArticleTag] {
        let existingTagIds = associations[link]?.tagIds ?? []
        return allTagsByPopularity()
            .filter { !existingTagIds.contains($0.id) }
            .prefix(limit)
            .map { $0 }
    }
    
    /// Search tags by name (prefix match).
    func searchTags(query: String) -> [ArticleTag] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return allTagsAlphabetical() }
        return allTagsAlphabetical().filter { $0.id.contains(q) }
    }
    
    // MARK: - Statistics
    
    /// Total number of defined tags.
    var tagCount: Int { return tags.count }
    
    /// Total number of tagged articles.
    var taggedArticleCount: Int { return associations.count }
    
    /// Tag usage summary: [(tag, articleCount)].
    func tagUsageSummary() -> [(tag: ArticleTag, articleCount: Int)] {
        return allTagsByPopularity().map { tag in
            (tag: tag, articleCount: tagToArticles[tag.id]?.count ?? 0)
        }
    }
    
    // MARK: - Bulk Operations
    
    /// Remove all tags from an article.
    func removeAllTags(fromArticle link: String) {
        guard let assoc = associations[link] else { return }
        for tagId in assoc.tagIds {
            tags[tagId]?.decrementUseCount()
            tagToArticles[tagId]?.remove(link)
        }
        associations.removeValue(forKey: link)
        saveTags()
        saveAssociations()
        postNotification()
    }
    
    /// Delete all tags and associations (reset).
    func removeAll() {
        tags.removeAll()
        associations.removeAll()
        tagToArticles.removeAll()
        saveTags()
        saveAssociations()
        postNotification()
    }
    
    // MARK: - Persistence
    
    private func saveTags() {
        let tagArray = Array(tags.values)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: tagArray, requiringSecureCoding: true) {
            try? data.write(to: ArticleTagManager.tagsArchiveURL)
        }
    }
    
    private func saveAssociations() {
        let assocArray = Array(associations.values)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: assocArray, requiringSecureCoding: true) {
            try? data.write(to: ArticleTagManager.associationsArchiveURL)
        }
    }
    
    private func loadData() {
        // Load tags
        if let data = try? Data(contentsOf: ArticleTagManager.tagsArchiveURL),
           let tagArray = try? NSKeyedUnarchiver.unarchivedArrayOfObjects(ofClass: ArticleTag.self, from: data) {
            tags = Dictionary(uniqueKeysWithValues: tagArray.map { ($0.id, $0) })
        }
        
        // Load associations
        if let data = try? Data(contentsOf: ArticleTagManager.associationsArchiveURL),
           let assocArray = try? NSKeyedUnarchiver.unarchivedArrayOfObjects(ofClass: ArticleTagAssociation.self, from: data) {
            associations = Dictionary(uniqueKeysWithValues: assocArray.map { ($0.articleLink, $0) })
        }
    }
    
    private func rebuildReverseIndex() {
        tagToArticles.removeAll()
        for (_, tag) in tags {
            tagToArticles[tag.id] = []
        }
        for (link, assoc) in associations {
            for tagId in assoc.tagIds {
                tagToArticles[tagId, default: []].insert(link)
            }
        }
    }
    
    private func postNotification() {
        NotificationCenter.default.post(name: .articleTagsDidChange, object: self)
    }
}
