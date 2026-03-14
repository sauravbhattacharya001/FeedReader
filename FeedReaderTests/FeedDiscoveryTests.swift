//
//  FeedDiscoveryTests.swift
//  FeedReaderTests
//
//  Tests for FeedDiscoveryManager — HTML link tag parsing,
//  URL resolution, common path fallback, feed detection,
//  URL validation, deduplication, and edge cases.
//

import XCTest
@testable import FeedReader

class FeedDiscoveryTests: XCTestCase {
    
    private var manager: FeedDiscoveryManager!
    
    override func setUp() {
        super.setUp()
        manager = FeedDiscoveryManager.shared
    }
    
    // MARK: - extractFeedLinks: basic RSS link tags
    
    func testExtractRSSLink() {
        let html = """
        <html><head>
        <link rel="alternate" type="application/rss+xml" title="My Blog" href="/feed" />
        </head></html>
        """
        let feeds = FeedDiscoveryManager.extractFeedLinks(from: html, baseURL: "https://example.com")
        XCTAssertEqual(feeds.count, 1)
        XCTAssertEqual(feeds[0].url, "https://example.com/feed")
        XCTAssertEqual(feeds[0].title, "My Blog")
        XCTAssertEqual(feeds[0].source, .linkTag)
    }
    
    func testExtractAtomLink() {
        let html = """
        <html><head>
        <link rel="alternate" type="application/atom+xml" title="Atom Feed" href="/atom.xml" />
        </head></html>
        """
        let feeds = FeedDiscoveryManager.extractFeedLinks(from: html, baseURL: "https://example.com")
        XCTAssertEqual(feeds.count, 1)
        XCTAssertEqual(feeds[0].url, "https://example.com/atom.xml")
        XCTAssertEqual(feeds[0].title, "Atom Feed")
    }
    
    func testExtractMultipleLinks() {
        let html = """
        <html><head>
        <link rel="alternate" type="application/rss+xml" title="Posts" href="/feed" />
        <link rel="alternate" type="application/atom+xml" title="Comments" href="/comments/feed" />
        <link rel="alternate" type="application/rss+xml" title="Category" href="/cat/tech/feed" />
        </head></html>
        """
        let feeds = FeedDiscoveryManager.extractFeedLinks(from: html, baseURL: "https://blog.example.com")
        XCTAssertEqual(feeds.count, 3)
        XCTAssertEqual(feeds[0].title, "Posts")
        XCTAssertEqual(feeds[1].title, "Comments")
        XCTAssertEqual(feeds[2].title, "Category")
    }
    
    // MARK: - extractFeedLinks: attribute variations
    
    func testSingleQuoteAttributes() {
        let html = "<link rel='alternate' type='application/rss+xml' title='Feed' href='/rss' />"
        let feeds = FeedDiscoveryManager.extractFeedLinks(from: html, baseURL: "https://example.com")
        XCTAssertEqual(feeds.count, 1)
        XCTAssertEqual(feeds[0].url, "https://example.com/rss")
    }
    
    func testCaseInsensitiveType() {
        let html = """
        <LINK REL="alternate" TYPE="Application/RSS+XML" TITLE="Feed" HREF="/feed" />
        """
        let feeds = FeedDiscoveryManager.extractFeedLinks(from: html, baseURL: "https://example.com")
        XCTAssertEqual(feeds.count, 1)
    }
    
    func testMixedCaseAttributes() {
        let html = """
        <link Rel="alternate" Type="application/rss+xml" Title="Feed" Href="/feed" />
        """
        let feeds = FeedDiscoveryManager.extractFeedLinks(from: html, baseURL: "https://example.com")
        XCTAssertEqual(feeds.count, 1)
    }
    
    // MARK: - extractFeedLinks: filtering
    
    func testIgnoresNonAlternateRel() {
        let html = """
        <link rel="stylesheet" type="application/rss+xml" href="/feed" />
        """
        let feeds = FeedDiscoveryManager.extractFeedLinks(from: html, baseURL: "https://example.com")
        XCTAssertEqual(feeds.count, 0)
    }
    
    func testIgnoresNonFeedType() {
        let html = """
        <link rel="alternate" type="text/html" href="/page" />
        """
        let feeds = FeedDiscoveryManager.extractFeedLinks(from: html, baseURL: "https://example.com")
        XCTAssertEqual(feeds.count, 0)
    }
    
    func testIgnoresLinkWithoutHref() {
        let html = """
        <link rel="alternate" type="application/rss+xml" title="Feed" />
        """
        let feeds = FeedDiscoveryManager.extractFeedLinks(from: html, baseURL: "https://example.com")
        XCTAssertEqual(feeds.count, 0)
    }
    
    func testDeduplicatesByURL() {
        let html = """
        <link rel="alternate" type="application/rss+xml" title="Feed 1" href="/feed" />
        <link rel="alternate" type="application/atom+xml" title="Feed 2" href="/feed" />
        """
        let feeds = FeedDiscoveryManager.extractFeedLinks(from: html, baseURL: "https://example.com")
        XCTAssertEqual(feeds.count, 1)
        XCTAssertEqual(feeds[0].title, "Feed 1") // First one wins
    }
    
    // MARK: - extractFeedLinks: empty/invalid input
    
    func testEmptyHTML() {
        let feeds = FeedDiscoveryManager.extractFeedLinks(from: "", baseURL: "https://example.com")
        XCTAssertEqual(feeds.count, 0)
    }
    
    func testHTMLWithNoLinks() {
        let html = "<html><head><title>Page</title></head><body>Hello</body></html>"
        let feeds = FeedDiscoveryManager.extractFeedLinks(from: html, baseURL: "https://example.com")
        XCTAssertEqual(feeds.count, 0)
    }
    
    func testOversizedHTMLRejected() {
        let html = String(repeating: "x", count: FeedDiscoveryManager.maxHTMLSize + 1)
        let feeds = FeedDiscoveryManager.extractFeedLinks(from: html, baseURL: "https://example.com")
        XCTAssertEqual(feeds.count, 0)
    }
    
    // MARK: - extractFeedLinks: URL types
    
    func testAbsoluteHref() {
        let html = """
        <link rel="alternate" type="application/rss+xml" href="https://cdn.example.com/feed.xml" />
        """
        let feeds = FeedDiscoveryManager.extractFeedLinks(from: html, baseURL: "https://example.com")
        XCTAssertEqual(feeds[0].url, "https://cdn.example.com/feed.xml")
    }
    
    func testProtocolRelativeHref() {
        let html = """
        <link rel="alternate" type="application/rss+xml" href="//cdn.example.com/feed" />
        """
        let feeds = FeedDiscoveryManager.extractFeedLinks(from: html, baseURL: "https://example.com")
        XCTAssertEqual(feeds[0].url, "https://cdn.example.com/feed")
    }
    
    func testProtocolRelativeWithHTTP() {
        let html = """
        <link rel="alternate" type="application/rss+xml" href="//cdn.example.com/feed" />
        """
        let feeds = FeedDiscoveryManager.extractFeedLinks(from: html, baseURL: "http://example.com")
        XCTAssertEqual(feeds[0].url, "http://cdn.example.com/feed")
    }
    
    func testRelativeHref() {
        let html = """
        <link rel="alternate" type="application/rss+xml" href="feed.xml" />
        """
        let feeds = FeedDiscoveryManager.extractFeedLinks(from: html, baseURL: "https://example.com/blog/")
        XCTAssertEqual(feeds[0].url, "https://example.com/blog/feed.xml")
    }
    
    // MARK: - extractFeedLinks: title fallback
    
    func testTitleFallbackFromURL() {
        let html = """
        <link rel="alternate" type="application/rss+xml" href="/feed.xml" />
        """
        let feeds = FeedDiscoveryManager.extractFeedLinks(from: html, baseURL: "https://example.com")
        // Title should be derived from URL since no title attribute
        XCTAssertFalse(feeds[0].title.isEmpty)
    }
    
    // MARK: - resolveURL
    
    func testResolveAbsoluteURL() {
        let result = FeedDiscoveryManager.resolveURL("https://other.com/feed", base: "https://example.com")
        XCTAssertEqual(result, "https://other.com/feed")
    }
    
    func testResolveRootRelative() {
        let result = FeedDiscoveryManager.resolveURL("/feed", base: "https://example.com/blog/post")
        XCTAssertEqual(result, "https://example.com/feed")
    }
    
    func testResolveProtocolRelative() {
        let result = FeedDiscoveryManager.resolveURL("//cdn.example.com/rss", base: "https://example.com")
        XCTAssertEqual(result, "https://cdn.example.com/rss")
    }
    
    func testResolveRelativePath() {
        let result = FeedDiscoveryManager.resolveURL("rss.xml", base: "https://example.com/blog/index.html")
        XCTAssertTrue(result.contains("rss.xml"))
        XCTAssertTrue(result.hasPrefix("https://"))
    }
    
    func testResolveEmptyHref() {
        let result = FeedDiscoveryManager.resolveURL("", base: "https://example.com")
        XCTAssertEqual(result, "")
    }
    
    func testResolveWithBadBase() {
        let result = FeedDiscoveryManager.resolveURL("/feed", base: "not-a-url")
        XCTAssertEqual(result, "")
    }
    
    // MARK: - extractOrigin
    
    func testExtractOriginHTTPS() {
        let origin = FeedDiscoveryManager.extractOrigin(from: "https://example.com/path")
        XCTAssertEqual(origin, "https://example.com")
    }
    
    func testExtractOriginHTTP() {
        let origin = FeedDiscoveryManager.extractOrigin(from: "http://example.com:8080/path")
        XCTAssertEqual(origin, "http://example.com:8080")
    }
    
    func testExtractOriginNoPath() {
        let origin = FeedDiscoveryManager.extractOrigin(from: "https://example.com")
        XCTAssertEqual(origin, "https://example.com")
    }
    
    func testExtractOriginInvalidURL() {
        let origin = FeedDiscoveryManager.extractOrigin(from: "ftp://example.com")
        XCTAssertNil(origin)
    }
    
    // MARK: - extractPath
    
    func testExtractPathWithPath() {
        let path = FeedDiscoveryManager.extractPath(from: "https://example.com/blog/post")
        XCTAssertEqual(path, "/blog/post")
    }
    
    func testExtractPathNoPath() {
        let path = FeedDiscoveryManager.extractPath(from: "https://example.com")
        XCTAssertEqual(path, "/")
    }
    
    func testExtractPathRootSlash() {
        let path = FeedDiscoveryManager.extractPath(from: "https://example.com/")
        XCTAssertEqual(path, "/")
    }
    
    // MARK: - normalizeURL
    
    func testNormalizeRemovesTrailingSlash() {
        let normalized = FeedDiscoveryManager.normalizeURL("https://Example.com/feed/")
        XCTAssertEqual(normalized, "https://example.com/feed")
    }
    
    func testNormalizeLowercasesSchemeAndHost() {
        let normalized = FeedDiscoveryManager.normalizeURL("HTTPS://EXAMPLE.COM/Feed")
        XCTAssertEqual(normalized, "https://example.com/Feed")
    }
    
    func testNormalizePreservesPathCase() {
        let normalized = FeedDiscoveryManager.normalizeURL("https://example.com/MyFeed")
        XCTAssertEqual(normalized, "https://example.com/MyFeed")
    }
    
    func testNormalizeTrimsWhitespace() {
        let normalized = FeedDiscoveryManager.normalizeURL("  https://example.com/feed  ")
        XCTAssertEqual(normalized, "https://example.com/feed")
    }
    
    // MARK: - extractAttribute
    
    func testExtractAttributeDoubleQuotes() {
        let value = FeedDiscoveryManager.extractAttribute(
            "<link rel=\"alternate\" href=\"/feed\">", name: "href")
        XCTAssertEqual(value, "/feed")
    }
    
    func testExtractAttributeSingleQuotes() {
        let value = FeedDiscoveryManager.extractAttribute(
            "<link rel='alternate' href='/rss'>", name: "href")
        XCTAssertEqual(value, "/rss")
    }
    
    func testExtractAttributeNotFound() {
        let value = FeedDiscoveryManager.extractAttribute("<link rel=\"alternate\">", name: "href")
        XCTAssertNil(value)
    }
    
    func testExtractAttributeWithSpaces() {
        let value = FeedDiscoveryManager.extractAttribute(
            "<link href = \"  /feed  \" >", name: "href")
        XCTAssertEqual(value, "/feed")
    }
    
    // MARK: - containsAttribute
    
    func testContainsAttributeTrue() {
        XCTAssertTrue(FeedDiscoveryManager.containsAttribute(
            "<link rel=\"alternate\">", name: "rel", value: "alternate"))
    }
    
    func testContainsAttributeFalse() {
        XCTAssertFalse(FeedDiscoveryManager.containsAttribute(
            "<link rel=\"stylesheet\">", name: "rel", value: "alternate"))
    }
    
    func testContainsAttributeCaseInsensitive() {
        XCTAssertTrue(FeedDiscoveryManager.containsAttribute(
            "<link rel=\"Alternate\">", name: "rel", value: "alternate"))
    }
    
    // MARK: - looksLikeFeed
    
    func testLooksLikeFeedRSS() {
        XCTAssertTrue(FeedDiscoveryManager.looksLikeFeed(
            "<?xml version=\"1.0\"?><rss version=\"2.0\"><channel>..."))
    }
    
    func testLooksLikeFeedAtom() {
        XCTAssertTrue(FeedDiscoveryManager.looksLikeFeed(
            "<feed xmlns=\"http://www.w3.org/2005/Atom\">"))
    }
    
    func testLooksLikeFeedRDF() {
        XCTAssertTrue(FeedDiscoveryManager.looksLikeFeed(
            "<rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">"))
    }
    
    func testLooksLikeFeedHTML() {
        XCTAssertFalse(FeedDiscoveryManager.looksLikeFeed(
            "<html><head><title>Page</title></head></html>"))
    }
    
    func testLooksLikeFeedEmpty() {
        XCTAssertFalse(FeedDiscoveryManager.looksLikeFeed(""))
    }
    
    func testLooksLikeFeedPlainText() {
        XCTAssertFalse(FeedDiscoveryManager.looksLikeFeed("Hello World"))
    }
    
    func testLooksLikeFeedJSON() {
        XCTAssertFalse(FeedDiscoveryManager.looksLikeFeed("{\"items\": []}"))
    }
    
    func testLooksLikeFeedWithWhitespace() {
        XCTAssertTrue(FeedDiscoveryManager.looksLikeFeed(
            "\n  <?xml version=\"1.0\"?>\n<rss version=\"2.0\">"))
    }
    
    // MARK: - isValidFeedURL
    
    func testValidHTTPSURL() {
        XCTAssertTrue(FeedDiscoveryManager.isValidFeedURL("https://example.com/feed"))
    }
    
    func testValidHTTPURL() {
        XCTAssertTrue(FeedDiscoveryManager.isValidFeedURL("http://example.com/rss"))
    }
    
    func testInvalidEmptyURL() {
        XCTAssertFalse(FeedDiscoveryManager.isValidFeedURL(""))
    }
    
    func testInvalidJavascriptURL() {
        XCTAssertFalse(FeedDiscoveryManager.isValidFeedURL("javascript:alert(1)"))
    }
    
    func testInvalidDataURL() {
        XCTAssertFalse(FeedDiscoveryManager.isValidFeedURL("data:text/html,<h1>Hi</h1>"))
    }
    
    func testInvalidFileURL() {
        XCTAssertFalse(FeedDiscoveryManager.isValidFeedURL("file:///etc/passwd"))
    }
    
    func testInvalidFTPURL() {
        XCTAssertFalse(FeedDiscoveryManager.isValidFeedURL("ftp://example.com/feed"))
    }
    
    func testInvalidNoHost() {
        XCTAssertFalse(FeedDiscoveryManager.isValidFeedURL("https://"))
    }
    
    func testInvalidNoDot() {
        XCTAssertFalse(FeedDiscoveryManager.isValidFeedURL("https://localhost/feed"))
    }
    
    func testValidWithPort() {
        XCTAssertTrue(FeedDiscoveryManager.isValidFeedURL("https://example.com:8080/feed"))
    }
    
    func testValidWithQueryString() {
        XCTAssertTrue(FeedDiscoveryManager.isValidFeedURL("https://example.com/feed?format=rss"))
    }
    
    func testURLWithWhitespace() {
        XCTAssertTrue(FeedDiscoveryManager.isValidFeedURL("  https://example.com/feed  "))
    }
    
    // MARK: - SSRF Protection in isValidFeedURL
    
    func testRejectsPrivateIP10() {
        XCTAssertFalse(FeedDiscoveryManager.isValidFeedURL("http://10.0.0.1/feed"))
    }
    
    func testRejectsPrivateIP172() {
        XCTAssertFalse(FeedDiscoveryManager.isValidFeedURL("http://172.16.0.1/feed"))
    }
    
    func testRejectsPrivateIP192() {
        XCTAssertFalse(FeedDiscoveryManager.isValidFeedURL("http://192.168.1.1/feed"))
    }
    
    func testRejectsLoopback() {
        XCTAssertFalse(FeedDiscoveryManager.isValidFeedURL("http://127.0.0.1/feed"))
    }
    
    func testRejectsCloudMetadata() {
        XCTAssertFalse(FeedDiscoveryManager.isValidFeedURL("http://169.254.169.254/latest/meta-data/"))
    }
    
    func testRejectsLocalhostDomain() {
        XCTAssertFalse(FeedDiscoveryManager.isValidFeedURL("http://localhost.localdomain/feed"))
    }
    
    // MARK: - feedTitleFromURL
    
    func testTitleFromFeedPath() {
        let title = FeedDiscoveryManager.feedTitleFromURL("https://example.com/feed")
        XCTAssertEqual(title, "Feed")
    }
    
    func testTitleFromXMLPath() {
        let title = FeedDiscoveryManager.feedTitleFromURL("https://example.com/rss.xml")
        XCTAssertEqual(title, "Rss")
    }
    
    func testTitleFromNestedPath() {
        let title = FeedDiscoveryManager.feedTitleFromURL("https://example.com/blog/feed.xml")
        XCTAssertEqual(title, "Feed")
    }
    
    func testTitleFromRootPath() {
        let title = FeedDiscoveryManager.feedTitleFromURL("https://example.com/")
        XCTAssertTrue(title.contains("example.com"))
    }
    
    func testTitleFromEmptyPath() {
        let title = FeedDiscoveryManager.feedTitleFromURL("https://example.com")
        XCTAssertTrue(title.contains("example.com"))
    }
    
    // MARK: - discoverFromHTML: with fallback
    
    func testDiscoverFallsBackToCommonPaths() {
        let html = "<html><head><title>No feeds here</title></head></html>"
        let feeds = manager.discoverFromHTML(html, baseURL: "https://example.com")
        XCTAssertTrue(feeds.count > 0)
        XCTAssertTrue(feeds.allSatisfy { $0.source == .commonPath })
    }
    
    func testDiscoverNoFallbackWhenLinksFound() {
        let html = """
        <html><head>
        <link rel="alternate" type="application/rss+xml" href="/feed" />
        </head></html>
        """
        let feeds = manager.discoverFromHTML(html, baseURL: "https://example.com")
        XCTAssertEqual(feeds.count, 1)
        XCTAssertEqual(feeds[0].source, .linkTag)
    }
    
    func testDiscoverWithFallbackDisabled() {
        let html = "<html><head><title>No feeds</title></head></html>"
        let feeds = manager.discoverFromHTML(html, baseURL: "https://example.com",
                                             includeCommonPaths: false)
        XCTAssertEqual(feeds.count, 0)
    }
    
    // MARK: - generateCommonPathCandidates
    
    func testCommonPathCandidatesNotEmpty() {
        let candidates = manager.generateCommonPathCandidates(baseURL: "https://example.com")
        XCTAssertTrue(candidates.count > 0)
        XCTAssertTrue(candidates.count <= FeedDiscoveryManager.commonFeedPaths.count)
    }
    
    func testCommonPathCandidatesAllStartWithBase() {
        let candidates = manager.generateCommonPathCandidates(baseURL: "https://blog.example.com")
        for c in candidates {
            XCTAssertTrue(c.url.hasPrefix("https://blog.example.com"),
                          "Expected \(c.url) to start with https://blog.example.com")
        }
    }
    
    func testCommonPathCandidatesAllHaveCommonPathSource() {
        let candidates = manager.generateCommonPathCandidates(baseURL: "https://example.com")
        XCTAssertTrue(candidates.allSatisfy { $0.source == .commonPath })
    }
    
    func testCommonPathCandidatesNoDuplicateURLs() {
        let candidates = manager.generateCommonPathCandidates(baseURL: "https://example.com")
        let urls = candidates.map { FeedDiscoveryManager.normalizeURL($0.url) }
        XCTAssertEqual(urls.count, Set(urls).count, "Expected no duplicate URLs")
    }
    
    func testCommonPathCandidatesWithInvalidBase() {
        let candidates = manager.generateCommonPathCandidates(baseURL: "not-a-url")
        XCTAssertEqual(candidates.count, 0)
    }
    
    // MARK: - Real-world HTML patterns
    
    func testWordPressPattern() {
        let html = """
        <html><head>
        <link rel="alternate" type="application/rss+xml" title="My WordPress Blog &raquo; Feed" href="https://myblog.com/feed/" />
        <link rel="alternate" type="application/rss+xml" title="My WordPress Blog &raquo; Comments Feed" href="https://myblog.com/comments/feed/" />
        </head></html>
        """
        let feeds = FeedDiscoveryManager.extractFeedLinks(from: html, baseURL: "https://myblog.com")
        XCTAssertEqual(feeds.count, 2)
    }
    
    func testGitHubPagesPattern() {
        let html = """
        <html><head>
        <link rel="alternate" type="application/atom+xml" title="My Site - Atom" href="/feed.xml" />
        </head></html>
        """
        let feeds = FeedDiscoveryManager.extractFeedLinks(from: html, baseURL: "https://user.github.io")
        XCTAssertEqual(feeds.count, 1)
        XCTAssertEqual(feeds[0].url, "https://user.github.io/feed.xml")
    }
    
    func testMediumPattern() {
        let html = """
        <html><head>
        <link rel="alternate" type="application/rss+xml" href="https://medium.com/feed/@user" />
        </head></html>
        """
        let feeds = FeedDiscoveryManager.extractFeedLinks(from: html, baseURL: "https://medium.com/@user")
        XCTAssertEqual(feeds.count, 1)
        XCTAssertEqual(feeds[0].url, "https://medium.com/feed/@user")
    }
    
    // MARK: - DiscoveredFeed Equatable
    
    func testDiscoveredFeedEquality() {
        let a = DiscoveredFeed(url: "https://example.com/feed", title: "Feed", source: .linkTag)
        let b = DiscoveredFeed(url: "https://example.com/feed", title: "Feed", source: .linkTag)
        XCTAssertEqual(a, b)
    }
    
    func testDiscoveredFeedInequality() {
        let a = DiscoveredFeed(url: "https://example.com/feed", title: "Feed", source: .linkTag)
        let b = DiscoveredFeed(url: "https://example.com/rss", title: "Feed", source: .linkTag)
        XCTAssertNotEqual(a, b)
    }
    
    // MARK: - DiscoverySource raw values
    
    func testDiscoverySourceRawValues() {
        XCTAssertEqual(DiscoveredFeed.DiscoverySource.linkTag.rawValue, "link-tag")
        XCTAssertEqual(DiscoveredFeed.DiscoverySource.commonPath.rawValue, "common-path")
        XCTAssertEqual(DiscoveredFeed.DiscoverySource.directURL.rawValue, "direct-url")
    }
    
    // MARK: - Constants
    
    func testMaxResultsPositive() {
        XCTAssertGreaterThan(FeedDiscoveryManager.maxResults, 0)
    }
    
    func testMaxHTMLSizeReasonable() {
        XCTAssertGreaterThan(FeedDiscoveryManager.maxHTMLSize, 1000)
    }
    
    func testFeedContentTypesNotEmpty() {
        XCTAssertFalse(FeedDiscoveryManager.feedContentTypes.isEmpty)
        XCTAssertTrue(FeedDiscoveryManager.feedContentTypes.contains("application/rss+xml"))
        XCTAssertTrue(FeedDiscoveryManager.feedContentTypes.contains("application/atom+xml"))
    }
    
    func testCommonFeedPathsNotEmpty() {
        XCTAssertFalse(FeedDiscoveryManager.commonFeedPaths.isEmpty)
        XCTAssertTrue(FeedDiscoveryManager.commonFeedPaths.contains("/feed"))
        XCTAssertTrue(FeedDiscoveryManager.commonFeedPaths.contains("/rss"))
    }
}
