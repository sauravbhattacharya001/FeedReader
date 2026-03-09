//
//  ArticleCollectionManager.swift
//  FeedReader
//
//  Organizes articles into named collections (like playlists for articles).
//  Users can create collections by topic, project, or any theme, then
//  add/remove articles from them. Supports reordering, collection icons,
//  descriptions, pinning, JSON export/import, and merge operations.
//
//  Persistence: UserDefaults (collection metadata) + NSKeyedArchiver (articles).
//  Each collection stores its articles independently from BookmarkManager.
//

import UIKit

// MARK: - Notifications

extension Notification.Name {
    /// Posted when any collection is created, modified, or deleted.
    static let collectionsDidChange = Notification.Name("ArticleCollectionsDidChangeNotification")
}

// MARK: - ArticleCollection

/// A named group of articles with optional metadata.
struct ArticleCollection: Codable, Equatable {
    let id: String
    var name: String
    var icon: String           // emoji icon
    var description: String
    var isPinned: Bool
    var articleLinks: [String]  // ordered list of article link URLs
    let createdAt: Date
    var updatedAt: Date

    static func == (lhs: ArticleCollection, rhs: ArticleCollection) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - ArticleCollectionManager

class ArticleCollectionManager {

    // MARK: - Singleton

    static let shared = ArticleCollectionManager()

    // MARK: - Constants

    static let maxCollections = 100
    static let maxArticlesPerCollection = 500
    static let maxNameLength = 60
    static let maxDescriptionLength = 200

    // MARK: - Properties

    private(set) var collections: [ArticleCollection] = []

    /// O(1) lookup: articleLink → set of collection IDs containing it.
    private var articleIndex: [String: Set<String>] = [:]

    private let metadataKey = "feedreader_collections_metadata"

    // MARK: - Initialization

    init() {
        loadCollections()
    }

    // MARK: - Collection CRUD

    /// Create a new collection. Returns the created collection, or nil if limit reached
    /// or name is empty/duplicate.
    @discardableResult
    func createCollection(name: String, icon: String = "📁", description: String = "") -> ArticleCollection? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        guard trimmedName.count <= ArticleCollectionManager.maxNameLength else { return nil }
        guard collections.count < ArticleCollectionManager.maxCollections else { return nil }

        // Reject duplicate names (case-insensitive)
        let lowerName = trimmedName.lowercased()
        guard !collections.contains(where: { $0.name.lowercased() == lowerName }) else { return nil }

        let trimmedDesc = String(description.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(ArticleCollectionManager.maxDescriptionLength))
        let trimmedIcon = icon.isEmpty ? "📁" : String(icon.prefix(2))

        let collection = ArticleCollection(
            id: UUID().uuidString,
            name: trimmedName,
            icon: trimmedIcon,
            description: trimmedDesc,
            isPinned: false,
            articleLinks: [],
            createdAt: Date(),
            updatedAt: Date()
        )

        collections.append(collection)
        saveCollections()
        NotificationCenter.default.post(name: .collectionsDidChange, object: nil)
        return collection
    }

    /// Update a collection's metadata (name, icon, description).
    /// Returns true if the update succeeded.
    @discardableResult
    func updateCollection(id: String, name: String? = nil, icon: String? = nil, description: String? = nil) -> Bool {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return false }

        if let newName = name {
            let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { return false }
            guard trimmedName.count <= ArticleCollectionManager.maxNameLength else { return false }

            // Check for duplicate names (excluding self)
            let lowerName = trimmedName.lowercased()
            let isDuplicate = collections.contains(where: {
                $0.id != id && $0.name.lowercased() == lowerName
            })
            guard !isDuplicate else { return false }

            collections[index].name = trimmedName
        }

        if let newIcon = icon {
            collections[index].icon = newIcon.isEmpty ? "📁" : String(newIcon.prefix(2))
        }

        if let newDesc = description {
            collections[index].description = String(newDesc.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(ArticleCollectionManager.maxDescriptionLength))
        }

        collections[index].updatedAt = Date()
        saveCollections()
        NotificationCenter.default.post(name: .collectionsDidChange, object: nil)
        return true
    }

    /// Delete a collection by ID. Returns true if found and removed.
    @discardableResult
    func deleteCollection(id: String) -> Bool {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return false }

        let removed = collections.remove(at: index)
        // Clean up article index
        for link in removed.articleLinks {
            articleIndex[link]?.remove(id)
            if articleIndex[link]?.isEmpty == true {
                articleIndex.removeValue(forKey: link)
            }
        }

        saveCollections()
        NotificationCenter.default.post(name: .collectionsDidChange, object: nil)
        return true
    }

    /// Get a collection by ID.
    func collection(withId id: String) -> ArticleCollection? {
        return collections.first(where: { $0.id == id })
    }

    /// Get a collection by name (case-insensitive).
    func collection(named name: String) -> ArticleCollection? {
        let lower = name.lowercased()
        return collections.first(where: { $0.name.lowercased() == lower })
    }

    // MARK: - Article Management

    /// Add an article to a collection. Returns true if added (not already present).
    @discardableResult
    func addArticle(link: String, toCollection collectionId: String) -> Bool {
        guard let index = collections.firstIndex(where: { $0.id == collectionId }) else { return false }
        guard !link.isEmpty else { return false }
        guard collections[index].articleLinks.count < ArticleCollectionManager.maxArticlesPerCollection else { return false }

        // Already in this collection?
        guard !collections[index].articleLinks.contains(link) else { return false }

        collections[index].articleLinks.append(link)
        collections[index].updatedAt = Date()

        // Update reverse index
        if articleIndex[link] == nil {
            articleIndex[link] = Set<String>()
        }
        articleIndex[link]?.insert(collectionId)

        saveCollections()
        NotificationCenter.default.post(name: .collectionsDidChange, object: nil)
        return true
    }

    /// Remove an article from a collection. Returns true if found and removed.
    @discardableResult
    func removeArticle(link: String, fromCollection collectionId: String) -> Bool {
        guard let index = collections.firstIndex(where: { $0.id == collectionId }) else { return false }
        guard let articleIdx = collections[index].articleLinks.firstIndex(of: link) else { return false }

        collections[index].articleLinks.remove(at: articleIdx)
        collections[index].updatedAt = Date()

        // Update reverse index
        articleIndex[link]?.remove(collectionId)
        if articleIndex[link]?.isEmpty == true {
            articleIndex.removeValue(forKey: link)
        }

        saveCollections()
        NotificationCenter.default.post(name: .collectionsDidChange, object: nil)
        return true
    }

    /// Move an article within a collection (reorder).
    @discardableResult
    func moveArticle(inCollection collectionId: String, from sourceIndex: Int, to destinationIndex: Int) -> Bool {
        guard let index = collections.firstIndex(where: { $0.id == collectionId }) else { return false }
        let count = collections[index].articleLinks.count
        guard sourceIndex >= 0 && sourceIndex < count else { return false }
        guard destinationIndex >= 0 && destinationIndex < count else { return false }
        guard sourceIndex != destinationIndex else { return true }

        let link = collections[index].articleLinks.remove(at: sourceIndex)
        collections[index].articleLinks.insert(link, at: destinationIndex)
        collections[index].updatedAt = Date()

        saveCollections()
        NotificationCenter.default.post(name: .collectionsDidChange, object: nil)
        return true
    }

    /// Get all collection IDs containing a given article.
    func collectionsContaining(articleLink: String) -> [String] {
        return Array(articleIndex[articleLink] ?? [])
    }

    /// Check if an article is in a specific collection.
    func isArticle(_ link: String, inCollection collectionId: String) -> Bool {
        return articleIndex[link]?.contains(collectionId) == true
    }

    /// Number of articles in a collection.
    func articleCount(inCollection collectionId: String) -> Int {
        return collections.first(where: { $0.id == collectionId })?.articleLinks.count ?? 0
    }

    // MARK: - Pinning

    /// Toggle pinned state. Pinned collections sort to the top.
    @discardableResult
    func togglePin(collectionId: String) -> Bool {
        guard let index = collections.firstIndex(where: { $0.id == collectionId }) else { return false }
        collections[index].isPinned.toggle()
        collections[index].updatedAt = Date()

        saveCollections()
        NotificationCenter.default.post(name: .collectionsDidChange, object: nil)
        return collections[index].isPinned
    }

    /// Get collections sorted: pinned first, then by updatedAt descending.
    func sortedCollections() -> [ArticleCollection] {
        return collections.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.updatedAt > b.updatedAt
        }
    }

    // MARK: - Search

    /// Search collections by name or description (case-insensitive substring match).
    func search(query: String) -> [ArticleCollection] {
        let lower = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return collections }

        return collections.filter {
            $0.name.lowercased().contains(lower) ||
            $0.description.lowercased().contains(lower)
        }
    }

    // MARK: - Merge

    /// Merge one collection into another, deduplicating articles. Source is deleted.
    /// Returns true if successful.
    @discardableResult
    func mergeCollection(sourceId: String, intoId destinationId: String) -> Bool {
        guard sourceId != destinationId else { return false }
        guard let srcIndex = collections.firstIndex(where: { $0.id == sourceId }) else { return false }
        guard let dstIndex = collections.firstIndex(where: { $0.id == destinationId }) else { return false }

        let sourceLinks = collections[srcIndex].articleLinks
        let existingSet = Set(collections[dstIndex].articleLinks)
        var addedCount = 0

        for link in sourceLinks {
            if !existingSet.contains(link) &&
               collections[dstIndex].articleLinks.count < ArticleCollectionManager.maxArticlesPerCollection {
                collections[dstIndex].articleLinks.append(link)
                if articleIndex[link] == nil {
                    articleIndex[link] = Set<String>()
                }
                articleIndex[link]?.insert(destinationId)
                addedCount += 1
            }
        }

        collections[dstIndex].updatedAt = Date()

        // Remove source collection
        let removed = collections.remove(at: collections.firstIndex(where: { $0.id == sourceId })!)
        for link in removed.articleLinks {
            articleIndex[link]?.remove(sourceId)
            if articleIndex[link]?.isEmpty == true {
                articleIndex.removeValue(forKey: link)
            }
        }

        saveCollections()
        NotificationCenter.default.post(name: .collectionsDidChange, object: nil)
        return true
    }

    // MARK: - Export / Import

    /// Export all collections as JSON data.
    func exportAsJSON() -> Data? {
        let encoder = JSONCoding.iso8601PrettyEncoder
        return try? encoder.encode(collections)
    }

    /// Import collections from JSON data. Skips collections with duplicate names.
    /// Returns the number of collections imported.
    @discardableResult
    func importFromJSON(_ data: Data) -> Int {
        let decoder = JSONCoding.iso8601Decoder
        guard let imported = try? decoder.decode([ArticleCollection].self, from: data) else { return 0 }

        var importedCount = 0
        for var collection in imported {
            // Skip if name already exists
            let lowerName = collection.name.lowercased()
            guard !collections.contains(where: { $0.name.lowercased() == lowerName }) else { continue }
            guard collections.count < ArticleCollectionManager.maxCollections else { break }

            // Assign new ID to avoid conflicts
            collection = ArticleCollection(
                id: UUID().uuidString,
                name: String(collection.name.prefix(ArticleCollectionManager.maxNameLength)),
                icon: collection.icon.isEmpty ? "📁" : String(collection.icon.prefix(2)),
                description: String(collection.description.prefix(ArticleCollectionManager.maxDescriptionLength)),
                isPinned: collection.isPinned,
                articleLinks: Array(collection.articleLinks.prefix(ArticleCollectionManager.maxArticlesPerCollection)),
                createdAt: collection.createdAt,
                updatedAt: Date()
            )

            collections.append(collection)

            // Update article index
            for link in collection.articleLinks {
                if articleIndex[link] == nil {
                    articleIndex[link] = Set<String>()
                }
                articleIndex[link]?.insert(collection.id)
            }

            importedCount += 1
        }

        if importedCount > 0 {
            saveCollections()
            NotificationCenter.default.post(name: .collectionsDidChange, object: nil)
        }

        return importedCount
    }

    // MARK: - Statistics

    /// Summary statistics across all collections.
    func statistics() -> CollectionStatistics {
        let totalArticles = collections.reduce(0) { $0 + $1.articleLinks.count }
        let pinnedCount = collections.filter { $0.isPinned }.count
        let emptyCount = collections.filter { $0.articleLinks.isEmpty }.count

        // Articles appearing in multiple collections
        let multiCollectionArticles = articleIndex.values.filter { $0.count > 1 }.count

        let avgArticles = collections.isEmpty ? 0.0 : Double(totalArticles) / Double(collections.count)
        let maxArticles = collections.map { $0.articleLinks.count }.max() ?? 0

        return CollectionStatistics(
            totalCollections: collections.count,
            totalArticles: totalArticles,
            uniqueArticles: articleIndex.count,
            multiCollectionArticles: multiCollectionArticles,
            pinnedCollections: pinnedCount,
            emptyCollections: emptyCount,
            averageArticlesPerCollection: avgArticles,
            largestCollectionSize: maxArticles
        )
    }

    // MARK: - Bulk Operations

    /// Remove all empty collections. Returns the number removed.
    @discardableResult
    func removeEmptyCollections() -> Int {
        let emptyIds = collections.filter { $0.articleLinks.isEmpty }.map { $0.id }
        guard !emptyIds.isEmpty else { return 0 }

        collections.removeAll { $0.articleLinks.isEmpty }
        saveCollections()
        NotificationCenter.default.post(name: .collectionsDidChange, object: nil)
        return emptyIds.count
    }

    /// Clear all collections.
    func clearAll() {
        collections.removeAll()
        articleIndex.removeAll()
        saveCollections()
        NotificationCenter.default.post(name: .collectionsDidChange, object: nil)
    }

    // MARK: - Persistence

    private func saveCollections() {
        let encoder = JSONCoding.iso8601Encoder
        if let data = try? encoder.encode(collections) {
            UserDefaults.standard.set(data, forKey: metadataKey)
        }
    }

    private func loadCollections() {
        guard let data = UserDefaults.standard.data(forKey: metadataKey) else {
            collections = []
            articleIndex = [:]
            return
        }

        let decoder = JSONCoding.iso8601Decoder
        if let loaded = try? decoder.decode([ArticleCollection].self, from: data) {
            collections = loaded
            rebuildArticleIndex()
        } else {
            collections = []
            articleIndex = [:]
        }
    }

    private func rebuildArticleIndex() {
        articleIndex = [:]
        for collection in collections {
            for link in collection.articleLinks {
                if articleIndex[link] == nil {
                    articleIndex[link] = Set<String>()
                }
                articleIndex[link]?.insert(collection.id)
            }
        }
    }

    /// Force a reload from disk.
    func reload() {
        loadCollections()
    }
}

// MARK: - CollectionStatistics

struct CollectionStatistics {
    let totalCollections: Int
    let totalArticles: Int
    let uniqueArticles: Int
    let multiCollectionArticles: Int
    let pinnedCollections: Int
    let emptyCollections: Int
    let averageArticlesPerCollection: Double
    let largestCollectionSize: Int
}
