//
//  ArticleDigestComposerTests.swift
//  FeedReaderCoreTests
//
//  Tests for the markdown digest composition logic and supporting
//  models (DigestPeriodCore, DigestEntry).
//

import XCTest
@testable import FeedReaderCore

final class ArticleDigestComposerTests: XCTestCase {

    // MARK: - DigestPeriodCore

    func testDigestPeriodDaysMapping() {
        XCTAssertEqual(DigestPeriodCore.daily.days, 1)
        XCTAssertEqual(DigestPeriodCore.weekly.days, 7)
        XCTAssertEqual(DigestPeriodCore.monthly.days, 30)
    }

    func testDigestPeriodRawValuesAreHumanReadable() {
        XCTAssertEqual(DigestPeriodCore.daily.rawValue, "Daily")
        XCTAssertEqual(DigestPeriodCore.weekly.rawValue, "Weekly")
        XCTAssertEqual(DigestPeriodCore.monthly.rawValue, "Monthly")
    }

    func testDigestPeriodCaseIterableExposesAllCases() {
        XCTAssertEqual(
            DigestPeriodCore.allCases,
            [.daily, .weekly, .monthly]
        )
    }

    func testDigestPeriodCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for period in DigestPeriodCore.allCases {
            let data    = try encoder.encode(period)
            let decoded = try decoder.decode(DigestPeriodCore.self, from: data)
            XCTAssertEqual(decoded, period)
        }
    }

    // MARK: - DigestEntry

    func testDigestEntryInitializerStoresAllFields() {
        let entry = DigestEntry(
            title: "Swift 6 ships",
            feedName: "Swift Blog",
            url: "https://swift.org/blog/swift-6",
            snippet: "Major release",
            readingMinutes: 4
        )
        XCTAssertEqual(entry.title, "Swift 6 ships")
        XCTAssertEqual(entry.feedName, "Swift Blog")
        XCTAssertEqual(entry.url, "https://swift.org/blog/swift-6")
        XCTAssertEqual(entry.snippet, "Major release")
        XCTAssertEqual(entry.readingMinutes, 4)
    }

    func testDigestEntryCodableRoundTrip() throws {
        let entry = DigestEntry(
            title: "Title with \"quotes\" & symbols",
            feedName: "Feed",
            url: "https://example.com/article?id=42",
            snippet: "Snippet with unicode — résumé 日本語",
            readingMinutes: 7
        )

        let data    = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(DigestEntry.self, from: data)

        XCTAssertEqual(decoded.title, entry.title)
        XCTAssertEqual(decoded.feedName, entry.feedName)
        XCTAssertEqual(decoded.url, entry.url)
        XCTAssertEqual(decoded.snippet, entry.snippet)
        XCTAssertEqual(decoded.readingMinutes, entry.readingMinutes)
    }

    // MARK: - composeDigestMarkdown

    func testComposeDigestMarkdownIncludesTitleAndHeader() {
        let entry = DigestEntry(
            title: "Hello",
            feedName: "Feed A",
            url: "https://a.example/1",
            snippet: "World",
            readingMinutes: 3
        )
        let md = composeDigestMarkdown(title: "My Weekly Digest", entries: [entry])

        XCTAssertTrue(md.hasPrefix("# My Weekly Digest\n\n"),
                      "Digest should begin with a level-1 markdown title")
        XCTAssertTrue(md.contains("1 articles"), "Should report the article count")
        XCTAssertTrue(md.contains("Weekly digest"),
                      "Default period is .weekly and should appear in the header")
        XCTAssertTrue(md.contains("---"), "Should contain the horizontal rule separator")
    }

    func testComposeDigestMarkdownDefaultPeriodIsWeekly() {
        let entry = DigestEntry(
            title: "x", feedName: "F", url: "https://x.test", snippet: "", readingMinutes: 1
        )
        let md = composeDigestMarkdown(title: "T", entries: [entry])
        XCTAssertTrue(md.contains("Weekly digest"))
    }

    func testComposeDigestMarkdownHonorsExplicitPeriod() {
        let entry = DigestEntry(
            title: "x", feedName: "F", url: "https://x.test", snippet: "", readingMinutes: 1
        )
        let daily = composeDigestMarkdown(title: "T", entries: [entry], period: .daily)
        XCTAssertTrue(daily.contains("Daily digest"))
        XCTAssertFalse(daily.contains("Weekly digest"))

        let monthly = composeDigestMarkdown(title: "T", entries: [entry], period: .monthly)
        XCTAssertTrue(monthly.contains("Monthly digest"))
    }

    func testComposeDigestMarkdownGroupsEntriesByFeedNameAlphabetically() {
        // Entries supplied in non-sorted order; output sections must be A, B, C.
        let entries = [
            DigestEntry(title: "C-article", feedName: "Charlie",
                        url: "https://c.test", snippet: "", readingMinutes: 1),
            DigestEntry(title: "A-article", feedName: "Alpha",
                        url: "https://a.test", snippet: "", readingMinutes: 2),
            DigestEntry(title: "B-article", feedName: "Bravo",
                        url: "https://b.test", snippet: "", readingMinutes: 3),
        ]

        let md = composeDigestMarkdown(title: "Mixed", entries: entries)
        guard let alphaRange   = md.range(of: "## Alpha"),
              let bravoRange   = md.range(of: "## Bravo"),
              let charlieRange = md.range(of: "## Charlie")
        else {
            return XCTFail("All feed headings should appear in the digest")
        }
        XCTAssertLessThan(alphaRange.lowerBound,   bravoRange.lowerBound)
        XCTAssertLessThan(bravoRange.lowerBound,   charlieRange.lowerBound)
    }

    func testComposeDigestMarkdownGroupsMultipleArticlesUnderSameFeed() {
        let entries = [
            DigestEntry(title: "First",  feedName: "Same",
                        url: "https://s.test/1", snippet: "", readingMinutes: 2),
            DigestEntry(title: "Second", feedName: "Same",
                        url: "https://s.test/2", snippet: "", readingMinutes: 5),
        ]
        let md = composeDigestMarkdown(title: "Two", entries: entries)

        // Only one feed heading expected.
        let occurrences = md.components(separatedBy: "## Same").count - 1
        XCTAssertEqual(occurrences, 1)

        // Both article links should appear.
        XCTAssertTrue(md.contains("[First](https://s.test/1)"))
        XCTAssertTrue(md.contains("[Second](https://s.test/2)"))
        XCTAssertTrue(md.contains("(2 min)"))
        XCTAssertTrue(md.contains("(5 min)"))
    }

    func testComposeDigestMarkdownRendersBulletWithLinkAndReadingTime() {
        let entry = DigestEntry(
            title: "Cool Article",
            feedName: "Feed",
            url: "https://example.com/x",
            snippet: "",
            readingMinutes: 9
        )
        let md = composeDigestMarkdown(title: "T", entries: [entry])
        XCTAssertTrue(md.contains("- **[Cool Article](https://example.com/x)** (9 min)"))
    }

    func testComposeDigestMarkdownOmitsBlankSnippets() {
        // Empty snippet → no continuation line under the bullet.
        let entries = [
            DigestEntry(title: "WithSnippet", feedName: "Feed",
                        url: "https://example.com/a", snippet: "Has snippet text",
                        readingMinutes: 1),
            DigestEntry(title: "NoSnippet",   feedName: "Feed",
                        url: "https://example.com/b", snippet: "",
                        readingMinutes: 1),
        ]
        let md = composeDigestMarkdown(title: "T", entries: entries)

        XCTAssertTrue(md.contains("Has snippet text"),
                      "Non-empty snippets must be rendered")

        // The "NoSnippet" bullet should be followed by a blank line, not snippet text.
        // We verify by checking that no two-space-indented line follows that bullet.
        let lines = md.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let bulletIndex = lines.firstIndex(where: { $0.contains("[NoSnippet]") }) else {
            return XCTFail("NoSnippet bullet missing")
        }
        let next = lines[(bulletIndex + 1)..<min(lines.count, bulletIndex + 2)]
        for line in next {
            XCTAssertFalse(line.hasPrefix("  "),
                           "Empty snippets must not produce an indented continuation line")
        }
    }

    func testComposeDigestMarkdownWithEmptyEntries() {
        let md = composeDigestMarkdown(title: "Empty", entries: [])
        XCTAssertTrue(md.hasPrefix("# Empty\n\n"))
        XCTAssertTrue(md.contains("0 articles"))
        XCTAssertTrue(md.contains("---"))
        // No feed headings should appear when there are no entries.
        XCTAssertFalse(md.contains("##"))
    }

    func testComposeDigestMarkdownPreservesSpecialCharactersInTitleAndSnippet() {
        // The composer does not HTML/markdown-escape — that's intentional.
        // Verify the raw characters round-trip into the output.
        let entry = DigestEntry(
            title: "Title <with> & \"chars\"",
            feedName: "Feed & Co.",
            url: "https://example.com/?a=1&b=2",
            snippet: "Snippet with [brackets] and *stars*",
            readingMinutes: 3
        )
        let md = composeDigestMarkdown(title: "Raw", entries: [entry])
        XCTAssertTrue(md.contains("## Feed & Co."))
        XCTAssertTrue(md.contains("Title <with> & \"chars\""))
        XCTAssertTrue(md.contains("https://example.com/?a=1&b=2"))
        XCTAssertTrue(md.contains("Snippet with [brackets] and *stars*"))
    }
}
