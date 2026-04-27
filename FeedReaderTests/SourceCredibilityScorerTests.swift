//
//  SourceCredibilityScorerTests.swift
//  FeedReaderTests
//
//  Tests for SourceCredibilityScorer — domain reputation, content
//  transparency, writing quality, source attribution, and composite scoring.
//

import XCTest
@testable import FeedReader

class SourceCredibilityScorerTests: XCTestCase {

    // MARK: - Helpers

    /// Build a well-sourced, transparent article body.
    private func wellWrittenBody() -> String {
        return """
        By Jane Smith, Senior Correspondent

        Published on April 15, 2026. Updated April 16, 2026.

        According to a report from the World Health Organization, global vaccination
        rates have improved significantly. The study published in The Lancet confirms
        that coverage in low-income countries rose by 12%. Data shows a correlation
        between investment and outcome. A spokesperson for UNICEF confirmed the findings.
        Research found that community outreach programs contributed the most.

        Correction: An earlier version of this article stated 15%; the correct figure is 12%.

        Sources say the trend is expected to continue through 2027. It is unclear whether
        funding levels will be sustained. The report states that further monitoring is needed.
        Reportedly, several governments have pledged additional support.

        https://who.int/report https://lancet.com/study https://unicef.org/data
        """
    }

    /// Build a low-quality, unsourced article body.
    private func lowQualityBody() -> String {
        return "Big pharma is hiding the truth. Wake up people."
    }

    // MARK: - Domain Extraction

    func testExtractDomain_standardURL() {
        let domain = SourceCredibilityScorer.extractDomain(from: "https://www.nytimes.com/2026/04/article")
        XCTAssertEqual(domain, "nytimes.com")
    }

    func testExtractDomain_noWWW() {
        let domain = SourceCredibilityScorer.extractDomain(from: "https://reuters.com/world/story")
        XCTAssertEqual(domain, "reuters.com")
    }

    func testExtractDomain_fallbackParsing() {
        let domain = SourceCredibilityScorer.extractDomain(from: "not-a-valid-url")
        XCTAssertEqual(domain, "not-a-valid-url")
    }

    func testExtractDomain_subdomainStripsWWW() {
        let domain = SourceCredibilityScorer.extractDomain(from: "https://www.bbc.co.uk/news")
        XCTAssertEqual(domain, "bbc.co.uk")
    }

    func testExtractDomain_httpScheme() {
        let domain = SourceCredibilityScorer.extractDomain(from: "http://apnews.com/article/123")
        XCTAssertEqual(domain, "apnews.com")
    }

    // MARK: - Quick Check

    func testQuickCheck_highCredibilityDomain() {
        let tier = SourceCredibilityScorer.quickCheck(url: "https://reuters.com/story")
        XCTAssertEqual(tier, .high)
    }

    func testQuickCheck_lowCredibilityDomain() {
        let tier = SourceCredibilityScorer.quickCheck(url: "https://infowars.com/story")
        XCTAssertEqual(tier, .low)
    }

    func testQuickCheck_unknownDomain() {
        let tier = SourceCredibilityScorer.quickCheck(url: "https://randomsite12345.com/article")
        // Unknown domain baseline is 50 → moderate or mixed
        XCTAssertTrue(tier == .moderate || tier == .mixed)
    }

    // MARK: - CredibilityTier

    func testTierFromScore_high() {
        XCTAssertEqual(CredibilityTier.from(score: 80), .high)
        XCTAssertEqual(CredibilityTier.from(score: 100), .high)
    }

    func testTierFromScore_moderate() {
        XCTAssertEqual(CredibilityTier.from(score: 60), .moderate)
        XCTAssertEqual(CredibilityTier.from(score: 79), .moderate)
    }

    func testTierFromScore_mixed() {
        XCTAssertEqual(CredibilityTier.from(score: 40), .mixed)
        XCTAssertEqual(CredibilityTier.from(score: 59), .mixed)
    }

    func testTierFromScore_low() {
        XCTAssertEqual(CredibilityTier.from(score: 0), .low)
        XCTAssertEqual(CredibilityTier.from(score: 39), .low)
    }

    func testTierFromScore_negativeReturnsUnknown() {
        XCTAssertEqual(CredibilityTier.from(score: -5), .unknown)
    }

    func testTierEmoji() {
        XCTAssertEqual(CredibilityTier.high.emoji, "🟢")
        XCTAssertEqual(CredibilityTier.low.emoji, "🔴")
        XCTAssertEqual(CredibilityTier.unknown.emoji, "⚪")
    }

    // MARK: - Full Evaluate — High Credibility Source

    func testEvaluate_highCredibilitySource() {
        let report = SourceCredibilityScorer.evaluate(
            url: "https://www.reuters.com/article/global-health",
            title: "Global Vaccination Rates Rise Steadily in 2026",
            body: wellWrittenBody()
        )

        XCTAssertEqual(report.domain, "reuters.com")
        XCTAssertGreaterThanOrEqual(report.overallScore, 70,
            "Reuters with well-written body should score ≥70")
        XCTAssertTrue(report.tier == .high || report.tier == .moderate)

        // Should have 4 scored dimensions
        XCTAssertEqual(report.dimensions.count, 4)

        // Domain reputation should be high
        let domainDim = report.dimensions.first { $0.name == "Domain Reputation" }
        XCTAssertNotNil(domainDim)
        XCTAssertEqual(domainDim?.score, 90)
        XCTAssertEqual(domainDim?.weight, 0.35)
    }

    func testEvaluate_dimensionWeightsSumToOne() {
        let report = SourceCredibilityScorer.evaluate(
            url: "https://nytimes.com/article",
            title: "Test Article",
            body: wellWrittenBody()
        )
        let totalWeight = report.dimensions.reduce(0.0) { $0 + $1.weight }
        XCTAssertEqual(totalWeight, 1.0, accuracy: 0.001)
    }

    // MARK: - Full Evaluate — Low Credibility Source

    func testEvaluate_lowCredibilitySource() {
        let report = SourceCredibilityScorer.evaluate(
            url: "https://infowars.com/breaking",
            title: "SHOCKING BOMBSHELL EXPOSED!!!",
            body: lowQualityBody()
        )

        XCTAssertEqual(report.domain, "infowars.com")
        XCTAssertLessThanOrEqual(report.overallScore, 30,
            "Infowars with clickbait title and no sources should score ≤30")
        XCTAssertEqual(report.tier, .low)

        // Should flag unreliable source
        let unreliableFlag = report.flags.first { $0.indicator == "Unreliable Source" }
        XCTAssertNotNil(unreliableFlag)
        XCTAssertEqual(unreliableFlag?.impact, .critical)
    }

    // MARK: - Writing Quality — Clickbait Detection

    func testEvaluate_clickbaitTitle() {
        let report = SourceCredibilityScorer.evaluate(
            url: "https://example.com/article",
            title: "You Won't Believe What Happens Next - Mind-Blowing!",
            body: wellWrittenBody()
        )

        let clickbaitFlag = report.flags.first { $0.indicator == "Clickbait Title" }
        XCTAssertNotNil(clickbaitFlag, "Should detect clickbait patterns")
        XCTAssertEqual(clickbaitFlag?.impact, .negative)
    }

    func testEvaluate_excessiveCapsInTitle() {
        let report = SourceCredibilityScorer.evaluate(
            url: "https://example.com/article",
            title: "THIS ARTICLE WILL CHANGE YOUR LIFE FOREVER",
            body: wellWrittenBody()
        )

        let capsFlag = report.flags.first { $0.indicator == "Excessive Capitalization" }
        XCTAssertNotNil(capsFlag, "Should detect excessive ALL CAPS")
    }

    func testEvaluate_excessivePunctuation() {
        let report = SourceCredibilityScorer.evaluate(
            url: "https://example.com/article",
            title: "Is This Real?? Breaking News!!",
            body: wellWrittenBody()
        )

        let punctFlag = report.flags.first { $0.indicator == "Excessive Punctuation" }
        XCTAssertNotNil(punctFlag, "Should detect excessive punctuation")
    }

    func testEvaluate_shortArticleFlagged() {
        let report = SourceCredibilityScorer.evaluate(
            url: "https://example.com/article",
            title: "Brief Update",
            body: "This is very short."
        )

        let shortFlag = report.flags.first { $0.indicator == "Very Short Article" }
        XCTAssertNotNil(shortFlag, "Should flag articles under 100 words")
        XCTAssertEqual(shortFlag?.impact, .negative)
    }

    // MARK: - Content Transparency

    func testEvaluate_authorAttribution() {
        let bodyWithAuthor = "By John Doe\n\nThe economy grew 3% this quarter."
        let bodyWithoutAuthor = "The economy grew 3% this quarter."

        let withAuthor = SourceCredibilityScorer.evaluate(
            url: "https://example.com/a", title: "Economy Update", body: bodyWithAuthor
        )
        let withoutAuthor = SourceCredibilityScorer.evaluate(
            url: "https://example.com/b", title: "Economy Update", body: bodyWithoutAuthor
        )

        let authorFlag = withAuthor.flags.first { $0.indicator == "Author Attributed" }
        XCTAssertNotNil(authorFlag)

        let noAuthorFlag = withoutAuthor.flags.first { $0.indicator == "No Author Attribution" }
        XCTAssertNotNil(noAuthorFlag)
    }

    func testEvaluate_correctionNotice() {
        let body = """
        Correction: A previous version of this article misstated the date.
        The event occurred on March 5, not March 15.
        By Jane Smith. According to officials, the project is on track. Sources say
        construction will finish by December. Data shows progress is ahead of schedule.
        """
        let report = SourceCredibilityScorer.evaluate(
            url: "https://example.com/a", title: "Project Update", body: body
        )

        let correctionFlag = report.flags.first { $0.indicator == "Correction Notice Present" }
        XCTAssertNotNil(correctionFlag)
        XCTAssertEqual(correctionFlag?.impact, .positive)
    }

    func testEvaluate_disclosureDetected() {
        let body = """
        By Staff Writer. Disclosure: The author holds shares in the company discussed.
        According to the annual report, revenue increased 20%. Data shows continued growth.
        Sources say the trend will continue. Research found strong market demand.
        """
        let report = SourceCredibilityScorer.evaluate(
            url: "https://example.com/a", title: "Company Review", body: body
        )

        let disclosureFlag = report.flags.first { $0.indicator == "Disclosure Present" }
        XCTAssertNotNil(disclosureFlag)
        XCTAssertEqual(disclosureFlag?.impact, .neutral)
    }

    // MARK: - Source Attribution

    func testEvaluate_wellSourcedArticle() {
        let report = SourceCredibilityScorer.evaluate(
            url: "https://example.com/article",
            title: "Health Report",
            body: wellWrittenBody()
        )

        let sourcedFlag = report.flags.first { $0.indicator == "Well-Sourced" }
        XCTAssertNotNil(sourcedFlag, "Body with 3+ sourcing patterns should be flagged well-sourced")
        XCTAssertEqual(sourcedFlag?.impact, .positive)
    }

    func testEvaluate_minimalAttribution() {
        let report = SourceCredibilityScorer.evaluate(
            url: "https://example.com/article",
            title: "Opinion Piece",
            body: "This is clearly wrong and everyone knows it. The system is broken beyond repair."
        )

        let minimalFlag = report.flags.first { $0.indicator == "Minimal Attribution" }
        XCTAssertNotNil(minimalFlag, "Body without sourcing language should flag minimal attribution")
        XCTAssertEqual(minimalFlag?.impact, .negative)
    }

    func testEvaluate_hedgingLanguage() {
        let body = """
        By Reporter. According to unnamed sources, the deal is allegedly worth billions.
        Reportedly, the company plans to expand. It is unclear whether regulators will approve.
        Data shows market volatility. Sources say timing is critical.
        """
        let report = SourceCredibilityScorer.evaluate(
            url: "https://example.com/a", title: "Deal Report", body: body
        )

        let hedgeFlag = report.flags.first { $0.indicator == "Appropriate Hedging" }
        XCTAssertNotNil(hedgeFlag, "Body with hedging language should be flagged positively")
    }

    // MARK: - Domain Types

    func testEvaluate_govDomainBonus() {
        let report = SourceCredibilityScorer.evaluate(
            url: "https://cdc.gov/health/report",
            title: "CDC Health Advisory",
            body: wellWrittenBody()
        )

        let institutionalFlag = report.flags.first { $0.indicator == "Institutional Domain" }
        XCTAssertNotNil(institutionalFlag)
        XCTAssertEqual(institutionalFlag?.impact, .positive)
        XCTAssertGreaterThanOrEqual(report.overallScore, 60)
    }

    func testEvaluate_eduDomainBonus() {
        let report = SourceCredibilityScorer.evaluate(
            url: "https://news.mit.edu/research",
            title: "MIT Research Breakthrough",
            body: wellWrittenBody()
        )

        let institutionalFlag = report.flags.first { $0.indicator == "Institutional Domain" }
        XCTAssertNotNil(institutionalFlag)
    }

    func testEvaluate_suspiciousDomain() {
        let report = SourceCredibilityScorer.evaluate(
            url: "https://cnn-breaking-news24.com/story",
            title: "Normal Title",
            body: wellWrittenBody()
        )

        let suspiciousFlag = report.flags.first { $0.indicator == "Suspicious Domain Pattern" }
        XCTAssertNotNil(suspiciousFlag, "Domain mimicking CNN should be flagged suspicious")
        XCTAssertEqual(suspiciousFlag?.impact, .negative)
    }

    // MARK: - Score Clamping

    func testEvaluate_scoreClampedTo0_100() {
        // Even worst-case scenarios should stay in 0-100
        let report = SourceCredibilityScorer.evaluate(
            url: "https://infowars.com/story",
            title: "SHOCKING!!! YOU WON'T BELIEVE THIS BOMBSHELL!!!",
            body: "Lies."
        )
        XCTAssertGreaterThanOrEqual(report.overallScore, 0)
        XCTAssertLessThanOrEqual(report.overallScore, 100)

        // All dimensions also clamped
        for dim in report.dimensions {
            XCTAssertGreaterThanOrEqual(dim.score, 0)
            XCTAssertLessThanOrEqual(dim.score, 100)
        }
    }

    // MARK: - Summary

    func testEvaluate_summaryContainsDomainAndTier() {
        let report = SourceCredibilityScorer.evaluate(
            url: "https://bbc.com/news/article",
            title: "World News Update",
            body: wellWrittenBody()
        )

        XCTAssertTrue(report.summary.contains("bbc.com"))
        XCTAssertTrue(report.summary.contains(report.tier.rawValue))
    }

    func testEvaluate_summaryMentionsCriticalConcerns() {
        let report = SourceCredibilityScorer.evaluate(
            url: "https://infowars.com/story",
            title: "Normal Title",
            body: wellWrittenBody()
        )

        // Has critical flag (Unreliable Source) → summary should mention it
        let hasCritical = report.flags.contains { $0.impact == .critical }
        if hasCritical {
            XCTAssertTrue(report.summary.contains("critical concern"))
        }
    }

    // MARK: - Report Codable Roundtrip

    func testCredibilityReport_codableRoundtrip() throws {
        let report = SourceCredibilityScorer.evaluate(
            url: "https://nytimes.com/article",
            title: "Test Article",
            body: wellWrittenBody()
        )

        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(CredibilityReport.self, from: data)

        XCTAssertEqual(decoded.domain, report.domain)
        XCTAssertEqual(decoded.overallScore, report.overallScore)
        XCTAssertEqual(decoded.tier, report.tier)
        XCTAssertEqual(decoded.dimensions.count, report.dimensions.count)
        XCTAssertEqual(decoded.flags.count, report.flags.count)
        XCTAssertEqual(decoded.summary, report.summary)
    }

    // MARK: - Moderate Credibility Domains

    func testEvaluate_moderateCredibilityDomain() {
        let report = SourceCredibilityScorer.evaluate(
            url: "https://cnn.com/politics/story",
            title: "Political Analysis",
            body: wellWrittenBody()
        )

        let knownFlag = report.flags.first { $0.indicator == "Known Source" }
        XCTAssertNotNil(knownFlag, "CNN should be flagged as a known source")
        XCTAssertEqual(knownFlag?.impact, .neutral)
    }

    // MARK: - CredibilityImpact

    func testCredibilityImpact_emoji() {
        XCTAssertEqual(CredibilityImpact.positive.emoji, "✅")
        XCTAssertEqual(CredibilityImpact.neutral.emoji, "ℹ️")
        XCTAssertEqual(CredibilityImpact.negative.emoji, "⚠️")
        XCTAssertEqual(CredibilityImpact.critical.emoji, "🚨")
    }

    // MARK: - Edge Cases

    func testEvaluate_emptyBody() {
        let report = SourceCredibilityScorer.evaluate(
            url: "https://example.com/a",
            title: "Title",
            body: ""
        )
        XCTAssertGreaterThanOrEqual(report.overallScore, 0)
        XCTAssertLessThanOrEqual(report.overallScore, 100)
    }

    func testEvaluate_emptyTitle() {
        let report = SourceCredibilityScorer.evaluate(
            url: "https://reuters.com/story",
            title: "",
            body: wellWrittenBody()
        )
        // Reuters domain should still score well even with empty title
        XCTAssertGreaterThanOrEqual(report.overallScore, 60)
    }

    func testEvaluate_checkedAtIsRecent() {
        let before = Date()
        let report = SourceCredibilityScorer.evaluate(
            url: "https://example.com/a",
            title: "Title",
            body: "Body text here."
        )
        let after = Date()
        XCTAssertGreaterThanOrEqual(report.checkedAt, before)
        XCTAssertLessThanOrEqual(report.checkedAt, after)
    }
}
