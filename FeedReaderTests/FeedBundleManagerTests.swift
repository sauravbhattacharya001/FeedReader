import XCTest
@testable import FeedReader

class FeedBundleManagerTests: XCTestCase {

    // MARK: - Helpers

    func makeManager() -> FeedBundleManager {
        return FeedBundleManager(testBundles: FeedBundleManager.builtInBundles())
    }

    func makeFeed(_ title: String = "Test Feed",
                  url: String = "https://example.com/feed",
                  desc: String = "A test feed") -> BundledFeed {
        return BundledFeed(title: title, url: url, description: desc)
    }

    // MARK: - Built-in Bundles

    func testBuiltInBundlesExist() {
        let bundles = FeedBundleManager.builtInBundles()
        XCTAssertGreaterThanOrEqual(bundles.count, 6)
    }

    func testAllBuiltInBundlesMarkedBuiltIn() {
        let bundles = FeedBundleManager.builtInBundles()
        for bundle in bundles {
            XCTAssertTrue(bundle.isBuiltIn, "\(bundle.name) should be built-in")
        }
    }

    func testBuiltInBundlesHaveUniqueIds() {
        let bundles = FeedBundleManager.builtInBundles()
        let ids = bundles.map { $0.id }
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testBuiltInBundlesHaveFeeds() {
        let bundles = FeedBundleManager.builtInBundles()
        for bundle in bundles {
            XCTAssertGreaterThan(bundle.feeds.count, 0,
                                "\(bundle.name) should have feeds")
        }
    }

    func testBuiltInBundlesHaveIcons() {
        let bundles = FeedBundleManager.builtInBundles()
        for bundle in bundles {
            XCTAssertFalse(bundle.icon.isEmpty, "\(bundle.name) should have an icon")
        }
    }

    // MARK: - Browse

    func testTopicsReturnsUniqueValues() {
        let mgr = makeManager()
        let topics = mgr.topics()
        XCTAssertEqual(topics.count, Set(topics).count)
    }

    func testTopicsAreSorted() {
        let mgr = makeManager()
        let topics = mgr.topics()
        XCTAssertEqual(topics, topics.sorted())
    }

    func testBundlesForTopic() {
        let mgr = makeManager()
        let tech = mgr.bundles(forTopic: "Technology")
        XCTAssertEqual(tech.count, 1)
        XCTAssertEqual(tech.first?.id, "tech-essentials")
    }

    func testBundlesForUnknownTopic() {
        let mgr = makeManager()
        let result = mgr.bundles(forTopic: "Nonexistent")
        XCTAssertTrue(result.isEmpty)
    }

    func testBundleById() {
        let mgr = makeManager()
        let bundle = mgr.bundle(withId: "ai-ml")
        XCTAssertNotNil(bundle)
        XCTAssertEqual(bundle?.name, "AI & Machine Learning")
    }

    func testBundleByIdNotFound() {
        let mgr = makeManager()
        XCTAssertNil(mgr.bundle(withId: "nonexistent"))
    }

    // MARK: - Search

    func testSearchByName() {
        let mgr = makeManager()
        let results = mgr.search(query: "developer")
        XCTAssertTrue(results.contains(where: { $0.id == "dev-tools" }))
    }

    func testSearchByTopic() {
        let mgr = makeManager()
        let results = mgr.search(query: "science")
        XCTAssertTrue(results.contains(where: { $0.id == "science-nature" }))
    }

    func testSearchByFeedTitle() {
        let mgr = makeManager()
        let results = mgr.search(query: "hacker news")
        XCTAssertTrue(results.contains(where: { $0.id == "tech-essentials" }))
    }

    func testSearchCaseInsensitive() {
        let mgr = makeManager()
        let results = mgr.search(query: "AI")
        XCTAssertTrue(results.contains(where: { $0.id == "ai-ml" }))
    }

    func testSearchNoResults() {
        let mgr = makeManager()
        let results = mgr.search(query: "zzzznonexistent")
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Subscribe

    func testSubscribeNewBundle() {
        let mgr = makeManager()
        var added: [(String, String)] = []
        let result = mgr.subscribe(
            bundleId: "tech-essentials",
            isAlreadySubscribed: { _ in false },
            addFeed: { url, title in added.append((url, title)); return true }
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.newlySubscribed, 5)
        XCTAssertEqual(result!.alreadySubscribed, 0)
        XCTAssertEqual(added.count, 5)
    }

    func testSubscribeWithExisting() {
        let mgr = makeManager()
        let result = mgr.subscribe(
            bundleId: "tech-essentials",
            isAlreadySubscribed: { $0.contains("arstechnica") },
            addFeed: { _, _ in true }
        )!
        XCTAssertEqual(result.alreadySubscribed, 1)
        XCTAssertEqual(result.newlySubscribed, 4)
    }

    func testSubscribeMarksAsSubscribed() {
        let mgr = makeManager()
        _ = mgr.subscribe(
            bundleId: "dev-tools",
            isAlreadySubscribed: { _ in false },
            addFeed: { _, _ in true }
        )
        XCTAssertTrue(mgr.isSubscribed(bundleId: "dev-tools"))
    }

    func testSubscribeNonexistentBundleReturnsNil() {
        let mgr = makeManager()
        let result = mgr.subscribe(
            bundleId: "fake",
            isAlreadySubscribed: { _ in false },
            addFeed: { _, _ in true }
        )
        XCTAssertNil(result)
    }

    func testUnsubscribe() {
        let mgr = makeManager()
        _ = mgr.subscribe(
            bundleId: "ai-ml",
            isAlreadySubscribed: { _ in false },
            addFeed: { _, _ in true }
        )
        XCTAssertTrue(mgr.unsubscribe(bundleId: "ai-ml"))
        XCTAssertFalse(mgr.isSubscribed(bundleId: "ai-ml"))
    }

    func testUnsubscribeNonSubscribedReturnsFalse() {
        let mgr = makeManager()
        XCTAssertFalse(mgr.unsubscribe(bundleId: "ai-ml"))
    }

    func testSubscribedBundleList() {
        let mgr = makeManager()
        _ = mgr.subscribe(
            bundleId: "tech-essentials",
            isAlreadySubscribed: { _ in false },
            addFeed: { _, _ in true }
        )
        _ = mgr.subscribe(
            bundleId: "ai-ml",
            isAlreadySubscribed: { _ in false },
            addFeed: { _, _ in true }
        )
        let list = mgr.subscribedBundleList()
        XCTAssertEqual(list.count, 2)
    }

    // MARK: - Custom Bundles

    func testCreateCustomBundle() {
        let mgr = makeManager()
        let bundle = mgr.createBundle(
            name: "My Reads",
            topic: "Personal",
            description: "My favorite feeds",
            icon: "⭐",
            feeds: [makeFeed("A", url: "https://a.com/feed"),
                    makeFeed("B", url: "https://b.com/feed")]
        )
        XCTAssertNotNil(bundle)
        XCTAssertFalse(bundle!.isBuiltIn)
        XCTAssertEqual(bundle!.feeds.count, 2)
        XCTAssertTrue(bundle!.id.hasPrefix("custom-"))
    }

    func testCreateBundleDeduplicatesFeeds() {
        let mgr = makeManager()
        let bundle = mgr.createBundle(
            name: "Dupes",
            topic: "Test",
            description: "",
            icon: "",
            feeds: [makeFeed("A", url: "https://a.com/feed"),
                    makeFeed("A Copy", url: "https://a.com/feed")]
        )!
        XCTAssertEqual(bundle.feeds.count, 1)
    }

    func testCreateBundleEmptyNameFails() {
        let mgr = makeManager()
        XCTAssertNil(mgr.createBundle(name: "  ", topic: "", description: "",
                                       icon: "", feeds: [makeFeed()]))
    }

    func testCreateBundleEmptyFeedsFails() {
        let mgr = makeManager()
        XCTAssertNil(mgr.createBundle(name: "Empty", topic: "", description: "",
                                       icon: "", feeds: []))
    }

    func testCreateBundleDefaultsEmptyTopicToCustom() {
        let mgr = makeManager()
        let bundle = mgr.createBundle(
            name: "No Topic", topic: "", description: "",
            icon: "", feeds: [makeFeed()]
        )!
        XCTAssertEqual(bundle.topic, "Custom")
    }

    func testCreateBundleDefaultsEmptyIconToPackage() {
        let mgr = makeManager()
        let bundle = mgr.createBundle(
            name: "No Icon", topic: "", description: "",
            icon: "", feeds: [makeFeed()]
        )!
        XCTAssertEqual(bundle.icon, "📦")
    }

    func testDeleteCustomBundle() {
        let mgr = makeManager()
        let bundle = mgr.createBundle(
            name: "Temp", topic: "Test", description: "",
            icon: "", feeds: [makeFeed()]
        )!
        XCTAssertTrue(mgr.deleteBundle(id: bundle.id))
        XCTAssertNil(mgr.bundle(withId: bundle.id))
    }

    func testDeleteBuiltInBundleFails() {
        let mgr = makeManager()
        XCTAssertFalse(mgr.deleteBundle(id: "tech-essentials"))
    }

    func testDeleteNonexistentBundleFails() {
        let mgr = makeManager()
        XCTAssertFalse(mgr.deleteBundle(id: "nonexistent"))
    }

    // MARK: - Add/Remove Feeds

    func testAddFeedToCustomBundle() {
        let mgr = makeManager()
        let bundle = mgr.createBundle(
            name: "Editable", topic: "", description: "",
            icon: "", feeds: [makeFeed("A", url: "https://a.com/feed")]
        )!
        let added = mgr.addFeed(
            makeFeed("B", url: "https://b.com/feed"),
            toBundleId: bundle.id
        )
        XCTAssertTrue(added)
        XCTAssertEqual(mgr.bundle(withId: bundle.id)!.feeds.count, 2)
    }

    func testAddDuplicateFeedFails() {
        let mgr = makeManager()
        let bundle = mgr.createBundle(
            name: "Editable", topic: "", description: "",
            icon: "", feeds: [makeFeed("A", url: "https://a.com/feed")]
        )!
        XCTAssertFalse(mgr.addFeed(
            makeFeed("A Again", url: "https://a.com/feed"),
            toBundleId: bundle.id
        ))
    }

    func testAddFeedToBuiltInBundleFails() {
        let mgr = makeManager()
        XCTAssertFalse(mgr.addFeed(makeFeed(), toBundleId: "tech-essentials"))
    }

    func testRemoveFeedFromCustomBundle() {
        let mgr = makeManager()
        let bundle = mgr.createBundle(
            name: "Editable", topic: "", description: "",
            icon: "", feeds: [makeFeed("A", url: "https://a.com/feed"),
                              makeFeed("B", url: "https://b.com/feed")]
        )!
        XCTAssertTrue(mgr.removeFeed(url: "https://a.com/feed",
                                      fromBundleId: bundle.id))
        XCTAssertEqual(mgr.bundle(withId: bundle.id)!.feeds.count, 1)
    }

    func testRemoveFeedFromBuiltInFails() {
        let mgr = makeManager()
        let url = mgr.bundles.first!.feeds.first!.url
        XCTAssertFalse(mgr.removeFeed(url: url, fromBundleId: mgr.bundles.first!.id))
    }

    func testRemoveNonexistentFeedFails() {
        let mgr = makeManager()
        let bundle = mgr.createBundle(
            name: "Test", topic: "", description: "",
            icon: "", feeds: [makeFeed()]
        )!
        XCTAssertFalse(mgr.removeFeed(url: "https://fake.com", fromBundleId: bundle.id))
    }

    // MARK: - Export / Import

    func testExportBundle() {
        let mgr = makeManager()
        let data = mgr.exportBundle(id: "tech-essentials")
        XCTAssertNotNil(data)
        let json = String(data: data!, encoding: .utf8)!
        XCTAssertTrue(json.contains("Tech Essentials"))
    }

    func testExportNonexistentReturnsNil() {
        let mgr = makeManager()
        XCTAssertNil(mgr.exportBundle(id: "nonexistent"))
    }

    func testImportBundle() {
        let mgr = makeManager()
        let data = mgr.exportBundle(id: "ai-ml")!
        let before = mgr.bundles.count
        let imported = mgr.importBundle(from: data)
        XCTAssertNotNil(imported)
        XCTAssertTrue(imported!.id.hasPrefix("imported-"))
        XCTAssertFalse(imported!.isBuiltIn)
        XCTAssertEqual(mgr.bundles.count, before + 1)
    }

    func testImportInvalidDataReturnsNil() {
        let mgr = makeManager()
        let bad = "not json".data(using: .utf8)!
        XCTAssertNil(mgr.importBundle(from: bad))
    }

    func testRoundTripExportImport() {
        let mgr = makeManager()
        let original = mgr.bundle(withId: "science-nature")!
        let data = mgr.exportBundle(id: "science-nature")!
        let imported = mgr.importBundle(from: data)!
        XCTAssertEqual(imported.name, original.name)
        XCTAssertEqual(imported.feeds.count, original.feeds.count)
        XCTAssertEqual(imported.topic, original.topic)
    }

    // MARK: - Statistics

    func testTotalUniqueFeedCount() {
        let mgr = makeManager()
        let count = mgr.totalUniqueFeedCount()
        // 6 bundles with 4-5 feeds each, all unique URLs
        XCTAssertGreaterThanOrEqual(count, 20)
    }

    func testBundlesPerTopic() {
        let mgr = makeManager()
        let perTopic = mgr.bundlesPerTopic()
        XCTAssertEqual(perTopic["Technology"], 1)
        XCTAssertEqual(perTopic["AI"], 1)
    }

    // MARK: - Model Equatable

    func testBundledFeedEquality() {
        let a = BundledFeed(title: "A", url: "https://a.com", description: "x")
        let b = BundledFeed(title: "B", url: "https://a.com", description: "y")
        XCTAssertEqual(a, b) // Same URL = equal
    }

    func testBundledFeedInequality() {
        let a = BundledFeed(title: "A", url: "https://a.com", description: "x")
        let b = BundledFeed(title: "A", url: "https://b.com", description: "x")
        XCTAssertNotEqual(a, b)
    }

    func testFeedBundleEquality() {
        let bundles = FeedBundleManager.builtInBundles()
        XCTAssertEqual(bundles[0], bundles[0])
        XCTAssertNotEqual(bundles[0], bundles[1])
    }
}
