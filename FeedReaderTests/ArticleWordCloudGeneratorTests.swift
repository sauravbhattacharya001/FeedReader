//
//  ArticleWordCloudGeneratorTests.swift
//  FeedReaderTests
//

import XCTest
@testable import FeedReader

class ArticleWordCloudGeneratorTests: XCTestCase {

    var generator: ArticleWordCloudGenerator!

    override func setUp() {
        super.setUp()
        generator = ArticleWordCloudGenerator()
    }

    private func makeArticle(
        title: String = "Test Article",
        body: String = "Some body text",
        feed: String? = "TechFeed",
        date: Date? = Date()
    ) -> (title: String, body: String, feedName: String?, date: Date?) {
        (title, body, feed, date)
    }

    // MARK: - Basic Generation

    func testEmptyArticlesReturnsEmpty() {
        let result = generator.generate(from: [])
        XCTAssertTrue(result.isEmpty)
    }

    func testSingleArticleWithMinDocFreq1() {
        var config = WordCloudConfig.default
        config.minDocumentFrequency = 1
        let articles = [
            makeArticle(title: "Swift Programming", body: "Swift is a modern programming language for iOS development. Swift provides safety and performance.")
        ]
        let result = generator.generate(from: articles, config: config)
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains { $0.word == "swift" })
    }

    func testMinDocumentFrequencyFiltering() {
        var config = WordCloudConfig.default
        config.minDocumentFrequency = 2
        let articles = [
            makeArticle(title: "Unique Words Only", body: "Completely unique content here standalone")
        ]
        let result = generator.generate(from: articles, config: config)
        XCTAssertTrue(result.isEmpty)
    }

    func testMultipleArticlesProduceResults() {
        let articles = [
            makeArticle(title: "Machine Learning Basics", body: "Machine learning algorithms process data to find patterns"),
            makeArticle(title: "Deep Learning Advances", body: "Neural networks and machine learning continue to evolve"),
            makeArticle(title: "AI and Machine Learning", body: "Artificial intelligence relies on machine learning techniques")
        ]
        let result = generator.generate(from: articles)
        XCTAssertFalse(result.isEmpty)
        let words = result.map { $0.word }
        XCTAssertTrue(words.contains("machine"))
        XCTAssertTrue(words.contains("learning"))
    }

    func testResultsSortedByScoreDescending() {
        let articles = [
            makeArticle(title: "Alpha Beta Gamma", body: "Alpha beta gamma delta epsilon alpha beta gamma"),
            makeArticle(title: "Alpha Gamma", body: "Alpha gamma zeta alpha gamma theta"),
            makeArticle(title: "Beta Delta", body: "Beta delta kappa beta delta lambda")
        ]
        let result = generator.generate(from: articles)
        for i in 1..<result.count {
            XCTAssertGreaterThanOrEqual(result[i-1].score, result[i].score)
        }
    }

    func testNormalizedSizeRange() {
        let articles = [
            makeArticle(title: "Rust Programming", body: "Rust provides memory safety without garbage collection"),
            makeArticle(title: "Rust Systems", body: "Systems programming with Rust is efficient and safe"),
            makeArticle(title: "Go Programming", body: "Go language provides concurrency and simplicity")
        ]
        let result = generator.generate(from: articles)
        for entry in result {
            XCTAssertGreaterThanOrEqual(entry.normalizedSize, 0.0)
            XCTAssertLessThanOrEqual(entry.normalizedSize, 1.0)
        }
        if let first = result.first {
            XCTAssertEqual(first.normalizedSize, 1.0)
        }
    }

    func testMaxWordsLimit() {
        var config = WordCloudConfig.default
        config.maxWords = 5
        config.minDocumentFrequency = 1
        let articles = [
            makeArticle(title: "Many Different Words", body: "alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike november oscar papa quebec romeo sierra tango"),
            makeArticle(title: "More Varied Content", body: "alpha bravo charlie delta echo foxtrot golf hotel india juliet uniform victor whiskey xray yankee zulu additional varied content")
        ]
        let result = generator.generate(from: articles, config: config)
        XCTAssertLessThanOrEqual(result.count, 5)
    }

    func testMaxDocumentFrequencyRatioFiltering() {
        var config = WordCloudConfig.default
        config.maxDocumentFrequencyRatio = 0.5
        config.minDocumentFrequency = 1
        let articles = [
            makeArticle(title: "Common Alpha", body: "common alpha specific"),
            makeArticle(title: "Common Beta", body: "common beta unique"),
            makeArticle(title: "Common Gamma", body: "common gamma rare"),
            makeArticle(title: "Common Delta", body: "common delta special")
        ]
        let result = generator.generate(from: articles, config: config)
        let words = result.map { $0.word }
        XCTAssertFalse(words.contains("common"))
    }

    // MARK: - Feed Filtering

    func testFeedFilterIncludesOnlyMatchingFeed() {
        var config = WordCloudConfig.default
        config.feedFilter = "TechFeed"
        config.minDocumentFrequency = 1
        let articles = [
            makeArticle(title: "Tech Article", body: "technology innovation startup", feed: "TechFeed"),
            makeArticle(title: "Sports Article", body: "football basketball soccer", feed: "SportsFeed")
        ]
        let result = generator.generate(from: articles, config: config)
        let words = result.map { $0.word }
        XCTAssertTrue(words.contains("technology") || words.contains("innovation") || words.contains("startup"))
        XCTAssertFalse(words.contains("football"))
    }

    func testFeedFilterCaseInsensitive() {
        var config = WordCloudConfig.default
        config.feedFilter = "techfeed"
        config.minDocumentFrequency = 1
        let articles = [
            makeArticle(title: "Tech Article", body: "technology innovation", feed: "TechFeed")
        ]
        let result = generator.generate(from: articles, config: config)
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: - Date Filtering

    func testSinceDateFiltering() {
        var config = WordCloudConfig.default
        config.sinceDate = Date(timeIntervalSinceNow: -86400)
        config.minDocumentFrequency = 1
        let articles = [
            makeArticle(title: "Recent Article", body: "recent content fresh", date: Date()),
            makeArticle(title: "Old Article", body: "ancient content stale", date: Date(timeIntervalSinceNow: -604800))
        ]
        let result = generator.generate(from: articles, config: config)
        let words = result.map { $0.word }
        XCTAssertTrue(words.contains("recent") || words.contains("fresh"))
        XCTAssertFalse(words.contains("ancient"))
    }

    func testNilDatesPassThroughWithSinceDate() {
        var config = WordCloudConfig.default
        config.sinceDate = Date(timeIntervalSinceNow: -86400)
        config.minDocumentFrequency = 1
        let articles = [
            makeArticle(title: "No Date Article", body: "dateless content included", date: nil)
        ]
        let result = generator.generate(from: articles, config: config)
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: - Per-Feed Breakdown

    func testPerFeedGeneration() {
        let articles = [
            makeArticle(title: "Tech News Alpha", body: "technology alpha innovation alpha", feed: "TechFeed"),
            makeArticle(title: "Tech News Beta", body: "technology beta startup beta", feed: "TechFeed"),
            makeArticle(title: "Sports Update", body: "football scores results football", feed: "SportsFeed"),
            makeArticle(title: "Sports Recap", body: "basketball highlights recap basketball", feed: "SportsFeed")
        ]
        let result = generator.generatePerFeed(from: articles)
        XCTAssertTrue(result.keys.contains("TechFeed"))
        XCTAssertTrue(result.keys.contains("SportsFeed"))
    }

    func testPerFeedExcludesNilFeedNames() {
        let articles = [
            makeArticle(title: "No Feed", body: "orphan content standalone", feed: nil),
            makeArticle(title: "Has Feed", body: "labeled content categorized", feed: "MyFeed")
        ]
        let result = generator.generatePerFeed(from: articles)
        XCTAssertFalse(result.keys.contains(""))
        XCTAssertTrue(result.keys.contains("MyFeed"))
    }

    // MARK: - Comparative Cloud

    func testComparativeCloudNeedsTwoFeeds() {
        let articles = [
            makeArticle(title: "Only One Feed", body: "single feed content", feed: "OnlyFeed"),
            makeArticle(title: "Same Feed Again", body: "more single feed content", feed: "OnlyFeed")
        ]
        let result = generator.generateComparative(from: articles)
        XCTAssertTrue(result.isEmpty)
    }

    func testComparativeCloudShowsDistinctiveWords() {
        let articles = [
            makeArticle(title: "Python Programming", body: "python django flask web framework python django flask", feed: "PythonFeed"),
            makeArticle(title: "Python Scripting", body: "python scripting automation python scripting automation", feed: "PythonFeed"),
            makeArticle(title: "Java Enterprise", body: "java spring boot enterprise application java spring boot", feed: "JavaFeed"),
            makeArticle(title: "Java Development", body: "java maven gradle build tools java maven gradle", feed: "JavaFeed")
        ]
        let result = generator.generateComparative(from: articles)
        XCTAssertTrue(result.keys.contains("PythonFeed"))
        XCTAssertTrue(result.keys.contains("JavaFeed"))
        if let pythonWords = result["PythonFeed"]?.map({ $0.word }) {
            XCTAssertTrue(pythonWords.contains("django") || pythonWords.contains("flask"))
        }
        if let javaWords = result["JavaFeed"]?.map({ $0.word }) {
            XCTAssertTrue(javaWords.contains("spring") || javaWords.contains("maven"))
        }
    }

    func testComparativeMaxWordsPerFeed() {
        let articles = [
            makeArticle(title: "Feed A", body: "alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike november", feed: "FeedA"),
            makeArticle(title: "Feed B", body: "oscar papa quebec romeo sierra tango uniform victor whiskey xray yankee zulu additional extras", feed: "FeedB")
        ]
        let result = generator.generateComparative(from: articles, maxWordsPerFeed: 5)
        for (_, entries) in result {
            XCTAssertLessThanOrEqual(entries.count, 5)
        }
    }

    // MARK: - Export

    func testJSONExport() {
        var config = WordCloudConfig.default
        config.minDocumentFrequency = 1
        let articles = [
            makeArticle(title: "Export Test", body: "export test content data json"),
            makeArticle(title: "More Export", body: "export additional data json format")
        ]
        let entries = generator.generate(from: articles, config: config)
        let jsonData = generator.exportJSON(entries)
        XCTAssertNotNil(jsonData)
        if let data = jsonData {
            let decoded = try? JSONDecoder().decode([WordCloudEntry].self, from: data)
            XCTAssertNotNil(decoded)
            XCTAssertEqual(decoded?.count, entries.count)
        }
    }

    func testJSONRoundTrip() {
        let entry = WordCloudEntry(word: "test", score: 1.5, frequency: 10, documentCount: 3, normalizedSize: 0.75)
        let data = try! JSONEncoder().encode([entry])
        let decoded = try! JSONDecoder().decode([WordCloudEntry].self, from: data)
        XCTAssertEqual(decoded.first, entry)
    }

    // MARK: - Text Report

    func testTextReportContainsExpectedSections() {
        var config = WordCloudConfig.default
        config.minDocumentFrequency = 1
        let articles = [
            makeArticle(title: "Report Test", body: "generating text report visualization"),
            makeArticle(title: "Another Report", body: "more text report content analysis")
        ]
        let entries = generator.generate(from: articles, config: config)
        let report = generator.textReport(entries)
        XCTAssertTrue(report.contains("Word Cloud"))
        XCTAssertTrue(report.contains("Total words:"))
        XCTAssertTrue(report.contains("Top word:"))
    }

    func testTextReportCustomTitle() {
        let entries = [WordCloudEntry(word: "hello", score: 1.0, frequency: 5, documentCount: 2, normalizedSize: 1.0)]
        let report = generator.textReport(entries, title: "My Custom Cloud")
        XCTAssertTrue(report.contains("My Custom Cloud"))
    }

    func testTextReportEmptyEntries() {
        let report = generator.textReport([], title: "Empty")
        XCTAssertTrue(report.contains("(no data)"))
    }

    // MARK: - Edge Cases

    func testStopWordsFiltered() {
        var config = WordCloudConfig.default
        config.minDocumentFrequency = 1
        let articles = [
            makeArticle(title: "The And But Or", body: "the and but or is are was were this that")
        ]
        let result = generator.generate(from: articles, config: config)
        let words = Set(result.map { $0.word })
        XCTAssertFalse(words.contains("the"))
        XCTAssertFalse(words.contains("and"))
    }

    func testMinWordLengthRespected() {
        var config = WordCloudConfig.default
        config.minWordLength = 5
        config.minDocumentFrequency = 1
        let articles = [
            makeArticle(title: "Big Words Only", body: "cat dog run fly big hat programming architecture infrastructure")
        ]
        let result = generator.generate(from: articles, config: config)
        for entry in result {
            XCTAssertGreaterThanOrEqual(entry.word.count, 5)
        }
    }

    func testDocumentCountAccurate() {
        var config = WordCloudConfig.default
        config.minDocumentFrequency = 1
        let articles = [
            makeArticle(title: "Alpha Article", body: "alpha specific content unique"),
            makeArticle(title: "Beta Article", body: "beta different content varied"),
            makeArticle(title: "Gamma Article", body: "gamma alpha content shared")
        ]
        let result = generator.generate(from: articles, config: config)
        if let contentEntry = result.first(where: { $0.word == "content" }) {
            XCTAssertEqual(contentEntry.documentCount, 3)
        }
        if let alphaEntry = result.first(where: { $0.word == "alpha" }) {
            XCTAssertEqual(alphaEntry.documentCount, 2)
        }
    }

    func testFrequencyCountAccurate() {
        var config = WordCloudConfig.default
        config.minDocumentFrequency = 1
        let articles = [
            makeArticle(title: "Repeat", body: "repeat repeat repeat unique"),
            makeArticle(title: "Other", body: "repeat other different words")
        ]
        let result = generator.generate(from: articles, config: config)
        if let repeatEntry = result.first(where: { $0.word == "repeat" }) {
            XCTAssertEqual(repeatEntry.frequency, 6)
        }
    }

    func testDefaultConfigValues() {
        let config = WordCloudConfig.default
        XCTAssertEqual(config.maxWords, 50)
        XCTAssertEqual(config.minDocumentFrequency, 2)
        XCTAssertEqual(config.maxDocumentFrequencyRatio, 0.8)
        XCTAssertEqual(config.minWordLength, 3)
        XCTAssertNil(config.feedFilter)
        XCTAssertNil(config.sinceDate)
    }

    func testWordCloudEntryEquatable() {
        let a = WordCloudEntry(word: "test", score: 1.0, frequency: 5, documentCount: 2, normalizedSize: 0.5)
        let b = WordCloudEntry(word: "test", score: 1.0, frequency: 5, documentCount: 2, normalizedSize: 0.5)
        let c = WordCloudEntry(word: "other", score: 1.0, frequency: 5, documentCount: 2, normalizedSize: 0.5)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
