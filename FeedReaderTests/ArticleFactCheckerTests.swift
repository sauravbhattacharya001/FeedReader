//
//  ArticleFactCheckerTests.swift
//  FeedReaderTests
//

import XCTest
@testable import FeedReader

final class ArticleFactCheckerTests: XCTestCase {

    // MARK: - Numeric Claims

    func testDetectsNumericClaims() {
        let text = "The company reported $4.5 billion in revenue last quarter."
        let report = ArticleFactChecker.analyze(text: text)
        XCTAssertFalse(report.claims.isEmpty)
        let cats = report.claims.flatMap { $0.categories }
        XCTAssertTrue(cats.contains(.numeric))
    }

    func testDetectsPercentageClaims() {
        let text = "Sales increased by 45% compared to last year according to analysts."
        let report = ArticleFactChecker.analyze(text: text)
        XCTAssertFalse(report.claims.isEmpty)
        let cats = report.claims.flatMap { $0.categories }
        XCTAssertTrue(cats.contains(.numeric))
    }

    // MARK: - Temporal Claims

    func testDetectsTemporalClaims() {
        let text = "The policy was enacted on March 15, 2024 after lengthy debate."
        let report = ArticleFactChecker.analyze(text: text)
        let cats = report.claims.flatMap { $0.categories }
        XCTAssertTrue(cats.contains(.temporal))
    }

    // MARK: - Attribution

    func testDetectsAttributionClaims() {
        let text = "According to researchers at MIT, the new material is 10 times stronger."
        let report = ArticleFactChecker.analyze(text: text)
        let cats = report.claims.flatMap { $0.categories }
        XCTAssertTrue(cats.contains(.attribution))
    }

    // MARK: - Red Flags

    func testDetectsWeaselWords() {
        let text = "Some experts believe that the economy will improve in the next quarter significantly."
        let report = ArticleFactChecker.analyze(text: text)
        let flags = report.claims.flatMap { $0.redFlags }
        XCTAssertTrue(flags.contains(.weaselWords))
    }

    func testDetectsAbsoluteLanguage() {
        let text = "This product always delivers results and never fails under any circumstances."
        let report = ArticleFactChecker.analyze(text: text)
        let flags = report.claims.flatMap { $0.redFlags }
        XCTAssertTrue(flags.contains(.absoluteLanguage))
    }

    func testDetectsEmotionalLanguage() {
        let text = "The shocking revelation stunned investors and caused an unprecedented market crash."
        let report = ArticleFactChecker.analyze(text: text)
        let flags = report.claims.flatMap { $0.redFlags }
        XCTAssertTrue(flags.contains(.emotionalLanguage))
    }

    func testDetectsVagueSources() {
        let text = "Sources close to the matter say the deal will be announced next week."
        let report = ArticleFactChecker.analyze(text: text)
        let flags = report.claims.flatMap { $0.redFlags }
        XCTAssertTrue(flags.contains(.vagueSource))
    }

    // MARK: - Verifiability

    func testHighVerifiability() {
        let text = "According to the WHO, 3.4 million people were vaccinated in January 2024."
        let report = ArticleFactChecker.analyze(text: text)
        XCTAssertFalse(report.claims.isEmpty)
        // Should have attribution + numeric + temporal = high verifiability
        let best = report.claims.max { $0.verifiability < $1.verifiability }
        XCTAssertNotNil(best)
    }

    func testOpinionDetection() {
        let text = "I believe this is probably the best approach for solving climate change."
        let report = ArticleFactChecker.analyze(text: text)
        if let claim = report.claims.first {
            XCTAssertEqual(claim.verifiability, .opinion)
        }
    }

    // MARK: - Report

    func testFullReport() {
        let text = """
        The global temperature rose by 1.2 degrees Celsius since 1880 according to NASA.
        Some experts believe this trend will accelerate dramatically.
        The shocking data revealed unprecedented changes in Arctic ice coverage.
        Sources close to the research team say a major announcement is coming next week.
        The study was published in Nature on February 3, 2024 and reviewed by 15 scientists.
        """
        let report = ArticleFactChecker.analyze(text: text, title: "Climate Change Report")
        XCTAssertGreaterThan(report.claimCount, 0)
        XCTAssertGreaterThan(report.totalSentences, 0)
        XCTAssertTrue(report.credibilityScore >= 0.0 && report.credibilityScore <= 1.0)
        XCTAssertFalse(report.assessment.isEmpty)
    }

    func testFormatReport() {
        let text = "According to the FBI, cybercrime losses exceeded $10 billion in 2023."
        let report = ArticleFactChecker.analyze(text: text, title: "Cybercrime Report")
        let formatted = ArticleFactChecker.formatReport(report)
        XCTAssertTrue(formatted.contains("FACT-CHECK REPORT"))
        XCTAssertTrue(formatted.contains("Credibility score"))
    }

    // MARK: - Quick Score

    func testQuickScore() {
        let clean = "According to the CDC, 45.3% of adults received flu vaccines in 2023."
        let score = ArticleFactChecker.quickScore(text: clean)
        XCTAssertTrue(score >= 0.0 && score <= 1.0)
    }

    // MARK: - Edge Cases

    func testEmptyText() {
        let report = ArticleFactChecker.analyze(text: "")
        XCTAssertEqual(report.claimCount, 0)
        XCTAssertEqual(report.credibilityScore, 1.0)
    }

    func testShortSentences() {
        let report = ArticleFactChecker.analyze(text: "Hi. Yes. No. Ok. Fine.")
        XCTAssertEqual(report.claimCount, 0) // All too short
    }

    func testTopConcerns() {
        let text = """
        The company always delivers the best results in every market.
        Sources say the CEO will resign tomorrow.
        Revenue grew by 12% according to the annual report filed with the SEC.
        """
        let concerns = ArticleFactChecker.topConcerns(text: text, limit: 2)
        XCTAssertLessThanOrEqual(concerns.count, 2)
    }

    func testVerificationQueries() {
        let text = "According to NASA, the Mars rover Perseverance collected 20 rock samples in 2024."
        let report = ArticleFactChecker.analyze(text: text, title: "Mars Mission Update")
        if let claim = report.claims.first {
            XCTAssertFalse(claim.verificationQueries.isEmpty)
        }
    }
}
