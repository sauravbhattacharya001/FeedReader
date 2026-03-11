//
//  ArticleGeoTaggerTests.swift
//  FeedReaderTests
//

import XCTest
@testable import FeedReader

class ArticleGeoTaggerTests: XCTestCase {

    var tagger: ArticleGeoTagger!

    override func setUp() {
        super.setUp()
        tagger = ArticleGeoTagger(minimumConfidence: 0.6)
        tagger.clearAll()
    }

    override func tearDown() {
        tagger.clearAll()
        super.tearDown()
    }

    // MARK: - Gazetteer

    func testGazetteerHasEntries() {
        let entries = ArticleGeoTagger.buildGazetteer()
        XCTAssertGreaterThan(entries.count, 100, "Gazetteer should have >100 entries")
    }

    func testGazetteerCoversAllRegions() {
        let entries = ArticleGeoTagger.buildGazetteer()
        let regions = Set(entries.map { $0.region })
        XCTAssertTrue(regions.contains(.northAmerica))
        XCTAssertTrue(regions.contains(.europe))
        XCTAssertTrue(regions.contains(.asia))
        XCTAssertTrue(regions.contains(.africa))
        XCTAssertTrue(regions.contains(.middleEast))
        XCTAssertTrue(regions.contains(.southAmerica))
        XCTAssertTrue(regions.contains(.oceania))
    }

    func testGazetteerSearchTermsLowercased() {
        let entries = ArticleGeoTagger.buildGazetteer()
        for entry in entries {
            for term in entry.searchTerms {
                XCTAssertEqual(term, term.lowercased(),
                    "Search term '\(term)' for \(entry.name) should be lowercased")
            }
        }
    }

    // MARK: - Basic Tagging

    func testTagSimpleCountryMention() {
        let result = tagger.tagText("The earthquake struck Japan early this morning.")
        XCTAssertFalse(result.tags.isEmpty, "Should find Japan")
        XCTAssertEqual(result.tags.first?.normalizedName, "Japan")
        XCTAssertEqual(result.tags.first?.region, .asia)
    }

    func testTagMultipleLocations() {
        let text = "Trade talks between China and Germany stalled in Berlin."
        let result = tagger.tagText(text)
        let names = Set(result.tags.map { $0.normalizedName })
        XCTAssertTrue(names.contains("China"))
        XCTAssertTrue(names.contains("Germany") || names.contains("Berlin"))
    }

    func testTagCityAndCountry() {
        let text = "Officials in London met with delegates from France."
        let result = tagger.tagText(text)
        let names = Set(result.tags.map { $0.normalizedName })
        XCTAssertTrue(names.contains("London"))
        XCTAssertTrue(names.contains("France"))
    }

    func testTagMultiWordCity() {
        let text = "The conference was held in New York City last week."
        let result = tagger.tagText(text)
        let names = result.tags.map { $0.normalizedName }
        XCTAssertTrue(names.contains("New York"), "Should match 'New York City'")
    }

    func testNoLocationsInGenericText() {
        let result = tagger.tagText("The quick brown fox jumps over the lazy dog.")
        XCTAssertTrue(result.tags.isEmpty, "Generic text should have no geo tags")
    }

    func testTagPreservesCharacterOffset() {
        let text = "Protests erupted in Tokyo on Monday."
        let result = tagger.tagText(text)
        guard let tag = result.tags.first else {
            XCTFail("Should find Tokyo"); return
        }
        XCTAssertEqual(tag.normalizedName, "Tokyo")
        // "Tokyo" starts at index 20 in "Protests erupted in Tokyo on Monday."
        XCTAssertEqual(tag.characterOffset, 20)
        XCTAssertEqual(tag.matchLength, 5)
    }

    // MARK: - Aliases

    func testAliasMatchesNYC() {
        let result = tagger.tagText("Traffic chaos in NYC this morning.")
        let names = result.tags.map { $0.normalizedName }
        XCTAssertTrue(names.contains("New York"), "NYC alias should resolve to New York")
    }

    func testAliasMatchesUK() {
        let result = tagger.tagText("Elections in the UK drew record turnout.")
        let names = result.tags.map { $0.normalizedName }
        XCTAssertTrue(names.contains("United Kingdom"), "UK alias should match")
    }

    // MARK: - GeoTagResult Properties

    func testPrimaryRegion() {
        let text = "Reports from Berlin, Munich, and Paris indicate rising costs."
        let result = tagger.tagText(text)
        XCTAssertEqual(result.primaryRegion, .europe)
    }

    func testRegionBreakdown() {
        let text = "Tokyo and Beijing report growth while London faces recession."
        let result = tagger.tagText(text)
        XCTAssertNotNil(result.regionBreakdown["Asia"])
        XCTAssertNotNil(result.regionBreakdown["Europe"])
    }

    func testCountryBreakdown() {
        let text = "Officials from Japan and India met in Singapore."
        let result = tagger.tagText(text)
        XCTAssertNotNil(result.countryBreakdown["Japan"])
        XCTAssertNotNil(result.countryBreakdown["India"])
    }

    func testUniqueLocationsCount() {
        let text = "Tokyo hosted delegates from Tokyo, Seoul, and Beijing."
        let result = tagger.tagText(text)
        // Tokyo appears twice but should count as 1 unique
        let names = Set(result.tags.map { $0.normalizedName })
        XCTAssertEqual(result.uniqueLocations, names.count)
    }

    func testDominantLocation() {
        let text = "London, London, London — the city never sleeps. Paris was quiet."
        let result = tagger.tagText(text)
        XCTAssertEqual(result.dominantLocation?.normalizedName, "London")
    }

    // MARK: - Story Tagging

    func testTagStory() {
        let result = tagger.tagStory(
            title: "Tokyo Olympics Update",
            body: "Athletes from around the world gather in Tokyo for the games.",
            link: "https://example.com/olympics"
        )
        XCTAssertFalse(result.tags.isEmpty)
        XCTAssertEqual(result.articleLink, "https://example.com/olympics")
    }

    // MARK: - Persistence

    func testResultIsCached() {
        _ = tagger.tagText("Breaking news from Paris.", articleLink: "https://x.com/1")
        let cached = tagger.result(for: "https://x.com/1")
        XCTAssertNotNil(cached)
        XCTAssertFalse(cached!.tags.isEmpty)
    }

    func testAllResults() {
        _ = tagger.tagText("News from London.", articleLink: "https://x.com/a")
        _ = tagger.tagText("News from Tokyo.", articleLink: "https://x.com/b")
        XCTAssertEqual(tagger.allResults().count, 2)
    }

    func testRemoveResult() {
        _ = tagger.tagText("News from Berlin.", articleLink: "https://x.com/c")
        XCTAssertTrue(tagger.removeResult(for: "https://x.com/c"))
        XCTAssertNil(tagger.result(for: "https://x.com/c"))
    }

    func testRemoveNonexistentResult() {
        XCTAssertFalse(tagger.removeResult(for: "https://x.com/nope"))
    }

    func testClearAll() {
        _ = tagger.tagText("News from Paris.", articleLink: "https://x.com/d")
        _ = tagger.tagText("News from Tokyo.", articleLink: "https://x.com/e")
        tagger.clearAll()
        XCTAssertEqual(tagger.count, 0)
        XCTAssertTrue(tagger.allResults().isEmpty)
    }

    // MARK: - Queries

    func testArticlesInRegion() {
        _ = tagger.tagText("Update from Berlin.", articleLink: "a")
        _ = tagger.tagText("Update from Tokyo.", articleLink: "b")
        let european = tagger.articles(in: .europe)
        XCTAssertEqual(european.count, 1)
        XCTAssertEqual(european.first?.articleLink, "a")
    }

    func testArticlesMentioningCountry() {
        _ = tagger.tagText("News from Tokyo, Japan.", articleLink: "jp1")
        _ = tagger.tagText("News from London, England.", articleLink: "uk1")
        let japan = tagger.articles(mentioning: "Japan")
        XCTAssertEqual(japan.count, 1)
    }

    func testArticlesMentioningLocation() {
        _ = tagger.tagText("Flooding in Mumbai devastates neighborhoods.", articleLink: "m1")
        _ = tagger.tagText("Sunny day in Seattle today.", articleLink: "s1")
        let mumbai = tagger.articles(mentioningLocation: "Mumbai")
        XCTAssertEqual(mumbai.count, 1)
        XCTAssertEqual(mumbai.first?.articleLink, "m1")
    }

    // MARK: - Statistics

    func testStatisticsEmpty() {
        let stats = tagger.statistics()
        XCTAssertEqual(stats.totalArticles, 0)
        XCTAssertEqual(stats.taggedArticles, 0)
        XCTAssertEqual(stats.coveragePercent, 0.0)
    }

    func testStatisticsWithData() {
        _ = tagger.tagText("News from London.", articleLink: "s1")
        _ = tagger.tagText("News from Tokyo.", articleLink: "s2")
        _ = tagger.tagText("No locations here.", articleLink: "s3")
        let stats = tagger.statistics()
        XCTAssertEqual(stats.totalArticles, 3)
        XCTAssertEqual(stats.taggedArticles, 2)
        XCTAssertGreaterThan(stats.coveragePercent, 60.0)
    }

    func testTopLocationsInStats() {
        _ = tagger.tagText("London is great. London rocks.", articleLink: "t1")
        _ = tagger.tagText("Paris is beautiful.", articleLink: "t2")
        let stats = tagger.statistics()
        XCTAssertFalse(stats.topLocations.isEmpty)
    }

    // MARK: - Summary

    func testSummaryFormat() {
        _ = tagger.tagText("News from Berlin and Paris.", articleLink: "sum1")
        let summary = tagger.summary()
        XCTAssertTrue(summary.contains("📍 Geographic Coverage"))
        XCTAssertTrue(summary.contains("Articles analyzed:"))
    }

    func testSummaryEmpty() {
        let summary = tagger.summary()
        XCTAssertTrue(summary.contains("Articles analyzed: 0"))
    }

    // MARK: - GeoRegion

    func testGeoRegionAllCases() {
        XCTAssertEqual(GeoRegion.allCases.count, 8)
    }

    func testGeoRegionEmoji() {
        XCTAssertFalse(GeoRegion.northAmerica.emoji.isEmpty)
        XCTAssertFalse(GeoRegion.europe.emoji.isEmpty)
        XCTAssertFalse(GeoRegion.unknown.emoji.isEmpty)
    }

    func testGeoRegionDescription() {
        XCTAssertEqual(GeoRegion.asia.description, "Asia")
        XCTAssertEqual(GeoRegion.africa.description, "Africa")
    }

    // MARK: - Confidence

    func testHighConfidenceForExactMatch() {
        let result = tagger.tagText("Meeting in London tomorrow.")
        guard let tag = result.tags.first else {
            XCTFail("Should find London"); return
        }
        XCTAssertEqual(tag.confidence, 1.0, "Exact match should have 1.0 confidence")
    }

    func testMinimumConfidenceFilter() {
        let strictTagger = ArticleGeoTagger(minimumConfidence: 0.99)
        strictTagger.clearAll()
        let result = strictTagger.tagText("Visit Londn for holidays.")
        // "Londn" is a typo — should be filtered by high confidence threshold
        // (only exact matches pass 0.99)
        let londonTags = result.tags.filter { $0.normalizedName == "London" }
        XCTAssertTrue(londonTags.isEmpty, "Typo should not pass 0.99 confidence threshold")
    }

    // MARK: - Edge Cases

    func testEmptyText() {
        let result = tagger.tagText("")
        XCTAssertTrue(result.tags.isEmpty)
        XCTAssertEqual(result.uniqueLocations, 0)
    }

    func testVeryShortText() {
        let result = tagger.tagText("Hi")
        XCTAssertTrue(result.tags.isEmpty)
    }

    func testArticleLinkEmpty() {
        let result = tagger.tagText("News from Paris.")
        // Should still work but not cache
        XCTAssertFalse(result.tags.isEmpty)
        XCTAssertEqual(tagger.count, 0, "Empty link should not be cached")
    }

    func testGeoTagEquatable() {
        let tag1 = GeoTag(placeName: "London", normalizedName: "London",
            region: .europe, country: "United Kingdom",
            latitude: 51.5074, longitude: -0.1278,
            confidence: 1.0, characterOffset: 10, matchLength: 6)
        let tag2 = GeoTag(placeName: "London", normalizedName: "London",
            region: .europe, country: "United Kingdom",
            latitude: 51.5074, longitude: -0.1278,
            confidence: 0.9, characterOffset: 10, matchLength: 6)
        XCTAssertEqual(tag1, tag2, "Same name + offset should be equal")
    }

    func testGeoStatsEquatable() {
        let stats1 = GeoStats(totalArticles: 5, taggedArticles: 3, totalMentions: 10,
            uniqueLocations: 4, regionDistribution: [:],
            topLocations: [], topCountries: [], coveragePercent: 60.0)
        let stats2 = GeoStats(totalArticles: 5, taggedArticles: 3, totalMentions: 10,
            uniqueLocations: 4, regionDistribution: [:],
            topLocations: [], topCountries: [], coveragePercent: 60.0)
        XCTAssertEqual(stats1, stats2)
    }

    func testCountProperty() {
        XCTAssertEqual(tagger.count, 0)
        _ = tagger.tagText("London calling.", articleLink: "cnt1")
        XCTAssertEqual(tagger.count, 1)
    }
}
