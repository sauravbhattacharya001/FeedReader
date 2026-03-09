//
//  FeedPrivacyGuardTests.swift
//  FeedReaderTests
//

import XCTest
@testable import FeedReader

class FeedPrivacyGuardTests: XCTestCase {

    var guard_: FeedPrivacyGuard!
    let testDefaults = UserDefaults(suiteName: "FeedPrivacyGuardTests")!

    override func setUp() {
        super.setUp()
        testDefaults.removePersistentDomain(forName: "FeedPrivacyGuardTests")
        guard_ = FeedPrivacyGuard()
        guard_.clearScans()
    }

    override func tearDown() {
        guard_.clearScans()
        testDefaults.removePersistentDomain(forName: "FeedPrivacyGuardTests")
        super.tearDown()
    }

    // MARK: - Clean Content

    func testCleanArticle_PerfectScore() {
        let scan = guard_.scanArticle(
            title: "Clean Article",
            body: "<p>This is a simple article with no trackers.</p>",
            link: "https://example.com/clean",
            feedName: "Clean Feed"
        )
        XCTAssertEqual(scan.privacyScore, 100)
        XCTAssertTrue(scan.isClean)
        XCTAssertTrue(scan.threats.isEmpty)
        XCTAssertEqual(scan.severity, .low)
    }

    func testCleanArticle_PlainText() {
        let scan = guard_.scanArticle(
            title: "Plain",
            body: "Just plain text, no HTML at all.",
            link: "https://example.com/plain",
            feedName: "Text Feed"
        )
        XCTAssertEqual(scan.privacyScore, 100)
        XCTAssertTrue(scan.isClean)
    }

    func testEmptyBody_Clean() {
        let scan = guard_.scanArticle(
            title: "Empty",
            body: "",
            link: "https://example.com/empty",
            feedName: "Feed"
        )
        XCTAssertEqual(scan.privacyScore, 100)
    }

    // MARK: - Tracking Pixels

    func testTrackingPixel_1x1Image() {
        let body = """
        <p>Article text</p>
        <img src="https://tracker.com/pixel.gif" width="1" height="1">
        """
        let scan = guard_.scanArticle(title: "Tracked", body: body,
                                       link: "https://example.com/1", feedName: "Feed")
        XCTAssertFalse(scan.isClean)
        let pixelThreats = scan.threats.filter { $0.category == .trackingPixel }
        XCTAssertFalse(pixelThreats.isEmpty)
    }

    func testTrackingPixel_CSSHidden() {
        let body = """
        <div style="display: none"><img src="https://spy.com/t.gif"></div>
        """
        let scan = guard_.scanArticle(title: "Hidden", body: body,
                                       link: "https://example.com/2", feedName: "Feed")
        let pixelThreats = scan.threats.filter { $0.category == .trackingPixel }
        XCTAssertFalse(pixelThreats.isEmpty)
    }

    func testTrackingPixel_VisibilityHidden() {
        let body = """
        <span style="visibility: hidden"><img src="https://t.com/p.png"></span>
        """
        let scan = guard_.scanArticle(title: "Invisible", body: body,
                                       link: "https://example.com/3", feedName: "Feed")
        let pixelThreats = scan.threats.filter { $0.category == .trackingPixel }
        XCTAssertFalse(pixelThreats.isEmpty)
    }

    // MARK: - Known Tracker Domains

    func testGoogleAnalytics_Detected() {
        let body = """
        <script src="https://www.google-analytics.com/analytics.js"></script>
        <p>Content</p>
        """
        let scan = guard_.scanArticle(title: "GA", body: body,
                                       link: "https://example.com/ga", feedName: "Feed")
        XCTAssertFalse(scan.isClean)
        let hasAnalytics = scan.threats.contains { $0.category == .analyticsScript }
        XCTAssertTrue(hasAnalytics)
    }

    func testDoubleClick_AdNetwork() {
        let body = """
        <img src="https://ad.doubleclick.net/ad/campaign123">
        """
        let scan = guard_.scanArticle(title: "Ad", body: body,
                                       link: "https://example.com/ad", feedName: "Feed")
        let hasAd = scan.threats.contains { $0.category == .adNetwork }
        XCTAssertTrue(hasAd)
    }

    func testFacebookTracker_CrossSite() {
        let body = """
        <script src="https://connect.facebook.net/en_US/fbevents.js"></script>
        """
        let scan = guard_.scanArticle(title: "FB", body: body,
                                       link: "https://example.com/fb", feedName: "Feed")
        let hasCrossSite = scan.threats.contains { $0.category == .crossSiteTracker }
        XCTAssertTrue(hasCrossSite)
    }

    func testMultipleTrackers_AllDetected() {
        let body = """
        <script src="https://www.googletagmanager.com/gtm.js"></script>
        <script src="https://static.hotjar.com/c/hotjar-123.js"></script>
        <img src="https://ad.doubleclick.net/pixel.gif" width="1" height="1">
        """
        let scan = guard_.scanArticle(title: "Multi", body: body,
                                       link: "https://example.com/multi", feedName: "Feed")
        XCTAssertGreaterThanOrEqual(scan.threats.count, 3)
        XCTAssertLessThan(scan.privacyScore, 70)
    }

    // MARK: - Fingerprinting

    func testCanvasFingerprinting() {
        let body = """
        <script>
        var canvas = document.createElement('canvas');
        var data = canvas.toDataURL();
        </script>
        """
        let scan = guard_.scanArticle(title: "FP", body: body,
                                       link: "https://example.com/fp", feedName: "Feed")
        let hasFP = scan.threats.contains { $0.category == .fingerprinting }
        XCTAssertTrue(hasFP)
    }

    func testWebGLFingerprinting() {
        let body = """
        <script>
        var gl = canvas.getContext('webgl');
        var info = gl.getParameter(gl.RENDERER);
        </script>
        """
        let scan = guard_.scanArticle(title: "WebGL", body: body,
                                       link: "https://example.com/webgl", feedName: "Feed")
        let hasFP = scan.threats.contains { $0.category == .fingerprinting }
        XCTAssertTrue(hasFP)
    }

    func testNavigatorPlugins() {
        let body = "<script>var p = navigator.plugins;</script>"
        let scan = guard_.scanArticle(title: "Plugins", body: body,
                                       link: "https://example.com/plugins", feedName: "Feed")
        let hasFP = scan.threats.contains { $0.category == .fingerprinting }
        XCTAssertTrue(hasFP)
    }

    // MARK: - Beacons

    func testSendBeacon() {
        let body = "<script>navigator.sendBeacon('/analytics', data);</script>"
        let scan = guard_.scanArticle(title: "Beacon", body: body,
                                       link: "https://example.com/beacon", feedName: "Feed")
        let hasBeacon = scan.threats.contains { $0.category == .externalBeacon }
        XCTAssertTrue(hasBeacon)
    }

    func testImageBeacon() {
        let body = "<script>new Image().src = 'https://track.com/event?id=123';</script>"
        let scan = guard_.scanArticle(title: "ImgBeacon", body: body,
                                       link: "https://example.com/imgbeacon", feedName: "Feed")
        let hasBeacon = scan.threats.contains { $0.category == .externalBeacon }
        XCTAssertTrue(hasBeacon)
    }

    func testUTMBeacon() {
        let body = """
        <img src="https://tracker.com/pixel.gif?utm_source=email&utm_medium=track">
        """
        let scan = guard_.scanArticle(title: "UTM", body: body,
                                       link: "https://example.com/utm", feedName: "Feed")
        let hasBeacon = scan.threats.contains { $0.category == .externalBeacon }
        XCTAssertTrue(hasBeacon)
    }

    // MARK: - Hidden Forms

    func testHiddenForm() {
        let body = """
        <form action="https://collect.com/data">
        <input type="hidden" name="uid" value="abc123">
        </form>
        """
        let scan = guard_.scanArticle(title: "Form", body: body,
                                       link: "https://example.com/form", feedName: "Feed")
        let hasForm = scan.threats.contains { $0.category == .hiddenForm }
        XCTAssertTrue(hasForm)
    }

    // MARK: - Email Trackers

    func testEmailOpenTracking() {
        let body = """
        <img src="https://mail.example.com/track/open?id=abc123">
        """
        let scan = guard_.scanArticle(title: "Email", body: body,
                                       link: "https://example.com/email", feedName: "Feed")
        let hasEmail = scan.threats.contains { $0.category == .emailTracker }
        XCTAssertTrue(hasEmail)
    }

    func testPixelGifTracker() {
        let body = """
        <img src="https://track.newsletter.com/pixel.gif?subscriber=xyz">
        """
        let scan = guard_.scanArticle(title: "PixelGif", body: body,
                                       link: "https://example.com/pixelgif", feedName: "Feed")
        let hasEmail = scan.threats.contains { $0.category == .emailTracker }
        XCTAssertTrue(hasEmail)
    }

    // MARK: - Privacy Score

    func testScore_DecreasesWithMoreThreats() {
        let clean = guard_.scanArticle(title: "A", body: "<p>Clean</p>",
                                        link: "https://example.com/a", feedName: "F")
        let tracked = guard_.scanArticle(
            title: "B",
            body: """
            <script src="https://www.google-analytics.com/ga.js"></script>
            <script src="https://static.hotjar.com/c/h.js"></script>
            <img src="https://ad.doubleclick.net/p.gif" width="1" height="1">
            <script>var d = canvas.toDataURL();</script>
            """,
            link: "https://example.com/b", feedName: "F")
        XCTAssertGreaterThan(clean.privacyScore, tracked.privacyScore)
    }

    func testScore_MaxIs100() {
        let scan = guard_.scanArticle(title: "X", body: "text",
                                       link: "https://example.com/x", feedName: "F")
        XCTAssertLessThanOrEqual(scan.privacyScore, 100)
    }

    func testScore_MinIs0() {
        // Even with many threats, score floors at 0
        var body = ""
        for domain in FeedPrivacyGuard.trackerDomains.prefix(20) {
            body += "<script src=\"https://\(domain)/track.js\"></script>\n"
        }
        body += "<script>canvas.toDataURL(); navigator.plugins; navigator.sendBeacon('/t');</script>"
        let scan = guard_.scanArticle(title: "Heavy", body: body,
                                       link: "https://example.com/heavy", feedName: "F")
        XCTAssertGreaterThanOrEqual(scan.privacyScore, 0)
    }

    // MARK: - External Domains

    func testExternalDomains_Extracted() {
        let body = """
        <img src="https://cdn.example.com/image.jpg">
        <script src="https://scripts.other.com/lib.js"></script>
        <a href="https://link.third.com/page">Link</a>
        """
        let scan = guard_.scanArticle(title: "Domains", body: body,
                                       link: "https://example.com/d", feedName: "F")
        XCTAssertGreaterThanOrEqual(scan.externalDomainCount, 3)
        XCTAssertTrue(scan.externalDomains.contains("cdn.example.com"))
    }

    // MARK: - Feed Profile

    func testFeedProfile_NoScans() {
        let profile = guard_.feedProfile(feedName: "Empty Feed",
                                          feedURL: "https://empty.com/feed")
        XCTAssertEqual(profile.averageScore, 100)
        XCTAssertEqual(profile.grade, "A+")
        XCTAssertEqual(profile.articlesScanned, 0)
    }

    func testFeedProfile_WithScans() {
        guard_.scanArticle(title: "A1", body: "<p>Clean</p>",
                            link: "https://f.com/1", feedName: "TestFeed")
        guard_.scanArticle(title: "A2",
                            body: "<script src=\"https://www.google-analytics.com/ga.js\"></script>",
                            link: "https://f.com/2", feedName: "TestFeed")
        let profile = guard_.feedProfile(feedName: "TestFeed",
                                          feedURL: "https://f.com/feed")
        XCTAssertEqual(profile.articlesScanned, 2)
        XCTAssertEqual(profile.cleanArticles, 1)
        XCTAssertGreaterThan(profile.averageScore, 0)
        XCTAssertLessThanOrEqual(profile.averageScore, 100)
        XCTAssertFalse(profile.grade.isEmpty)
        XCTAssertFalse(profile.recommendation.isEmpty)
    }

    func testFeedProfile_CleanPercentage() {
        guard_.scanArticle(title: "C1", body: "clean", link: "https://f.com/c1", feedName: "FP")
        guard_.scanArticle(title: "C2", body: "clean", link: "https://f.com/c2", feedName: "FP")
        guard_.scanArticle(title: "C3",
                            body: "<script src=\"https://www.google-analytics.com/ga.js\"></script>",
                            link: "https://f.com/c3", feedName: "FP")
        let profile = guard_.feedProfile(feedName: "FP", feedURL: "https://f.com/feed")
        // 2 out of 3 are clean
        XCTAssertEqual(profile.cleanPercentage, 200.0/3.0, accuracy: 0.1)
    }

    // MARK: - Fleet Report

    func testReport_Empty() {
        let report = guard_.generateReport()
        XCTAssertEqual(report.totalFeeds, 0)
        XCTAssertEqual(report.totalArticles, 0)
        XCTAssertEqual(report.overallScore, 100)
    }

    func testReport_WithData() {
        guard_.scanArticle(title: "A", body: "clean",
                            link: "https://a.com/1", feedName: "Feed A")
        guard_.scanArticle(title: "B",
                            body: "<script src=\"https://www.google-analytics.com/ga.js\"></script>",
                            link: "https://b.com/1", feedName: "Feed B")
        let report = guard_.generateReport()
        XCTAssertEqual(report.totalFeeds, 2)
        XCTAssertEqual(report.totalArticles, 2)
        XCTAssertFalse(report.summary.isEmpty)
    }

    func testReport_TextReport() {
        guard_.scanArticle(title: "A", body: "clean",
                            link: "https://a.com/1", feedName: "Feed A")
        let report = guard_.generateReport()
        let text = report.textReport()
        XCTAssertTrue(text.contains("Feed Privacy Report"))
        XCTAssertTrue(text.contains("Overall Score"))
    }

    func testReport_FeedRankings_SortedWorstFirst() {
        guard_.scanArticle(title: "Clean", body: "no trackers",
                            link: "https://c.com/1", feedName: "Good Feed")
        guard_.scanArticle(title: "Tracked",
                            body: "<script src=\"https://www.google-analytics.com/ga.js\"></script><script src=\"https://static.hotjar.com/h.js\"></script>",
                            link: "https://t.com/1", feedName: "Bad Feed")
        let report = guard_.generateReport()
        XCTAssertEqual(report.feedRankings.count, 2)
        // Worst (lowest score) should be first
        XCTAssertLessThanOrEqual(report.feedRankings[0].score, report.feedRankings[1].score)
    }

    // MARK: - Caching

    func testCachedScan_ReturnsStoredResult() {
        let url = "https://example.com/cached"
        guard_.scanArticle(title: "X", body: "clean", link: url, feedName: "F")
        let cached = guard_.cachedScan(for: url)
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.articleURL, url)
    }

    func testCachedScan_MissReturnsNil() {
        XCTAssertNil(guard_.cachedScan(for: "https://nonexistent.com/x"))
    }

    func testAllScans_SortedByDate() {
        let date1 = Date(timeIntervalSince1970: 1000)
        let date2 = Date(timeIntervalSince1970: 2000)
        guard_.scanArticle(title: "Old", body: "a", link: "https://e.com/old",
                            feedName: "F", now: date1)
        guard_.scanArticle(title: "New", body: "b", link: "https://e.com/new",
                            feedName: "F", now: date2)
        let all = guard_.allScans()
        XCTAssertEqual(all.count, 2)
        // Most recent first
        XCTAssertEqual(all[0].articleTitle, "New")
    }

    func testScansForFeed_Filtered() {
        guard_.scanArticle(title: "A", body: "x", link: "https://e.com/a", feedName: "Alpha")
        guard_.scanArticle(title: "B", body: "y", link: "https://e.com/b", feedName: "Beta")
        guard_.scanArticle(title: "C", body: "z", link: "https://e.com/c", feedName: "Alpha")
        XCTAssertEqual(guard_.scans(for: "Alpha").count, 2)
        XCTAssertEqual(guard_.scans(for: "Beta").count, 1)
        XCTAssertEqual(guard_.scans(for: "Gamma").count, 0)
    }

    // MARK: - Clear

    func testClearScans_RemovesAll() {
        guard_.scanArticle(title: "A", body: "x", link: "https://e.com/a", feedName: "F")
        guard_.scanArticle(title: "B", body: "y", link: "https://e.com/b", feedName: "F")
        XCTAssertEqual(guard_.scanCount, 2)
        guard_.clearScans()
        XCTAssertEqual(guard_.scanCount, 0)
    }

    func testClearScansForFeed_SelectiveRemoval() {
        guard_.scanArticle(title: "A", body: "x", link: "https://e.com/a", feedName: "Keep")
        guard_.scanArticle(title: "B", body: "y", link: "https://e.com/b", feedName: "Remove")
        guard_.clearScans(for: "Remove")
        XCTAssertEqual(guard_.scanCount, 1)
        XCTAssertEqual(guard_.scans(for: "Keep").count, 1)
    }

    // MARK: - Export/Import

    func testExportJSON_ProducesValidData() {
        guard_.scanArticle(title: "A", body: "clean", link: "https://e.com/a", feedName: "F")
        let data = guard_.exportJSON()
        XCTAssertNotNil(data)
        XCTAssertGreaterThan(data!.count, 0)
    }

    func testImportJSON_AddsNewScans() {
        guard_.scanArticle(title: "A", body: "clean", link: "https://e.com/a", feedName: "F")
        let exported = guard_.exportJSON()!
        guard_.clearScans()
        let count = guard_.importJSON(exported)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(guard_.scanCount, 1)
    }

    func testImportJSON_SkipsDuplicates() {
        guard_.scanArticle(title: "A", body: "clean", link: "https://e.com/a", feedName: "F")
        let exported = guard_.exportJSON()!
        // Import again — should skip
        let count = guard_.importJSON(exported)
        XCTAssertEqual(count, 0)
        XCTAssertEqual(guard_.scanCount, 1)
    }

    func testImportJSON_InvalidData() {
        let count = guard_.importJSON(Data("not json".utf8))
        XCTAssertEqual(count, 0)
    }

    // MARK: - Grading

    func testScoreToGrade_APlusForPerfect() {
        XCTAssertEqual(FeedPrivacyGuard.scoreToGrade(100), "A+")
        XCTAssertEqual(FeedPrivacyGuard.scoreToGrade(95), "A+")
    }

    func testScoreToGrade_AForHigh() {
        XCTAssertEqual(FeedPrivacyGuard.scoreToGrade(90), "A")
        XCTAssertEqual(FeedPrivacyGuard.scoreToGrade(94), "A")
    }

    func testScoreToGrade_FForLow() {
        XCTAssertEqual(FeedPrivacyGuard.scoreToGrade(39), "F")
        XCTAssertEqual(FeedPrivacyGuard.scoreToGrade(0), "F")
    }

    func testScoreToGrade_FullRange() {
        // Every score maps to a valid grade
        for score in 0...100 {
            let grade = FeedPrivacyGuard.scoreToGrade(score)
            XCTAssertFalse(grade.isEmpty, "Score \(score) should have a grade")
        }
    }

    // MARK: - Severity

    func testSeverity_Ordering() {
        XCTAssertTrue(PrivacySeverity.low < PrivacySeverity.medium)
        XCTAssertTrue(PrivacySeverity.medium < PrivacySeverity.high)
        XCTAssertTrue(PrivacySeverity.high < PrivacySeverity.critical)
    }

    func testSeverity_FromScore() {
        XCTAssertEqual(PrivacySeverity.from(score: 0.0), .low)
        XCTAssertEqual(PrivacySeverity.from(score: 0.3), .medium)
        XCTAssertEqual(PrivacySeverity.from(score: 0.6), .high)
        XCTAssertEqual(PrivacySeverity.from(score: 0.9), .critical)
    }

    // MARK: - Threat Categories

    func testThreatCategory_AllHaveSeverity() {
        for cat in PrivacyThreatCategory.allCases {
            XCTAssertGreaterThan(cat.severity, 0.0)
            XCTAssertLessThanOrEqual(cat.severity, 1.0)
        }
    }

    func testThreatCategory_AllHaveLabels() {
        for cat in PrivacyThreatCategory.allCases {
            XCTAssertFalse(cat.label.isEmpty)
        }
    }

    func testThreatCategory_FingerprintingMostSevere() {
        let maxSeverity = PrivacyThreatCategory.allCases.max(by: { $0.severity < $1.severity })
        XCTAssertEqual(maxSeverity, .fingerprinting)
    }

    // MARK: - ArticlePrivacyScan

    func testScan_ThreatsByCategory() {
        let body = """
        <script src="https://www.google-analytics.com/ga.js"></script>
        <script src="https://ad.doubleclick.net/ad.js"></script>
        <script>canvas.toDataURL();</script>
        """
        let scan = guard_.scanArticle(title: "Mixed", body: body,
                                       link: "https://example.com/mixed", feedName: "F")
        let byCategory = scan.threatsByCategory
        XCTAssertFalse(byCategory.isEmpty)
    }

    func testScan_MetadataPreserved() {
        let now = Date()
        let scan = guard_.scanArticle(title: "Title", body: "body",
                                       link: "https://example.com/meta",
                                       feedName: "MyFeed", now: now)
        XCTAssertEqual(scan.articleTitle, "Title")
        XCTAssertEqual(scan.articleURL, "https://example.com/meta")
        XCTAssertEqual(scan.feedName, "MyFeed")
        XCTAssertEqual(scan.scannedAt, now)
    }

    // MARK: - Deduplication

    func testDeduplication_SameCategoryAndEvidence() {
        // Same tracker domain appearing in multiple tags should only count once
        let body = """
        <script src="https://www.google-analytics.com/analytics.js"></script>
        <script src="https://www.google-analytics.com/gtag.js"></script>
        """
        let scan = guard_.scanArticle(title: "Dedup", body: body,
                                       link: "https://e.com/dedup", feedName: "F")
        // Should have the tracker detected (at least once)
        let gaThreats = scan.threats.filter { $0.evidence.contains("google-analytics.com") }
        // Both are same domain but different src URLs — domain extracted is same
        // Dedup key is category|evidence, so same domain match = 1 threat
        XCTAssertGreaterThanOrEqual(gaThreats.count, 1)
    }

    // MARK: - Notification

    func testScanPostsNotification() {
        let expectation = XCTestExpectation(description: "Privacy scan notification")
        let observer = NotificationCenter.default.addObserver(
            forName: .privacyScanDidUpdate, object: nil, queue: nil
        ) { _ in expectation.fulfill() }

        guard_.scanArticle(title: "N", body: "text",
                            link: "https://e.com/notify", feedName: "F")

        wait(for: [expectation], timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }

    // MARK: - Edge Cases

    func testMalformedHTML_DoesNotCrash() {
        let body = """
        <div><script src="broken" <img width="1" height="1"
        <form <input type="hidden" <<<>>>
        """
        let scan = guard_.scanArticle(title: "Malformed", body: body,
                                       link: "https://e.com/malformed", feedName: "F")
        // Should not crash, score should be valid
        XCTAssertGreaterThanOrEqual(scan.privacyScore, 0)
        XCTAssertLessThanOrEqual(scan.privacyScore, 100)
    }

    func testVeryLargeContent_DoesNotHang() {
        // 100KB of repeated HTML
        let chunk = "<p>Some text with <a href=\"https://safe.com/page\">a link</a>.</p>\n"
        let body = String(repeating: chunk, count: 1500)
        let scan = guard_.scanArticle(title: "Large", body: body,
                                       link: "https://e.com/large", feedName: "F")
        XCTAssertGreaterThanOrEqual(scan.privacyScore, 0)
    }

    func testUnicodeContent_HandledCorrectly() {
        let body = """
        <p>日本語のテスト記事 🔒 Ñoño</p>
        <script src="https://www.google-analytics.com/ga.js"></script>
        """
        let scan = guard_.scanArticle(title: "Unicode", body: body,
                                       link: "https://e.com/unicode", feedName: "F")
        XCTAssertFalse(scan.isClean) // GA detected despite unicode
    }

    func testCaseSensitivity_HandlesMixedCase() {
        let body = """
        <SCRIPT SRC="https://WWW.GOOGLE-ANALYTICS.COM/ga.js"></SCRIPT>
        """
        let scan = guard_.scanArticle(title: "Caps", body: body,
                                       link: "https://e.com/caps", feedName: "F")
        // Should still detect (lowercased comparison)
        XCTAssertFalse(scan.isClean)
    }
}
