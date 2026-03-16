//
//  FeedMigrationAssistantTests.swift
//  FeedReaderTests
//
//  Tests for FeedMigrationAssistant — source detection, OPML parsing,
//  category mapping, dedup, migration execution, and report generation.
//

import XCTest
@testable import FeedReader

class FeedMigrationAssistantTests: XCTestCase {

    var assistant: FeedMigrationAssistant!

    override func setUp() {
        super.setUp()
        assistant = FeedMigrationAssistant.shared
        assistant.clearHistory()
    }

    // MARK: - Sample OPML Data

    private let feedlyOPML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <opml version="2.0">
    <head><title>Feedly OPML Export</title></head>
    <body>
        <outline text="Technology" title="Technology">
            <outline text="Ars Technica" title="Ars Technica" type="rss"
                xmlUrl="https://feeds.arstechnica.com/arstechnica/index" htmlUrl="https://arstechnica.com"/>
            <outline text="TechCrunch" title="TechCrunch" type="rss"
                xmlUrl="https://techcrunch.com/feed/" htmlUrl="https://techcrunch.com"/>
        </outline>
        <outline text="News" title="News">
            <outline text="Reuters" title="Reuters" type="rss"
                xmlUrl="https://feeds.reuters.com/reuters/topNews" htmlUrl="https://reuters.com"/>
        </outline>
    </body>
    </opml>
    """

    private let inoreaderOPML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <opml version="1.0">
    <head><title>Inoreader Subscriptions</title></head>
    <body>
        <outline text="dev" title="dev">
            <outline text="Hacker News" title="Hacker News" type="rss"
                xmlUrl="https://hnrss.org/frontpage" htmlUrl="https://news.ycombinator.com"/>
        </outline>
        <outline text="science" title="science">
            <outline text="Nature" title="Nature" type="rss"
                xmlUrl="https://www.nature.com/nature.rss" htmlUrl="https://nature.com"/>
        </outline>
    </body>
    </opml>
    """

    private let newsblurOPML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <opml version="1.0">
    <head><title>NewsBlur Subscriptions</title></head>
    <body>
        <outline text="gaming" title="gaming">
            <outline text="Kotaku" title="Kotaku" type="rss"
                xmlUrl="https://kotaku.com/rss" htmlUrl="https://kotaku.com"/>
        </outline>
    </body>
    </opml>
    """

    private let genericOPML = """
    <?xml version="1.0"?>
    <opml version="2.0">
    <head><title>My Feeds</title></head>
    <body>
        <outline text="Blog A" title="Blog A" type="rss" xmlUrl="https://bloga.com/feed"/>
        <outline text="Blog B" title="Blog B" type="rss" xmlUrl="https://blogb.com/rss"/>
        <outline text="No URL" title="No URL" type="rss"/>
    </body>
    </opml>
    """

    // MARK: - Source Detection Tests

    func testDetectFeedly() {
        XCTAssertEqual(assistant.detectSource(from: feedlyOPML), .feedly)
    }

    func testDetectInoreader() {
        XCTAssertEqual(assistant.detectSource(from: inoreaderOPML), .inoreader)
    }

    func testDetectNewsBlur() {
        XCTAssertEqual(assistant.detectSource(from: newsblurOPML), .newsblur)
    }

    func testDetectGenericOPML() {
        XCTAssertEqual(assistant.detectSource(from: genericOPML), .genericOPML)
    }

    func testDetectUnknown() {
        XCTAssertEqual(assistant.detectSource(from: "just some text"), .unknown)
    }

    func testDetectMiniflux() {
        let opml = "<opml><head><title>Miniflux</title></head></opml>"
        XCTAssertEqual(assistant.detectSource(from: opml), .miniflux)
    }

    func testDetectNetNewsWire() {
        let opml = "<opml><head><title>NetNewsWire Export</title></head></opml>"
        XCTAssertEqual(assistant.detectSource(from: opml), .netNewsWire)
    }

    func testDetectFeedbin() {
        let opml = "<opml><head><title>Feedbin Subscriptions</title></head></opml>"
        XCTAssertEqual(assistant.detectSource(from: opml), .feedbin)
    }

    // MARK: - OPML Parsing Tests

    func testParseFeedlyOPML() {
        let (source, entries) = assistant.parseOPML(feedlyOPML)
        XCTAssertEqual(source, .feedly)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].title, "Ars Technica")
        XCTAssertEqual(entries[0].category, "Technology")
        XCTAssertEqual(entries[2].title, "Reuters")
        XCTAssertEqual(entries[2].category, "News")
    }

    func testParseInoreaderOPML() {
        let (source, entries) = assistant.parseOPML(inoreaderOPML)
        XCTAssertEqual(source, .inoreader)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].category, "dev")
        XCTAssertEqual(entries[1].category, "science")
    }

    func testParseGenericOPMLSkipsNoUrl() {
        let (_, entries) = assistant.parseOPML(genericOPML)
        XCTAssertEqual(entries.count, 2) // "No URL" should be skipped
    }

    func testParseEmptyOPML() {
        let (_, entries) = assistant.parseOPML("<opml><body></body></opml>")
        XCTAssertEqual(entries.count, 0)
    }

    // MARK: - Category Mapping Tests

    func testNormalizeTechSynonyms() {
        XCTAssertEqual(assistant.normalizeCategory("tech"), "Technology")
        XCTAssertEqual(assistant.normalizeCategory("programming"), "Technology")
        XCTAssertEqual(assistant.normalizeCategory("dev"), "Technology")
        XCTAssertEqual(assistant.normalizeCategory("coding"), "Technology")
    }

    func testNormalizeNewsSynonyms() {
        XCTAssertEqual(assistant.normalizeCategory("news"), "News")
        XCTAssertEqual(assistant.normalizeCategory("world news"), "News")
        XCTAssertEqual(assistant.normalizeCategory("headlines"), "News")
    }

    func testNormalizeBusinessSynonyms() {
        XCTAssertEqual(assistant.normalizeCategory("finance"), "Business")
        XCTAssertEqual(assistant.normalizeCategory("investing"), "Business")
    }

    func testNormalizeUnknownCategory() {
        XCTAssertEqual(assistant.normalizeCategory("my custom feeds"), "My Custom Feeds")
    }

    func testNormalizeFeedlyPrefixes() {
        XCTAssertEqual(assistant.normalizeCategory("user/12345/label/tech"), "Technology")
    }

    func testBuildCategoryMappings() {
        let (_, entries) = assistant.parseOPML(inoreaderOPML)
        let mappings = assistant.buildCategoryMappings(for: entries)
        XCTAssertTrue(mappings.contains(where: { $0.sourceCategory == "dev" && $0.targetCategory == "Technology" }))
        XCTAssertTrue(mappings.contains(where: { $0.sourceCategory == "science" && $0.targetCategory == "Science" }))
    }

    func testCustomCategoryMappings() {
        let (_, entries) = assistant.parseOPML(inoreaderOPML)
        let mappings = assistant.buildCategoryMappings(for: entries, customMappings: ["dev": "My Dev Stuff"])
        XCTAssertTrue(mappings.contains(where: { $0.sourceCategory == "dev" && $0.targetCategory == "My Dev Stuff" && !$0.isAutomatic }))
    }

    // MARK: - Migration Feed Entry Tests

    func testNormalizedUrl() {
        let entry = MigrationFeedEntry(title: "Test", xmlUrl: "HTTPS://Example.com/feed/", htmlUrl: nil, category: nil, source: .genericOPML)
        XCTAssertEqual(entry.normalizedUrl, "example.com/feed")
    }

    func testNormalizedUrlStripsProtocol() {
        let entry1 = MigrationFeedEntry(title: "A", xmlUrl: "https://site.com/rss", htmlUrl: nil, category: nil, source: .genericOPML)
        let entry2 = MigrationFeedEntry(title: "B", xmlUrl: "http://site.com/rss", htmlUrl: nil, category: nil, source: .genericOPML)
        XCTAssertEqual(entry1.normalizedUrl, entry2.normalizedUrl)
    }

    // MARK: - Dry Run / Preview Tests

    func testDryRunDoesNotImport() {
        let report = assistant.preview(from: genericOPML)
        XCTAssertEqual(report.imported, 2)
        XCTAssertTrue(report.feedResults.allSatisfy { $0.note == "Dry run — not imported" || $0.status == .invalid })
    }

    func testDryRunDoesNotSaveHistory() {
        _ = assistant.preview(from: genericOPML)
        XCTAssertEqual(assistant.migrationHistory.count, 0)
    }

    // MARK: - Report Tests

    func testReportSummary() {
        let report = assistant.preview(from: feedlyOPML)
        XCTAssertTrue(report.summary.contains("Feedly"))
        XCTAssertTrue(report.summary.contains("3 feeds found"))
    }

    func testReportToText() {
        let report = assistant.preview(from: feedlyOPML)
        let text = report.toText()
        XCTAssertTrue(text.contains("Feed Migration Report"))
        XCTAssertTrue(text.contains("Feedly"))
        XCTAssertTrue(text.contains("Imported"))
    }

    func testReportToJSON() {
        let report = assistant.preview(from: feedlyOPML)
        let json = report.toJSON()
        XCTAssertNotNil(json)
        // Verify it's valid JSON
        if let data = json {
            let obj = try? JSONSerialization.jsonObject(with: data)
            XCTAssertNotNil(obj)
        }
    }

    // MARK: - Invalid Feed Tests

    func testInvalidUrlMarkedInvalid() {
        let opml = """
        <opml><body>
            <outline text="Bad" title="Bad" type="rss" xmlUrl="not-a-url"/>
            <outline text="Good" title="Good" type="rss" xmlUrl="https://good.com/feed"/>
        </body></opml>
        """
        let report = assistant.preview(from: opml)
        XCTAssertEqual(report.invalid, 1)
        XCTAssertEqual(report.imported, 1)
    }

    // MARK: - Max Feeds Limit

    func testMaxFeedsLimit() {
        var options = MigrationOptions()
        options.maxFeeds = 1
        options.dryRun = true
        let report = assistant.migrate(from: feedlyOPML, options: options)
        XCTAssertEqual(report.totalFound, 1)
    }

    // MARK: - Describe Migration

    func testDescribeMigration() {
        let desc = assistant.describeMigration(from: feedlyOPML)
        XCTAssertTrue(desc.contains("Feedly"))
        XCTAssertTrue(desc.contains("3 feed"))
        XCTAssertTrue(desc.contains("2 categories"))
    }

    // MARK: - History Tests

    func testClearHistory() {
        assistant.clearHistory()
        XCTAssertEqual(assistant.migrationHistory.count, 0)
    }

    // MARK: - Source Icon Tests

    func testAllSourcesHaveIcons() {
        for source in FeedReaderSource.allCases {
            XCTAssertFalse(source.iconEmoji.isEmpty)
        }
    }

    // MARK: - XML Entity Decoding

    func testXMLEntityDecoding() {
        let opml = """
        <opml><body>
            <outline text="Tom &amp; Jerry" title="Tom &amp; Jerry" type="rss" xmlUrl="https://example.com/feed"/>
        </body></opml>
        """
        let (_, entries) = assistant.parseOPML(opml)
        XCTAssertEqual(entries.first?.title, "Tom & Jerry")
    }
}
