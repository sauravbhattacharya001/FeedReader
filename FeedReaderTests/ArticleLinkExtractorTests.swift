//
//  ArticleLinkExtractorTests.swift
//  FeedReaderTests
//
//  Tests for ArticleLinkExtractor: link parsing, categorization,
//  domain extraction, export formats, overlap detection, and search.
//

import XCTest
@testable import FeedReader

final class ArticleLinkExtractorTests: XCTestCase {

    private var extractor: ArticleLinkExtractor!

    override func setUp() {
        super.setUp()
        extractor = ArticleLinkExtractor.shared
        extractor.removeAllLinks()
    }

    override func tearDown() {
        extractor.removeAllLinks()
        super.tearDown()
    }

    // MARK: - Link Categorization

    func testCategorizeSocialDomains() {
        let html = """
        <a href="https://twitter.com/user">Tweet</a>
        <a href="https://www.reddit.com/r/swift">Reddit</a>
        <a href="https://mastodon.social/@user">Mastodon</a>
        """
        let links = extractor.extractLinks(from: html, articleId: "cat-social",
                                           articleTitle: "Social Test")
        XCTAssertEqual(links.count, 3)
        XCTAssertTrue(links.allSatisfy { $0.category == .social })
    }

    func testCategorizeVideoDomains() {
        let html = """
        <a href="https://youtube.com/watch?v=abc">YouTube</a>
        <a href="https://vimeo.com/123456">Vimeo</a>
        """
        let links = extractor.extractLinks(from: html, articleId: "cat-video",
                                           articleTitle: "Video Test")
        XCTAssertEqual(links.count, 2)
        XCTAssertTrue(links.allSatisfy { $0.category == .video })
    }

    func testCategorizeCodeDomains() {
        let html = """
        <a href="https://github.com/apple/swift">Swift Repo</a>
        <a href="https://codepen.io/pen/abc">CodePen</a>
        """
        let links = extractor.extractLinks(from: html, articleId: "cat-code",
                                           articleTitle: "Code Test")
        XCTAssertEqual(links.count, 2)
        XCTAssertTrue(links.allSatisfy { $0.category == .code })
    }

    func testCategorizeReferenceDomains() {
        let html = """
        <a href="https://en.wikipedia.org/wiki/Swift">Wikipedia</a>
        <a href="https://arxiv.org/abs/2301.00001">ArXiv Paper</a>
        <a href="https://stackoverflow.com/q/123">SO Question</a>
        """
        let links = extractor.extractLinks(from: html, articleId: "cat-ref",
                                           articleTitle: "Reference Test")
        XCTAssertEqual(links.count, 3)
        XCTAssertTrue(links.allSatisfy { $0.category == .reference })
    }

    func testCategorizeImageByExtension() {
        let html = """
        <a href="https://example.com/photo.jpg">Photo</a>
        <a href="https://cdn.example.com/icon.png">Icon</a>
        <a href="https://example.com/anim.gif">GIF</a>
        """
        let links = extractor.extractLinks(from: html, articleId: "cat-img",
                                           articleTitle: "Image Test")
        XCTAssertEqual(links.count, 3)
        XCTAssertTrue(links.allSatisfy { $0.category == .image })
    }

    func testCategorizeDocumentByExtension() {
        let html = """
        <a href="https://example.com/report.pdf">PDF Report</a>
        <a href="https://example.com/data.xlsx">Excel Data</a>
        """
        let links = extractor.extractLinks(from: html, articleId: "cat-doc",
                                           articleTitle: "Document Test")
        XCTAssertEqual(links.count, 2)
        XCTAssertTrue(links.allSatisfy { $0.category == .document })
    }

    func testCategorizeArticleByPathPattern() {
        let html = """
        <a href="https://example.com/blog/my-post">Blog Post</a>
        <a href="https://news.site.com/article/breaking-news">News Article</a>
        """
        let links = extractor.extractLinks(from: html, articleId: "cat-article",
                                           articleTitle: "Article Test")
        XCTAssertEqual(links.count, 2)
        XCTAssertTrue(links.allSatisfy { $0.category == .article })
    }

    func testCategorizeOtherFallback() {
        let html = """
        <a href="https://random-site.example.org/page">Random</a>
        """
        let links = extractor.extractLinks(from: html, articleId: "cat-other",
                                           articleTitle: "Other Test")
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.category, .other)
    }

    // MARK: - Link Parsing

    func testSkipsNonHttpLinks() {
        let html = """
        <a href="javascript:void(0)">JS Link</a>
        <a href="mailto:test@example.com">Email</a>
        <a href="#section">Anchor</a>
        <a href="ftp://files.example.com/data">FTP</a>
        <a href="https://valid.com/page">Valid</a>
        """
        let links = extractor.extractLinks(from: html, articleId: "parse-skip",
                                           articleTitle: "Skip Test")
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.url, "https://valid.com/page")
    }

    func testDeduplicatesUrls() {
        let html = """
        <a href="https://example.com/page">First</a>
        <a href="https://example.com/page">Duplicate</a>
        <a href="https://example.com/other">Different</a>
        """
        let links = extractor.extractLinks(from: html, articleId: "parse-dedup",
                                           articleTitle: "Dedup Test")
        XCTAssertEqual(links.count, 2)
    }

    func testStripsHtmlFromAnchorText() {
        let html = """
        <a href="https://example.com"><strong>Bold</strong> text</a>
        """
        let links = extractor.extractLinks(from: html, articleId: "parse-strip",
                                           articleTitle: "Strip Test")
        XCTAssertEqual(links.first?.anchorText, "Bold text")
    }

    func testDomainExtractsWithoutWwwPrefix() {
        let html = """
        <a href="https://www.example.com/page">With WWW</a>
        <a href="https://api.example.com/data">Without WWW</a>
        """
        let links = extractor.extractLinks(from: html, articleId: "parse-domain",
                                           articleTitle: "Domain Test")
        XCTAssertEqual(links[0].domain, "example.com")
        XCTAssertEqual(links[1].domain, "api.example.com")
    }

    func testEmptyHtmlReturnsNoLinks() {
        let links = extractor.extractLinks(from: "", articleId: "parse-empty",
                                           articleTitle: "Empty Test")
        XCTAssertTrue(links.isEmpty)
    }

    func testReExtractionReplacesOldLinks() {
        let html1 = #"<a href="https://one.com">One</a>"#
        let html2 = #"<a href="https://two.com">Two</a>"#

        extractor.extractLinks(from: html1, articleId: "reextract", articleTitle: "T")
        XCTAssertEqual(extractor.links(forArticle: "reextract").count, 1)
        XCTAssertEqual(extractor.links(forArticle: "reextract").first?.url, "https://one.com")

        extractor.extractLinks(from: html2, articleId: "reextract", articleTitle: "T")
        XCTAssertEqual(extractor.links(forArticle: "reextract").count, 1)
        XCTAssertEqual(extractor.links(forArticle: "reextract").first?.url, "https://two.com")
    }

    // MARK: - Link Density

    func testLinkDensityCalculation() {
        let html = """
        <a href="https://a.com">A</a>
        <a href="https://b.com">B</a>
        <a href="https://c.com">C</a>
        <a href="https://d.com">D</a>
        <a href="https://e.com">E</a>
        """
        extractor.extractLinks(from: html, articleId: "density", articleTitle: "Density",
                               wordCount: 500)
        let summary = extractor.summaries.first { $0.articleId == "density" }
        XCTAssertNotNil(summary)
        // 5 links / 500 words * 1000 = 10.0
        XCTAssertEqual(summary?.linkDensity ?? 0, 10.0, accuracy: 0.01)
    }

    func testLinkDensityZeroWhenNoWordCount() {
        let html = #"<a href="https://a.com">A</a>"#
        extractor.extractLinks(from: html, articleId: "density-zero", articleTitle: "D")
        let summary = extractor.summaries.first { $0.articleId == "density-zero" }
        XCTAssertEqual(summary?.linkDensity ?? -1, 0.0, accuracy: 0.001)
    }

    // MARK: - Queries

    func testLinksByCategory() {
        let html = """
        <a href="https://github.com/repo">Code</a>
        <a href="https://twitter.com/user">Social</a>
        <a href="https://example.com/page">Other</a>
        """
        extractor.extractLinks(from: html, articleId: "q-cat", articleTitle: "Q")
        XCTAssertEqual(extractor.links(byCategory: .code).count, 1)
        XCTAssertEqual(extractor.links(byCategory: .social).count, 1)
    }

    func testLinksByDomain() {
        let html = """
        <a href="https://github.com/a">A</a>
        <a href="https://github.com/b">B</a>
        <a href="https://twitter.com/c">C</a>
        """
        extractor.extractLinks(from: html, articleId: "q-domain", articleTitle: "Q")
        XCTAssertEqual(extractor.links(fromDomain: "github.com").count, 2)
        XCTAssertEqual(extractor.links(fromDomain: "twitter.com").count, 1)
    }

    func testDomainFrequency() {
        let html = """
        <a href="https://github.com/a">A</a>
        <a href="https://github.com/b">B</a>
        <a href="https://github.com/c">C</a>
        <a href="https://twitter.com/d">D</a>
        """
        extractor.extractLinks(from: html, articleId: "q-freq", articleTitle: "Q")
        let freq = extractor.domainFrequency()
        XCTAssertEqual(freq.first?.domain, "github.com")
        XCTAssertEqual(freq.first?.count, 3)
    }

    func testCategoryDistribution() {
        let html = """
        <a href="https://github.com/a">A</a>
        <a href="https://twitter.com/b">B</a>
        """
        extractor.extractLinks(from: html, articleId: "q-dist", articleTitle: "Q")
        let dist = extractor.categoryDistribution()
        XCTAssertFalse(dist.isEmpty)
        let total = dist.reduce(0.0) { $0 + $1.percentage }
        XCTAssertEqual(total, 100.0, accuracy: 0.1)
    }

    func testSearchByUrl() {
        let html = #"<a href="https://github.com/apple/swift">Swift</a>"#
        extractor.extractLinks(from: html, articleId: "q-search", articleTitle: "Q")
        XCTAssertEqual(extractor.search(query: "apple/swift").count, 1)
        XCTAssertEqual(extractor.search(query: "nonexistent").count, 0)
    }

    func testSearchByAnchorText() {
        let html = #"<a href="https://example.com">Machine Learning Guide</a>"#
        extractor.extractLinks(from: html, articleId: "q-search-anchor", articleTitle: "Q")
        XCTAssertEqual(extractor.search(query: "machine learning").count, 1)
    }

    // MARK: - Overlap Detection

    func testFindOverlapsDetectsSharedLinks() {
        let html1 = """
        <a href="https://shared.com/page1">Shared 1</a>
        <a href="https://shared.com/page2">Shared 2</a>
        <a href="https://only-a.com">Only A</a>
        """
        let html2 = """
        <a href="https://shared.com/page1">Shared 1</a>
        <a href="https://shared.com/page2">Shared 2</a>
        <a href="https://only-b.com">Only B</a>
        """
        extractor.extractLinks(from: html1, articleId: "overlap-a", articleTitle: "A")
        extractor.extractLinks(from: html2, articleId: "overlap-b", articleTitle: "B")

        let overlaps = extractor.findOverlaps(minSharedUrls: 2)
        XCTAssertEqual(overlaps.count, 1)
        XCTAssertEqual(overlaps.first?.sharedUrls.count, 2)
        XCTAssertGreaterThan(overlaps.first?.overlapScore ?? 0, 0.0)
    }

    func testFindOverlapsRespectsMinSharedThreshold() {
        let html1 = #"<a href="https://shared.com/one">One</a>"#
        let html2 = #"<a href="https://shared.com/one">One</a>"#
        extractor.extractLinks(from: html1, articleId: "thresh-a", articleTitle: "A")
        extractor.extractLinks(from: html2, articleId: "thresh-b", articleTitle: "B")

        // Only 1 shared URL, threshold is 2
        let overlaps = extractor.findOverlaps(minSharedUrls: 2)
        XCTAssertTrue(overlaps.isEmpty)

        // Lower threshold
        let overlaps1 = extractor.findOverlaps(minSharedUrls: 1)
        XCTAssertEqual(overlaps1.count, 1)
    }

    // MARK: - Export

    func testExportCSVFormat() {
        let html = #"<a href="https://example.com/page">Test Link</a>"#
        extractor.extractLinks(from: html, articleId: "export-csv", articleTitle: "Export CSV")

        let csv = extractor.exportCSV(forArticle: "export-csv")
        XCTAssertTrue(csv.hasPrefix("URL,Anchor Text,Category,Domain,Source Article,Health Status,HTTP Code\n"))
        XCTAssertTrue(csv.contains("https://example.com/page"))
        XCTAssertTrue(csv.contains("Test Link"))
        XCTAssertTrue(csv.contains("unchecked"))
    }

    func testExportMarkdownFormat() {
        let html = #"<a href="https://github.com/repo">My Repo</a>"#
        extractor.extractLinks(from: html, articleId: "export-md", articleTitle: "Export MD")

        let md = extractor.exportMarkdown(forArticle: "export-md")
        XCTAssertTrue(md.contains("# Extracted Links"))
        XCTAssertTrue(md.contains("**Total:** 1 links"))
        XCTAssertTrue(md.contains("💻 Code"))
        XCTAssertTrue(md.contains("[My Repo](https://github.com/repo)"))
    }

    func testExportMarkdownEmptyReturnsPlaceholder() {
        let md = extractor.exportMarkdown(forArticle: "nonexistent")
        XCTAssertTrue(md.contains("No links found"))
    }

    func testExportJSONIsValidJSON() {
        let html = #"<a href="https://example.com">Test</a>"#
        extractor.extractLinks(from: html, articleId: "export-json", articleTitle: "Export JSON")

        let json = extractor.exportJSON(forArticle: "export-json")
        let data = json.data(using: .utf8)!
        XCTAssertNoThrow(try JSONDecoder().decode([ExtractedLink].self, from: data))
    }

    // MARK: - Statistics

    func testStatisticsAccuracy() {
        let html = """
        <a href="https://github.com/a">A</a>
        <a href="https://twitter.com/b">B</a>
        """
        extractor.extractLinks(from: html, articleId: "stats", articleTitle: "Stats")
        let stats = extractor.statistics()

        XCTAssertEqual(stats["totalLinks"] as? Int, 2)
        XCTAssertEqual(stats["totalArticles"] as? Int, 1)
        XCTAssertEqual(stats["uniqueDomains"] as? Int, 2)
        XCTAssertEqual(stats["uncheckedLinks"] as? Int, 2)
    }

    // MARK: - Cleanup

    func testRemoveLinksForArticle() {
        let html = #"<a href="https://example.com">E</a>"#
        extractor.extractLinks(from: html, articleId: "cleanup-a", articleTitle: "A")
        extractor.extractLinks(from: html.replacingOccurrences(of: "example.com", with: "other.com"),
                               articleId: "cleanup-b", articleTitle: "B")

        XCTAssertEqual(extractor.links.count, 2)
        extractor.removeLinks(forArticle: "cleanup-a")
        XCTAssertEqual(extractor.links.count, 1)
        XCTAssertEqual(extractor.links.first?.sourceArticleId, "cleanup-b")
    }

    func testRemoveAllLinks() {
        let html = #"<a href="https://example.com">E</a>"#
        extractor.extractLinks(from: html, articleId: "all-a", articleTitle: "A")
        extractor.extractLinks(from: html.replacingOccurrences(of: "example.com", with: "other.com"),
                               articleId: "all-b", articleTitle: "B")
        XCTAssertFalse(extractor.links.isEmpty)

        extractor.removeAllLinks()
        XCTAssertTrue(extractor.links.isEmpty)
        XCTAssertTrue(extractor.summaries.isEmpty)
    }

    // MARK: - LinkCategory

    func testLinkCategoryDisplayName() {
        XCTAssertEqual(LinkCategory.article.displayName, "Article")
        XCTAssertEqual(LinkCategory.social.displayName, "Social")
        XCTAssertEqual(LinkCategory.code.displayName, "Code")
    }

    func testLinkCategoryEmoji() {
        XCTAssertEqual(LinkCategory.article.emoji, "📰")
        XCTAssertEqual(LinkCategory.video.emoji, "🎬")
        XCTAssertEqual(LinkCategory.code.emoji, "💻")
    }

    func testLinkCategoryComparable() {
        XCTAssertTrue(LinkCategory.article < LinkCategory.social)
        XCTAssertTrue(LinkCategory.code < LinkCategory.other)
    }

    // MARK: - LinkHealthStatus

    func testLinkHealthStatusEmoji() {
        XCTAssertEqual(LinkHealthStatus.alive.emoji, "✅")
        XCTAssertEqual(LinkHealthStatus.dead.emoji, "❌")
        XCTAssertEqual(LinkHealthStatus.unchecked.emoji, "❓")
    }

    // MARK: - Notification

    func testLinksDidExtractNotificationFired() {
        let expectation = self.expectation(forNotification: .linksDidExtract, object: nil) { notification in
            let count = notification.userInfo?["count"] as? Int
            return count == 2
        }

        let html = """
        <a href="https://a.com">A</a>
        <a href="https://b.com">B</a>
        """
        extractor.extractLinks(from: html, articleId: "notif", articleTitle: "Notif")

        wait(for: [expectation], timeout: 1.0)
    }
}
