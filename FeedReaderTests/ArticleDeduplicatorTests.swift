//
//  ArticleDeduplicatorTests.swift
//  FeedReaderTests
//
//  Tests for ArticleDeduplicator - multi-signal duplicate detection.
//

import XCTest
@testable import FeedReader

class ArticleDeduplicatorTests: XCTestCase {

    var dedup: ArticleDeduplicator!

    override func setUp() {
        super.setUp()
        dedup = ArticleDeduplicator()
    }

    override func tearDown() {
        dedup = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeStory(
        title: String,
        body: String = "This is a test article body with enough content.",
        link: String,
        feedName: String = "TestFeed"
    ) -> Story {
        let story = Story(title: title, photo: nil, description: body, link: link)!
        story.sourceFeedName = feedName
        return story
    }

    // MARK: - Initialization

    func testDefaultThresholds() {
        let d = ArticleDeduplicator()
        XCTAssertEqual(d.threshold, 0.6, accuracy: 0.001)
        XCTAssertEqual(d.ngramSize, 3)
        XCTAssertEqual(d.fingerprintTermCount, 20)
        let sum = d.titleWeight + d.contentWeight + d.urlWeight
        XCTAssertEqual(sum, 1.0, accuracy: 0.001)
    }

    func testCustomThresholds() {
        let d = ArticleDeduplicator(threshold: 0.8, titleWeight: 1.0, contentWeight: 0.0, urlWeight: 0.0)
        XCTAssertEqual(d.threshold, 0.8, accuracy: 0.001)
        XCTAssertEqual(d.titleWeight, 1.0, accuracy: 0.001)
        XCTAssertEqual(d.contentWeight, 0.0, accuracy: 0.001)
    }

    func testThresholdClampedToRange() {
        let high = ArticleDeduplicator(threshold: 2.0)
        XCTAssertEqual(high.threshold, 1.0, accuracy: 0.001)
        let low = ArticleDeduplicator(threshold: -0.5)
        XCTAssertEqual(low.threshold, 0.0, accuracy: 0.001)
    }

    func testZeroWeightsDefaultToEqual() {
        let d = ArticleDeduplicator(titleWeight: 0.0, contentWeight: 0.0, urlWeight: 0.0)
        let sum = d.titleWeight + d.contentWeight + d.urlWeight
        XCTAssertEqual(sum, 1.0, accuracy: 0.001)
    }

    func testMinNgramSize() {
        let d = ArticleDeduplicator(ngramSize: 1)
        XCTAssertEqual(d.ngramSize, 2)
    }

    func testMinFingerprintTermCount() {
        let d = ArticleDeduplicator(fingerprintTermCount: 1)
        XCTAssertEqual(d.fingerprintTermCount, 5)
    }

    // MARK: - Indexing

    func testIndexSingleStory() {
        let story = makeStory(title: "Test Article", link: "https://example.com/1")
        dedup.indexStory(story)
        XCTAssertEqual(dedup.count, 1)
    }

    func testIndexBatch() {
        let stories = [
            makeStory(title: "Article One", link: "https://a.com/1"),
            makeStory(title: "Article Two", link: "https://a.com/2"),
            makeStory(title: "Article Three", link: "https://a.com/3"),
        ]
        dedup.index(stories)
        XCTAssertEqual(dedup.count, 3)
    }

    func testDuplicateLinkNotReindexed() {
        let story = makeStory(title: "Test", link: "https://example.com/1")
        dedup.indexStory(story)
        dedup.indexStory(story)
        XCTAssertEqual(dedup.count, 1)
    }

    func testRemoveStory() {
        let story = makeStory(title: "Test", link: "https://example.com/1")
        dedup.indexStory(story)
        dedup.removeStory(link: "https://example.com/1")
        XCTAssertEqual(dedup.count, 0)
    }

    func testReset() {
        dedup.index([
            makeStory(title: "A", link: "https://a.com/1"),
            makeStory(title: "B", link: "https://a.com/2"),
        ])
        dedup.reset()
        XCTAssertEqual(dedup.count, 0)
    }

    // MARK: - Text Normalization

    func testNormalizeTextLowercases() {
        let result = dedup.normalizeText("HELLO World")
        XCTAssertEqual(result, "hello world")
    }

    func testNormalizeTextStripsPunctuation() {
        let result = dedup.normalizeText("Hello, World! How's it going?")
        XCTAssertEqual(result, "hello world how s it going")
    }

    func testNormalizeTextCollapsesWhitespace() {
        let result = dedup.normalizeText("  hello    world  ")
        XCTAssertEqual(result, "hello world")
    }

    func testNormalizeTextPreservesNumbers() {
        let result = dedup.normalizeText("Version 2.5 Released!")
        XCTAssertEqual(result, "version 2 5 released")
    }

    func testNormalizeEmptyString() {
        let result = dedup.normalizeText("")
        XCTAssertEqual(result, "")
    }

    // MARK: - Character N-grams

    func testNgramsBasic() {
        let ngrams = dedup.characterNgrams("hello", n: 3)
        XCTAssertEqual(ngrams, Set(["hel", "ell", "llo"]))
    }

    func testNgramsTooShort() {
        let ngrams = dedup.characterNgrams("hi", n: 3)
        XCTAssertEqual(ngrams, Set(["hi"]))
    }

    func testNgramsEmpty() {
        let ngrams = dedup.characterNgrams("", n: 3)
        XCTAssertTrue(ngrams.isEmpty)
    }

    func testNgramsExactLength() {
        let ngrams = dedup.characterNgrams("abc", n: 3)
        XCTAssertEqual(ngrams, Set(["abc"]))
    }

    // MARK: - Top Terms Extraction

    func testExtractTopTermsBasic() {
        let text = "apple banana apple cherry apple banana"
        let terms = dedup.extractTopTerms(text, count: 2)
        XCTAssertEqual(terms["apple"], 3)
        XCTAssertEqual(terms["banana"], 2)
        XCTAssertNil(terms["cherry"])
    }

    func testExtractTopTermsFiltersStopWords() {
        let text = "the quick brown fox and the lazy dog the fox"
        let terms = dedup.extractTopTerms(text, count: 10)
        XCTAssertNil(terms["the"])
        XCTAssertNil(terms["and"])
        XCTAssertNotNil(terms["quick"])
        XCTAssertNotNil(terms["brown"])
        XCTAssertEqual(terms["fox"], 2)
    }

    func testExtractTopTermsFiltersShortWords() {
        let text = "go to be or not to be"
        let terms = dedup.extractTopTerms(text, count: 10)
        XCTAssertTrue(terms.isEmpty)
    }

    // MARK: - Domain Path Extraction

    func testExtractDomainPathBasic() {
        let result = dedup.extractDomainPath("https://example.com/articles/hello")
        XCTAssertEqual(result, "example.com/articles/hello")
    }

    func testExtractDomainPathStripsWWW() {
        let result = dedup.extractDomainPath("https://www.example.com/page")
        XCTAssertEqual(result, "example.com/page")
    }

    func testExtractDomainPathInvalidURL() {
        let result = dedup.extractDomainPath("not-a-url")
        XCTAssertEqual(result, "not-a-url")
    }

    // MARK: - Jaccard Similarity

    func testJaccardIdenticalSets() {
        let a: Set<String> = ["a", "b", "c"]
        let sim = dedup.jaccardSimilarity(a, a)
        XCTAssertEqual(sim, 1.0, accuracy: 0.001)
    }

    func testJaccardDisjointSets() {
        let a: Set<String> = ["a", "b"]
        let b: Set<String> = ["c", "d"]
        let sim = dedup.jaccardSimilarity(a, b)
        XCTAssertEqual(sim, 0.0, accuracy: 0.001)
    }

    func testJaccardPartialOverlap() {
        let a: Set<String> = ["a", "b", "c"]
        let b: Set<String> = ["b", "c", "d"]
        let sim = dedup.jaccardSimilarity(a, b)
        XCTAssertEqual(sim, 0.5, accuracy: 0.001)
    }

    func testJaccardEmptySets() {
        let sim = dedup.jaccardSimilarity(Set<String>(), Set<String>())
        XCTAssertEqual(sim, 0.0, accuracy: 0.001)
    }

    // MARK: - Term Overlap

    func testTermOverlapIdentical() {
        let terms: [String: Int] = ["apple": 3, "banana": 2]
        let sim = dedup.termOverlap(terms, terms)
        XCTAssertGreaterThan(sim, 0.9)
    }

    func testTermOverlapDisjoint() {
        let a: [String: Int] = ["apple": 3]
        let b: [String: Int] = ["banana": 2]
        let sim = dedup.termOverlap(a, b)
        XCTAssertEqual(sim, 0.0, accuracy: 0.001)
    }

    func testTermOverlapEmpty() {
        let sim = dedup.termOverlap([:], [:])
        XCTAssertEqual(sim, 0.0, accuracy: 0.001)
    }

    // MARK: - URL Similarity

    func testUrlSimilarityExactMatch() {
        let sim = dedup.urlSimilarity("example.com/article/1", "example.com/article/1")
        XCTAssertEqual(sim, 1.0, accuracy: 0.001)
    }

    func testUrlSimilarityDifferentDomainDifferentPath() {
        let sim = dedup.urlSimilarity("foo.com/aaa", "bar.com/zzz")
        XCTAssertEqual(sim, 0.0, accuracy: 0.001)
    }

    func testUrlSimilarityEmpty() {
        let sim = dedup.urlSimilarity("", "")
        XCTAssertEqual(sim, 0.0, accuracy: 0.001)
    }

    func testUrlSimilaritySameDomainDifferentPath() {
        let sim = dedup.urlSimilarity("example.com/path-a", "example.com/path-b")
        XCTAssertGreaterThan(sim, 0.3)
    }

    // MARK: - Duplicate Detection

    func testIdenticalArticlesDetected() {
        let body = "This is a substantial article body about technology and artificial intelligence in modern computing"
        dedup.index([
            makeStory(title: "Breaking: AI Takes Over", body: body, link: "https://a.com/1", feedName: "Feed A"),
            makeStory(title: "Breaking: AI Takes Over", body: body, link: "https://b.com/1", feedName: "Feed B"),
        ])
        let result = dedup.findDuplicates()
        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(result.duplicateCount, 1)
        XCTAssertEqual(result.groups[0].memberLinks.count, 2)
    }

    func testNearDuplicateTitlesDetected() {
        let body = "The technology conference featured presentations about machine learning algorithms and neural network architectures for natural language processing"
        dedup = ArticleDeduplicator(threshold: 0.4)
        dedup.index([
            makeStory(title: "Tech Conference: AI Breakthrough Announced Today", body: body, link: "https://a.com/1"),
            makeStory(title: "Tech Conference: Major AI Breakthrough Announced", body: body, link: "https://b.com/1"),
        ])
        let result = dedup.findDuplicates()
        XCTAssertEqual(result.groups.count, 1)
    }

    func testCompletelyDifferentArticlesNotGrouped() {
        dedup.index([
            makeStory(title: "Weather Forecast for Tomorrow", body: "Heavy rain expected across the eastern seaboard with flooding concerns in low-lying areas", link: "https://weather.com/1"),
            makeStory(title: "Stock Market Analysis Report", body: "Technology stocks rallied sharply as semiconductor companies reported strong quarterly earnings", link: "https://finance.com/1"),
        ])
        let result = dedup.findDuplicates()
        XCTAssertEqual(result.groups.count, 0)
        XCTAssertEqual(result.duplicateCount, 0)
    }

    func testThreeArticleSameStory() {
        let body = "Scientists discovered a breakthrough in quantum computing using superconducting processors with error correction"
        dedup = ArticleDeduplicator(threshold: 0.4)
        dedup.index([
            makeStory(title: "Quantum Computing Breakthrough", body: body, link: "https://a.com/quantum"),
            makeStory(title: "Quantum Computing Breakthrough", body: body, link: "https://b.com/quantum"),
            makeStory(title: "Quantum Computing Breakthrough", body: body, link: "https://c.com/quantum"),
        ])
        let result = dedup.findDuplicates()
        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(result.groups[0].memberLinks.count, 3)
        XCTAssertEqual(result.duplicateCount, 2)
    }

    func testCanonicalIsEarliestInsertion() {
        let body = "identical body about artificial intelligence advancements in healthcare applications worldwide"
        dedup = ArticleDeduplicator(threshold: 0.4)
        let stories = [
            makeStory(title: "AI in Healthcare", body: body, link: "https://first.com/article"),
            makeStory(title: "AI in Healthcare", body: body, link: "https://second.com/article"),
        ]
        dedup.index(stories)
        let result = dedup.findDuplicates()
        XCTAssertEqual(result.groups[0].canonicalLink, "https://first.com/article")
    }

    func testDuplicateLinksSet() {
        let body = "technology and science news about renewable energy solar panels and wind turbines sustainability"
        dedup = ArticleDeduplicator(threshold: 0.4)
        dedup.index([
            makeStory(title: "Renewable Energy Boom", body: body, link: "https://a.com/energy"),
            makeStory(title: "Renewable Energy Boom", body: body, link: "https://b.com/energy"),
        ])
        let result = dedup.findDuplicates()
        let dupes = result.duplicateLinks
        XCTAssertFalse(dupes.contains("https://a.com/energy"))
        XCTAssertTrue(dupes.contains("https://b.com/energy"))
    }

    func testScanDurationRecorded() {
        dedup.index([makeStory(title: "Test", link: "https://a.com/1")])
        let result = dedup.findDuplicates()
        XCTAssertGreaterThanOrEqual(result.scanDuration, 0)
    }

    func testTotalScannedAccurate() {
        dedup.index([
            makeStory(title: "A", link: "https://a.com/1"),
            makeStory(title: "B", link: "https://a.com/2"),
            makeStory(title: "C", link: "https://a.com/3"),
        ])
        let result = dedup.findDuplicates()
        XCTAssertEqual(result.totalScanned, 3)
    }

    // MARK: - duplicatesOf

    func testDuplicatesOfFindsMatches() {
        let body = "scientific research into climate change effects on global agriculture and food production patterns"
        dedup = ArticleDeduplicator(threshold: 0.4)
        dedup.index([
            makeStory(title: "Climate Change Impact", body: body, link: "https://a.com/climate"),
            makeStory(title: "Climate Change Impact", body: body, link: "https://b.com/climate"),
        ])
        let group = dedup.duplicatesOf(link: "https://a.com/climate")
        XCTAssertNotNil(group)
        XCTAssertEqual(group!.memberLinks.count, 2)
    }

    func testDuplicatesOfReturnsNilForUnique() {
        dedup.index([
            makeStory(title: "Unique Article About Nothing Similar", body: "completely unrelated sports content about basketball and football games", link: "https://a.com/unique"),
            makeStory(title: "Different Topic Altogether Here", body: "cooking recipes and kitchen gadgets for professional chefs in restaurants", link: "https://b.com/other"),
        ])
        let group = dedup.duplicatesOf(link: "https://a.com/unique")
        XCTAssertNil(group)
    }

    func testDuplicatesOfUnknownLink() {
        let group = dedup.duplicatesOf(link: "https://nonexistent.com/article")
        XCTAssertNil(group)
    }

    // MARK: - Raw Similarity

    func testSimilarityBetweenTwoArticles() {
        let body = "machine learning algorithms for natural language processing tasks including sentiment classification"
        dedup = ArticleDeduplicator(threshold: 0.4)
        dedup.index([
            makeStory(title: "ML for NLP", body: body, link: "https://a.com/ml"),
            makeStory(title: "ML for NLP", body: body, link: "https://b.com/ml"),
        ])
        let result = dedup.similarity(linkA: "https://a.com/ml", linkB: "https://b.com/ml")
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result!.score, 0.5)
        XCTAssertFalse(result!.reason.isEmpty)
    }

    func testSimilarityUnknownLinkReturnsNil() {
        let result = dedup.similarity(linkA: "https://a.com/1", linkB: "https://b.com/2")
        XCTAssertNil(result)
    }

    // MARK: - DuplicateGroup

    func testDuplicateGroupEquality() {
        let a = DuplicateGroup(id: "1", memberLinks: ["a", "b"], canonicalLink: "a", confidence: 0.9, reason: "test")
        let b = DuplicateGroup(id: "1", memberLinks: ["a", "b"], canonicalLink: "a", confidence: 0.9, reason: "test")
        XCTAssertEqual(a, b)
    }

    func testDuplicateGroupInequalityByMembers() {
        let a = DuplicateGroup(id: "1", memberLinks: ["a", "b"], canonicalLink: "a", confidence: 0.9, reason: "test")
        let b = DuplicateGroup(id: "1", memberLinks: ["a", "c"], canonicalLink: "a", confidence: 0.9, reason: "test")
        XCTAssertNotEqual(a, b)
    }

    // MARK: - DeduplicationResult

    func testDeduplicationResultDuplicateLinks() {
        let result = DeduplicationResult(
            groups: [
                DuplicateGroup(id: "1", memberLinks: ["a", "b", "c"], canonicalLink: "a", confidence: 0.9, reason: "test"),
            ],
            totalScanned: 5,
            duplicateCount: 2,
            scanDuration: 0.01
        )
        let dupes = result.duplicateLinks
        XCTAssertEqual(dupes.count, 2)
        XCTAssertTrue(dupes.contains("b"))
        XCTAssertTrue(dupes.contains("c"))
        XCTAssertFalse(dupes.contains("a"))
    }

    func testDeduplicationResultEmptyGroups() {
        let result = DeduplicationResult(groups: [], totalScanned: 10, duplicateCount: 0, scanDuration: 0.001)
        XCTAssertTrue(result.duplicateLinks.isEmpty)
    }

    // MARK: - Edge Cases

    func testEmptyIndex() {
        let result = dedup.findDuplicates()
        XCTAssertEqual(result.groups.count, 0)
        XCTAssertEqual(result.totalScanned, 0)
        XCTAssertEqual(result.duplicateCount, 0)
    }

    func testSingleArticleNoDuplicates() {
        dedup.indexStory(makeStory(title: "Solo Article", link: "https://a.com/solo"))
        let result = dedup.findDuplicates()
        XCTAssertEqual(result.groups.count, 0)
    }

    func testRemovedArticleNotInResults() {
        let body = "identical content about blockchain cryptocurrency decentralized finance trading platforms"
        dedup = ArticleDeduplicator(threshold: 0.4)
        dedup.index([
            makeStory(title: "Crypto News Update", body: body, link: "https://a.com/crypto"),
            makeStory(title: "Crypto News Update", body: body, link: "https://b.com/crypto"),
        ])
        dedup.removeStory(link: "https://b.com/crypto")
        let result = dedup.findDuplicates()
        XCTAssertEqual(result.groups.count, 0)
    }

    func testGroupConfidenceAboveThreshold() {
        let body = "identical article about space exploration and Mars colonization mission planning progress update"
        dedup = ArticleDeduplicator(threshold: 0.4)
        dedup.index([
            makeStory(title: "Mars Mission Update", body: body, link: "https://a.com/mars"),
            makeStory(title: "Mars Mission Update", body: body, link: "https://b.com/mars"),
        ])
        let result = dedup.findDuplicates()
        if let group = result.groups.first {
            XCTAssertGreaterThanOrEqual(group.confidence, dedup.threshold)
        }
    }

    func testGroupHasNonEmptyReason() {
        let body = "identical article about quantum entanglement experiments in particle physics laboratories worldwide"
        dedup = ArticleDeduplicator(threshold: 0.4)
        dedup.index([
            makeStory(title: "Quantum Physics Experiment", body: body, link: "https://a.com/quantum"),
            makeStory(title: "Quantum Physics Experiment", body: body, link: "https://b.com/quantum"),
        ])
        let result = dedup.findDuplicates()
        if let group = result.groups.first {
            XCTAssertFalse(group.reason.isEmpty)
        }
    }

    func testGroupIdIsDeterministic() {
        let body = "identical deterministic content about software engineering practices and code review processes"
        dedup = ArticleDeduplicator(threshold: 0.4)
        dedup.index([
            makeStory(title: "Software Engineering", body: body, link: "https://a.com/sw"),
            makeStory(title: "Software Engineering", body: body, link: "https://b.com/sw"),
        ])
        let result1 = dedup.findDuplicates()

        dedup.reset()
        dedup.index([
            makeStory(title: "Software Engineering", body: body, link: "https://a.com/sw"),
            makeStory(title: "Software Engineering", body: body, link: "https://b.com/sw"),
        ])
        let result2 = dedup.findDuplicates()

        if let g1 = result1.groups.first, let g2 = result2.groups.first {
            XCTAssertEqual(g1.id, g2.id)
        }
    }
}
