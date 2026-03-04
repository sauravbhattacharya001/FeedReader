//
//  ArticleCollectionManagerTests.swift
//  FeedReaderTests
//
//  Tests for ArticleCollectionManager — named article collections.
//

import XCTest
@testable import FeedReader

class ArticleCollectionManagerTests: XCTestCase {

    var manager: ArticleCollectionManager!

    override func setUp() {
        super.setUp()
        manager = ArticleCollectionManager()
        manager.clearAll()
    }

    override func tearDown() {
        manager.clearAll()
        super.tearDown()
    }

    // MARK: - Collection Creation

    func testCreateCollection() {
        let collection = manager.createCollection(name: "Tech News")
        XCTAssertNotNil(collection)
        XCTAssertEqual(collection?.name, "Tech News")
        XCTAssertEqual(collection?.icon, "📁")
        XCTAssertTrue(collection?.articleLinks.isEmpty ?? false)
        XCTAssertEqual(manager.collections.count, 1)
    }

    func testCreateCollectionWithIconAndDescription() {
        let collection = manager.createCollection(name: "AI Papers", icon: "🤖", description: "Machine learning research")
        XCTAssertNotNil(collection)
        XCTAssertEqual(collection?.icon, "🤖")
        XCTAssertEqual(collection?.description, "Machine learning research")
    }

    func testCreateCollectionEmptyNameFails() {
        let collection = manager.createCollection(name: "")
        XCTAssertNil(collection)
        XCTAssertEqual(manager.collections.count, 0)
    }

    func testCreateCollectionWhitespaceOnlyNameFails() {
        let collection = manager.createCollection(name: "   ")
        XCTAssertNil(collection)
    }

    func testCreateCollectionTrimsWhitespace() {
        let collection = manager.createCollection(name: "  Science  ")
        XCTAssertEqual(collection?.name, "Science")
    }

    func testCreateCollectionDuplicateNameFails() {
        manager.createCollection(name: "Tech")
        let duplicate = manager.createCollection(name: "tech") // case-insensitive
        XCTAssertNil(duplicate)
        XCTAssertEqual(manager.collections.count, 1)
    }

    func testCreateCollectionNameTooLongFails() {
        let longName = String(repeating: "x", count: ArticleCollectionManager.maxNameLength + 1)
        let collection = manager.createCollection(name: longName)
        XCTAssertNil(collection)
    }

    func testCreateCollectionMaxNameLength() {
        let maxName = String(repeating: "x", count: ArticleCollectionManager.maxNameLength)
        let collection = manager.createCollection(name: maxName)
        XCTAssertNotNil(collection)
        XCTAssertEqual(collection?.name.count, ArticleCollectionManager.maxNameLength)
    }

    func testCreateCollectionDefaultIconWhenEmpty() {
        let collection = manager.createCollection(name: "Test", icon: "")
        XCTAssertEqual(collection?.icon, "📁")
    }

    func testCreateCollectionDescriptionTruncated() {
        let longDesc = String(repeating: "a", count: 300)
        let collection = manager.createCollection(name: "Test", description: longDesc)
        XCTAssertNotNil(collection)
        XCTAssertLessThanOrEqual(collection!.description.count, ArticleCollectionManager.maxDescriptionLength)
    }

    func testCreateCollectionLimit() {
        for i in 0..<ArticleCollectionManager.maxCollections {
            manager.createCollection(name: "Collection \(i)")
        }
        XCTAssertEqual(manager.collections.count, ArticleCollectionManager.maxCollections)
        let overflow = manager.createCollection(name: "Overflow")
        XCTAssertNil(overflow)
    }

    // MARK: - Collection Update

    func testUpdateCollectionName() {
        let collection = manager.createCollection(name: "Old Name")!
        let result = manager.updateCollection(id: collection.id, name: "New Name")
        XCTAssertTrue(result)
        XCTAssertEqual(manager.collection(withId: collection.id)?.name, "New Name")
    }

    func testUpdateCollectionIcon() {
        let collection = manager.createCollection(name: "Test")!
        manager.updateCollection(id: collection.id, icon: "🎯")
        XCTAssertEqual(manager.collection(withId: collection.id)?.icon, "🎯")
    }

    func testUpdateCollectionDescription() {
        let collection = manager.createCollection(name: "Test")!
        manager.updateCollection(id: collection.id, description: "New desc")
        XCTAssertEqual(manager.collection(withId: collection.id)?.description, "New desc")
    }

    func testUpdateCollectionInvalidIdFails() {
        let result = manager.updateCollection(id: "nonexistent", name: "Whatever")
        XCTAssertFalse(result)
    }

    func testUpdateCollectionDuplicateNameFails() {
        manager.createCollection(name: "A")
        let b = manager.createCollection(name: "B")!
        let result = manager.updateCollection(id: b.id, name: "a") // case-insensitive clash
        XCTAssertFalse(result)
        XCTAssertEqual(manager.collection(withId: b.id)?.name, "B") // unchanged
    }

    func testUpdateCollectionEmptyNameFails() {
        let collection = manager.createCollection(name: "Test")!
        let result = manager.updateCollection(id: collection.id, name: "")
        XCTAssertFalse(result)
        XCTAssertEqual(manager.collection(withId: collection.id)?.name, "Test")
    }

    func testUpdateCollectionUpdatesTimestamp() {
        let collection = manager.createCollection(name: "Test")!
        let originalUpdate = collection.updatedAt
        Thread.sleep(forTimeInterval: 0.01)
        manager.updateCollection(id: collection.id, name: "Updated")
        let newUpdate = manager.collection(withId: collection.id)!.updatedAt
        XCTAssertGreaterThanOrEqual(newUpdate, originalUpdate)
    }

    // MARK: - Collection Deletion

    func testDeleteCollection() {
        let collection = manager.createCollection(name: "Doomed")!
        let result = manager.deleteCollection(id: collection.id)
        XCTAssertTrue(result)
        XCTAssertEqual(manager.collections.count, 0)
    }

    func testDeleteCollectionInvalidIdFails() {
        let result = manager.deleteCollection(id: "nonexistent")
        XCTAssertFalse(result)
    }

    func testDeleteCollectionCleansUpArticleIndex() {
        let collection = manager.createCollection(name: "Test")!
        manager.addArticle(link: "https://example.com/1", toCollection: collection.id)
        manager.deleteCollection(id: collection.id)
        XCTAssertTrue(manager.collectionsContaining(articleLink: "https://example.com/1").isEmpty)
    }

    // MARK: - Collection Lookup

    func testCollectionWithId() {
        let collection = manager.createCollection(name: "Test")!
        XCTAssertNotNil(manager.collection(withId: collection.id))
        XCTAssertNil(manager.collection(withId: "nonexistent"))
    }

    func testCollectionNamed() {
        manager.createCollection(name: "Research")
        XCTAssertNotNil(manager.collection(named: "research")) // case-insensitive
        XCTAssertNil(manager.collection(named: "nonexistent"))
    }

    // MARK: - Article Management

    func testAddArticle() {
        let collection = manager.createCollection(name: "Test")!
        let result = manager.addArticle(link: "https://example.com/article1", toCollection: collection.id)
        XCTAssertTrue(result)
        XCTAssertEqual(manager.articleCount(inCollection: collection.id), 1)
    }

    func testAddArticleEmptyLinkFails() {
        let collection = manager.createCollection(name: "Test")!
        let result = manager.addArticle(link: "", toCollection: collection.id)
        XCTAssertFalse(result)
    }

    func testAddArticleInvalidCollectionFails() {
        let result = manager.addArticle(link: "https://example.com/1", toCollection: "nonexistent")
        XCTAssertFalse(result)
    }

    func testAddDuplicateArticleFails() {
        let collection = manager.createCollection(name: "Test")!
        manager.addArticle(link: "https://example.com/1", toCollection: collection.id)
        let result = manager.addArticle(link: "https://example.com/1", toCollection: collection.id)
        XCTAssertFalse(result)
        XCTAssertEqual(manager.articleCount(inCollection: collection.id), 1)
    }

    func testAddArticleToMultipleCollections() {
        let a = manager.createCollection(name: "A")!
        let b = manager.createCollection(name: "B")!
        let link = "https://example.com/shared"
        manager.addArticle(link: link, toCollection: a.id)
        manager.addArticle(link: link, toCollection: b.id)
        let containing = manager.collectionsContaining(articleLink: link)
        XCTAssertEqual(Set(containing), Set([a.id, b.id]))
    }

    func testRemoveArticle() {
        let collection = manager.createCollection(name: "Test")!
        manager.addArticle(link: "https://example.com/1", toCollection: collection.id)
        let result = manager.removeArticle(link: "https://example.com/1", fromCollection: collection.id)
        XCTAssertTrue(result)
        XCTAssertEqual(manager.articleCount(inCollection: collection.id), 0)
    }

    func testRemoveArticleNotFoundFails() {
        let collection = manager.createCollection(name: "Test")!
        let result = manager.removeArticle(link: "https://nonexistent.com", fromCollection: collection.id)
        XCTAssertFalse(result)
    }

    func testRemoveArticleUpdatesIndex() {
        let collection = manager.createCollection(name: "Test")!
        let link = "https://example.com/1"
        manager.addArticle(link: link, toCollection: collection.id)
        manager.removeArticle(link: link, fromCollection: collection.id)
        XCTAssertTrue(manager.collectionsContaining(articleLink: link).isEmpty)
    }

    func testIsArticleInCollection() {
        let collection = manager.createCollection(name: "Test")!
        let link = "https://example.com/1"
        XCTAssertFalse(manager.isArticle(link, inCollection: collection.id))
        manager.addArticle(link: link, toCollection: collection.id)
        XCTAssertTrue(manager.isArticle(link, inCollection: collection.id))
    }

    func testArticleCountInCollection() {
        let collection = manager.createCollection(name: "Test")!
        XCTAssertEqual(manager.articleCount(inCollection: collection.id), 0)
        manager.addArticle(link: "https://example.com/1", toCollection: collection.id)
        manager.addArticle(link: "https://example.com/2", toCollection: collection.id)
        XCTAssertEqual(manager.articleCount(inCollection: collection.id), 2)
    }

    func testArticleCountInvalidCollectionReturnsZero() {
        XCTAssertEqual(manager.articleCount(inCollection: "nonexistent"), 0)
    }

    // MARK: - Article Reordering

    func testMoveArticle() {
        let collection = manager.createCollection(name: "Test")!
        manager.addArticle(link: "https://a.com", toCollection: collection.id)
        manager.addArticle(link: "https://b.com", toCollection: collection.id)
        manager.addArticle(link: "https://c.com", toCollection: collection.id)

        let result = manager.moveArticle(inCollection: collection.id, from: 2, to: 0)
        XCTAssertTrue(result)

        let links = manager.collection(withId: collection.id)!.articleLinks
        XCTAssertEqual(links, ["https://c.com", "https://a.com", "https://b.com"])
    }

    func testMoveArticleSamePositionSucceeds() {
        let collection = manager.createCollection(name: "Test")!
        manager.addArticle(link: "https://a.com", toCollection: collection.id)
        let result = manager.moveArticle(inCollection: collection.id, from: 0, to: 0)
        XCTAssertTrue(result)
    }

    func testMoveArticleInvalidIndicesFails() {
        let collection = manager.createCollection(name: "Test")!
        manager.addArticle(link: "https://a.com", toCollection: collection.id)
        XCTAssertFalse(manager.moveArticle(inCollection: collection.id, from: -1, to: 0))
        XCTAssertFalse(manager.moveArticle(inCollection: collection.id, from: 0, to: 5))
        XCTAssertFalse(manager.moveArticle(inCollection: collection.id, from: 3, to: 0))
    }

    func testMoveArticleInvalidCollectionFails() {
        let result = manager.moveArticle(inCollection: "nonexistent", from: 0, to: 1)
        XCTAssertFalse(result)
    }

    // MARK: - Pinning

    func testTogglePin() {
        let collection = manager.createCollection(name: "Test")!
        XCTAssertFalse(collection.isPinned)

        let isPinned = manager.togglePin(collectionId: collection.id)
        XCTAssertTrue(isPinned)

        let isUnpinned = manager.togglePin(collectionId: collection.id)
        XCTAssertFalse(isUnpinned)
    }

    func testTogglePinInvalidIdFails() {
        let result = manager.togglePin(collectionId: "nonexistent")
        XCTAssertFalse(result)
    }

    func testSortedCollectionsPinnedFirst() {
        let a = manager.createCollection(name: "A")!
        let _ = manager.createCollection(name: "B")!
        let c = manager.createCollection(name: "C")!
        manager.togglePin(collectionId: c.id)

        let sorted = manager.sortedCollections()
        XCTAssertEqual(sorted.first?.id, c.id) // pinned first
    }

    // MARK: - Search

    func testSearchByName() {
        manager.createCollection(name: "Swift Tutorials")
        manager.createCollection(name: "Python Tips")
        let results = manager.search(query: "swift")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.name, "Swift Tutorials")
    }

    func testSearchByDescription() {
        manager.createCollection(name: "Test", description: "machine learning papers")
        let results = manager.search(query: "machine")
        XCTAssertEqual(results.count, 1)
    }

    func testSearchEmptyQueryReturnsAll() {
        manager.createCollection(name: "A")
        manager.createCollection(name: "B")
        let results = manager.search(query: "")
        XCTAssertEqual(results.count, 2)
    }

    func testSearchNoMatch() {
        manager.createCollection(name: "Test")
        let results = manager.search(query: "nonexistent")
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Merge

    func testMergeCollections() {
        let a = manager.createCollection(name: "Source")!
        let b = manager.createCollection(name: "Destination")!
        manager.addArticle(link: "https://1.com", toCollection: a.id)
        manager.addArticle(link: "https://2.com", toCollection: a.id)
        manager.addArticle(link: "https://3.com", toCollection: b.id)

        let result = manager.mergeCollection(sourceId: a.id, intoId: b.id)
        XCTAssertTrue(result)

        // Source should be deleted
        XCTAssertNil(manager.collection(withId: a.id))

        // Destination should have all 3 articles
        XCTAssertEqual(manager.articleCount(inCollection: b.id), 3)
        XCTAssertEqual(manager.collections.count, 1)
    }

    func testMergeCollectionsDeduplicates() {
        let a = manager.createCollection(name: "Source")!
        let b = manager.createCollection(name: "Dest")!
        let shared = "https://shared.com"
        manager.addArticle(link: shared, toCollection: a.id)
        manager.addArticle(link: shared, toCollection: b.id)
        manager.addArticle(link: "https://unique.com", toCollection: a.id)

        manager.mergeCollection(sourceId: a.id, intoId: b.id)
        XCTAssertEqual(manager.articleCount(inCollection: b.id), 2) // shared + unique
    }

    func testMergeSameCollectionFails() {
        let collection = manager.createCollection(name: "Test")!
        let result = manager.mergeCollection(sourceId: collection.id, intoId: collection.id)
        XCTAssertFalse(result)
    }

    // MARK: - Export / Import

    func testExportImportRoundTrip() {
        manager.createCollection(name: "Export Test", icon: "📚", description: "For testing")
        let collection = manager.collections.first!
        manager.addArticle(link: "https://example.com/1", toCollection: collection.id)

        guard let data = manager.exportAsJSON() else {
            XCTFail("Export returned nil")
            return
        }

        // Clear and re-import
        manager.clearAll()
        XCTAssertEqual(manager.collections.count, 0)

        let imported = manager.importFromJSON(data)
        XCTAssertEqual(imported, 1)
        XCTAssertEqual(manager.collections.first?.name, "Export Test")
        XCTAssertEqual(manager.collections.first?.icon, "📚")
        XCTAssertEqual(manager.collections.first?.articleLinks.count, 1)
    }

    func testImportSkipsDuplicateNames() {
        manager.createCollection(name: "Existing")

        let toImport = [ArticleCollection(
            id: UUID().uuidString, name: "Existing", icon: "📁",
            description: "", isPinned: false, articleLinks: [],
            createdAt: Date(), updatedAt: Date()
        )]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode(toImport)

        let imported = manager.importFromJSON(data)
        XCTAssertEqual(imported, 0)
        XCTAssertEqual(manager.collections.count, 1)
    }

    func testImportInvalidDataReturnsZero() {
        let result = manager.importFromJSON(Data("invalid json".utf8))
        XCTAssertEqual(result, 0)
    }

    // MARK: - Statistics

    func testStatisticsEmpty() {
        let stats = manager.statistics()
        XCTAssertEqual(stats.totalCollections, 0)
        XCTAssertEqual(stats.totalArticles, 0)
        XCTAssertEqual(stats.uniqueArticles, 0)
        XCTAssertEqual(stats.multiCollectionArticles, 0)
    }

    func testStatisticsWithData() {
        let a = manager.createCollection(name: "A")!
        let b = manager.createCollection(name: "B")!
        manager.addArticle(link: "https://1.com", toCollection: a.id)
        manager.addArticle(link: "https://2.com", toCollection: a.id)
        manager.addArticle(link: "https://1.com", toCollection: b.id) // shared

        let stats = manager.statistics()
        XCTAssertEqual(stats.totalCollections, 2)
        XCTAssertEqual(stats.totalArticles, 3) // 2 + 1
        XCTAssertEqual(stats.uniqueArticles, 2)
        XCTAssertEqual(stats.multiCollectionArticles, 1) // "1.com" in both
        XCTAssertEqual(stats.largestCollectionSize, 2)
        XCTAssertEqual(stats.averageArticlesPerCollection, 1.5, accuracy: 0.01)
    }

    func testStatisticsPinnedCount() {
        let a = manager.createCollection(name: "A")!
        manager.createCollection(name: "B")
        manager.togglePin(collectionId: a.id)
        XCTAssertEqual(manager.statistics().pinnedCollections, 1)
    }

    func testStatisticsEmptyCollections() {
        manager.createCollection(name: "Empty1")
        manager.createCollection(name: "Empty2")
        let a = manager.createCollection(name: "WithArticle")!
        manager.addArticle(link: "https://example.com", toCollection: a.id)
        XCTAssertEqual(manager.statistics().emptyCollections, 2)
    }

    // MARK: - Bulk Operations

    func testRemoveEmptyCollections() {
        manager.createCollection(name: "Empty1")
        manager.createCollection(name: "Empty2")
        let c = manager.createCollection(name: "HasArticle")!
        manager.addArticle(link: "https://example.com", toCollection: c.id)

        let removed = manager.removeEmptyCollections()
        XCTAssertEqual(removed, 2)
        XCTAssertEqual(manager.collections.count, 1)
        XCTAssertEqual(manager.collections.first?.name, "HasArticle")
    }

    func testRemoveEmptyCollectionsWhenNoneEmpty() {
        let c = manager.createCollection(name: "Test")!
        manager.addArticle(link: "https://example.com", toCollection: c.id)
        XCTAssertEqual(manager.removeEmptyCollections(), 0)
    }

    func testClearAll() {
        manager.createCollection(name: "A")
        manager.createCollection(name: "B")
        manager.clearAll()
        XCTAssertTrue(manager.collections.isEmpty)
    }

    // MARK: - Article Limit

    func testArticleLimitPerCollection() {
        let collection = manager.createCollection(name: "Test")!
        for i in 0..<ArticleCollectionManager.maxArticlesPerCollection {
            manager.addArticle(link: "https://example.com/\(i)", toCollection: collection.id)
        }
        XCTAssertEqual(manager.articleCount(inCollection: collection.id),
                       ArticleCollectionManager.maxArticlesPerCollection)

        let overflow = manager.addArticle(link: "https://example.com/overflow", toCollection: collection.id)
        XCTAssertFalse(overflow)
    }
}
