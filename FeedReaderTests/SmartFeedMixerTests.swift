//
//  SmartFeedMixerTests.swift
//  FeedReaderTests
//
//  Tests for SmartFeedMixer.
//

import XCTest
@testable import FeedReader

class SmartFeedMixerTests: XCTestCase {

    var mixer: SmartFeedMixer!

    override func setUp() {
        super.setUp()
        // Clear stored state
        UserDefaults.standard.removeObject(forKey: "SmartFeedMixer_Weights")
        UserDefaults.standard.removeObject(forKey: "SmartFeedMixer_Presets")
        mixer = SmartFeedMixer()
    }

    // MARK: - Weight Management

    func testSetAndGetWeight() {
        mixer.setWeight(for: "TechCrunch", weight: 70)
        let fw = mixer.getWeight(for: "TechCrunch")
        XCTAssertEqual(fw.weight, 70)
        XCTAssertEqual(fw.feedName, "TechCrunch")
    }

    func testWeightClampedToRange() {
        mixer.setWeight(for: "Feed", weight: 150)
        XCTAssertEqual(mixer.getWeight(for: "Feed").weight, 100)

        mixer.setWeight(for: "Feed", weight: -10)
        XCTAssertEqual(mixer.getWeight(for: "Feed").weight, 0)
    }

    func testDefaultWeight() {
        let fw = mixer.getWeight(for: "Unknown")
        XCTAssertEqual(fw.weight, 50)
    }

    func testRemoveWeight() {
        mixer.setWeight(for: "Feed", weight: 80)
        mixer.removeWeight(for: "Feed")
        XCTAssertEqual(mixer.getWeight(for: "Feed").weight, 50) // back to default
    }

    func testEqualizeWeights() {
        mixer.setWeight(for: "A", weight: 10)
        mixer.setWeight(for: "B", weight: 90)
        mixer.equalizeWeights()
        let all = mixer.allWeights()
        XCTAssertTrue(all.allSatisfy { $0.weight == 50 })
    }

    func testPinning() {
        mixer.setPinned(for: "News", pinned: true)
        XCTAssertTrue(mixer.getWeight(for: "News").isPinned)
        mixer.setPinned(for: "News", pinned: false)
        XCTAssertFalse(mixer.getWeight(for: "News").isPinned)
    }

    // MARK: - Mixing

    private func makeArticles(_ feeds: [(String, Int)]) -> [MixableArticle] {
        var articles: [MixableArticle] = []
        for (feed, count) in feeds {
            for i in 0..<count {
                articles.append(MixableArticle(
                    title: "\(feed) Article \(i)",
                    feedName: feed,
                    publishedAt: Date().addingTimeInterval(Double(-i * 3600))
                ))
            }
        }
        return articles
    }

    func testMixEmptyArticles() {
        let result = mixer.mix(articles: [], limit: 10)
        XCTAssertTrue(result.isEmpty)
    }

    func testMixRespectsLimit() {
        let articles = makeArticles([("A", 20), ("B", 20)])
        let result = mixer.mix(articles: articles, limit: 10)
        XCTAssertEqual(result.count, 10)
    }

    func testMixWeightDistribution() {
        mixer.setWeight(for: "Heavy", weight: 80)
        mixer.setWeight(for: "Light", weight: 20)
        let articles = makeArticles([("Heavy", 30), ("Light", 30)])
        let result = mixer.mix(articles: articles, limit: 20)

        let heavyCount = result.filter { $0.feedName == "Heavy" }.count
        let lightCount = result.filter { $0.feedName == "Light" }.count

        // Heavy should have significantly more articles
        XCTAssertGreaterThan(heavyCount, lightCount)
    }

    func testPinnedFeedsAppearFirst() {
        mixer.setWeight(for: "Pinned", weight: 30)
        mixer.setPinned(for: "Pinned", pinned: true)
        mixer.setWeight(for: "Normal", weight: 70)
        let articles = makeArticles([("Pinned", 10), ("Normal", 10)])
        let result = mixer.mix(articles: articles, limit: 10)

        // First articles should be from the pinned feed
        XCTAssertEqual(result.first?.feedName, "Pinned")
    }

    // MARK: - Reading Queue

    func testGenerateReadingQueue() {
        mixer.setWeight(for: "A", weight: 50)
        mixer.setWeight(for: "B", weight: 50)
        let articles = makeArticles([("A", 10), ("B", 10)])
        let queue = mixer.generateReadingQueue(from: articles, limit: 10)

        XCTAssertEqual(queue.totalArticles, 10)
        XCTAssertFalse(queue.feedBreakdown.isEmpty)
        XCTAssertEqual(queue.feedBreakdown.reduce(0) { $0 + $1.count }, 10)
    }

    // MARK: - Presets

    func testSaveAndLoadPreset() {
        mixer.setWeight(for: "X", weight: 90)
        let _ = mixer.savePreset(name: "TestPreset")

        mixer.setWeight(for: "X", weight: 10) // change
        XCTAssertTrue(mixer.loadPreset(name: "TestPreset"))
        XCTAssertEqual(mixer.getWeight(for: "X").weight, 90)
    }

    func testLoadNonexistentPreset() {
        XCTAssertFalse(mixer.loadPreset(name: "Nope"))
    }

    func testDeletePreset() {
        let _ = mixer.savePreset(name: "ToDelete")
        mixer.deletePreset(name: "ToDelete")
        XCTAssertFalse(mixer.loadPreset(name: "ToDelete"))
    }

    func testListPresets() {
        let _ = mixer.savePreset(name: "P1")
        let _ = mixer.savePreset(name: "P2")
        XCTAssertEqual(mixer.listPresets().count, 2)
    }

    // MARK: - Discovery

    func testDiscoverFeeds() {
        let articles = makeArticles([("New1", 3), ("New2", 5)])
        let discovered = mixer.discoverFeeds(from: articles)
        XCTAssertEqual(discovered.count, 2)
        XCTAssertTrue(discovered.contains("New1"))
        XCTAssertTrue(discovered.contains("New2"))
    }

    func testDiscoverSkipsExisting() {
        mixer.setWeight(for: "Existing", weight: 60)
        let articles = makeArticles([("Existing", 5), ("Brand New", 3)])
        let discovered = mixer.discoverFeeds(from: articles)
        XCTAssertEqual(discovered, ["Brand New"])
    }

    // MARK: - Diversity Score

    func testDiversityScoreSingleFeed() {
        let articles = makeArticles([("Only", 10)])
        XCTAssertEqual(mixer.diversityScore(for: articles), 0)
    }

    func testDiversityScoreEvenDistribution() {
        mixer.setWeight(for: "A", weight: 50)
        mixer.setWeight(for: "B", weight: 50)
        let articles = makeArticles([("A", 20), ("B", 20)])
        let score = mixer.diversityScore(for: articles)
        XCTAssertGreaterThan(score, 80) // should be close to 100
    }
}
