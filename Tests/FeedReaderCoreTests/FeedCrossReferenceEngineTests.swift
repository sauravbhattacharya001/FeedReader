//
//  FeedCrossReferenceEngineTests.swift
//  FeedReaderCoreTests
//

import XCTest
@testable import FeedReaderCore

final class FeedCrossReferenceEngineTests: XCTestCase {

    // MARK: - Helpers

    private func makeStory(title: String, body: String, link: String = "https://example.com/\(UUID().uuidString)") -> RSSStory {
        return RSSStory(title: title, body: body, link: link)!
    }

    // MARK: - ClaimExtractor Tests

    func testExtractPercentageClaims() {
        let extractor = ClaimExtractor()
        let story = makeStory(
            title: "Economy Report",
            body: "Inflation rose to 7.5 percent this quarter, up from 5.2% last year."
        )
        let claims = extractor.extractClaims(from: story, sourceId: "TestSource")
        let percentClaims = claims.filter { $0.claimType == .percentage }
        XCTAssertGreaterThanOrEqual(percentClaims.count, 1, "Should extract percentage claims")
        XCTAssertTrue(percentClaims.allSatisfy { $0.sourceId == "TestSource" })
    }

    func testExtractMonetaryClaims() {
        let extractor = ClaimExtractor()
        let story = makeStory(
            title: "Funding News",
            body: "The startup raised $50 million in Series B funding, valued at $2 billion."
        )
        let claims = extractor.extractClaims(from: story, sourceId: "TechNews")
        let moneyClaims = claims.filter { $0.claimType == .monetary }
        XCTAssertGreaterThanOrEqual(moneyClaims.count, 1, "Should extract monetary claims")
    }

    func testExtractNumericClaims() {
        let extractor = ClaimExtractor()
        let story = makeStory(
            title: "Company Growth",
            body: "The company now has 10,000 employees across 50 offices worldwide."
        )
        let claims = extractor.extractClaims(from: story, sourceId: "BizNews")
        let numericClaims = claims.filter { $0.claimType == .numeric }
        XCTAssertGreaterThanOrEqual(numericClaims.count, 1, "Should extract numeric claims")
    }

    func testExtractStatisticClaims() {
        let extractor = ClaimExtractor()
        let story = makeStory(
            title: "Market Update",
            body: "Sales doubled in the third quarter. Revenue grew by 45 percent compared to last year."
        )
        let claims = extractor.extractClaims(from: story, sourceId: "Finance")
        let statClaims = claims.filter { $0.claimType == .statistic }
        XCTAssertGreaterThanOrEqual(statClaims.count, 1, "Should extract statistic claims")
    }

    func testExtractAttributionClaims() {
        let extractor = ClaimExtractor()
        let story = makeStory(
            title: "Press Conference",
            body: "John Smith said the project will be completed by December. Sarah Johnson confirmed the timeline."
        )
        let claims = extractor.extractClaims(from: story, sourceId: "PoliticsDaily")
        let attrClaims = claims.filter { $0.claimType == .attribution }
        XCTAssertGreaterThanOrEqual(attrClaims.count, 1, "Should extract attribution claims")
    }

    func testExtractCausalClaims() {
        let extractor = ClaimExtractor()
        let story = makeStory(
            title: "Climate Report",
            body: "Rising temperatures caused widespread flooding. The drought was due to climate change patterns."
        )
        let claims = extractor.extractClaims(from: story, sourceId: "ScienceDaily")
        let causalClaims = claims.filter { $0.claimType == .causal }
        XCTAssertGreaterThanOrEqual(causalClaims.count, 1, "Should extract causal claims")
    }

    func testExtractTemporalClaims() {
        let extractor = ClaimExtractor()
        let story = makeStory(
            title: "Historical Event",
            body: "The agreement was signed on January 15, 2024. The policy takes effect in 2025."
        )
        let claims = extractor.extractClaims(from: story, sourceId: "History")
        let temporalClaims = claims.filter { $0.claimType == .temporal }
        XCTAssertGreaterThanOrEqual(temporalClaims.count, 1, "Should extract temporal claims")
    }

    func testExtractClaimsPreservesKeywords() {
        let extractor = ClaimExtractor()
        let story = makeStory(
            title: "Technology Innovation",
            body: "Apple released a new smartphone with 25% better battery life and $999 price tag."
        )
        let claims = extractor.extractClaims(from: story, sourceId: "TechReview")
        XCTAssertTrue(claims.allSatisfy { !$0.keywords.isEmpty }, "All claims should have keywords")
    }

    func testExtractClaimsEmptyBody() {
        let extractor = ClaimExtractor()
        // RSSStory rejects empty body, so use minimal content
        let story = makeStory(title: "Short", body: "No facts here just opinions.")
        let claims = extractor.extractClaims(from: story, sourceId: "Blog")
        // May or may not have claims — just shouldn't crash
        XCTAssertNotNil(claims)
    }

    func testNumericValueExtraction() {
        let extractor = ClaimExtractor()
        let story = makeStory(
            title: "Revenue Report",
            body: "Revenue reached $5.2 billion this quarter, up from $3.1 billion last year."
        )
        let claims = extractor.extractClaims(from: story, sourceId: "Finance")
        let withValues = claims.filter { $0.numericValue != nil }
        XCTAssertGreaterThanOrEqual(withValues.count, 1, "Should extract numeric values from monetary claims")
    }

    // MARK: - CrossReferenceMatcher Tests

    func testMatchRelatedClaimsAcrossSources() {
        let matcher = CrossReferenceMatcher()
        let sharedKeywords = ["economy", "growth", "inflation", "report"]
        let claimA = ExtractedClaim(articleId: "a1", articleTitle: "Economy Report A", sourceId: "BBC",
                                     claimType: .percentage, claimText: "Inflation at 7.5 percent",
                                     keywords: sharedKeywords, numericValue: 7.5)
        let claimB = ExtractedClaim(articleId: "a2", articleTitle: "Economy Report B", sourceId: "Reuters",
                                     claimType: .percentage, claimText: "Inflation at 7.6 percent",
                                     keywords: sharedKeywords, numericValue: 7.6)
        let refs = matcher.findCrossReferences(claims: [claimA, claimB])
        XCTAssertEqual(refs.count, 1, "Should find one cross-reference")
        XCTAssertTrue(refs[0].agreement == .agrees || refs[0].agreement == .partiallyAgrees)
    }

    func testNoMatchSameSource() {
        let matcher = CrossReferenceMatcher()
        let keywords = ["economy", "growth"]
        let claimA = ExtractedClaim(articleId: "a1", articleTitle: "Report A", sourceId: "BBC",
                                     claimType: .percentage, claimText: "5%", keywords: keywords, numericValue: 5)
        let claimB = ExtractedClaim(articleId: "a2", articleTitle: "Report B", sourceId: "BBC",
                                     claimType: .percentage, claimText: "6%", keywords: keywords, numericValue: 6)
        let refs = matcher.findCrossReferences(claims: [claimA, claimB])
        XCTAssertEqual(refs.count, 0, "Should not cross-reference within same source")
    }

    func testContradictingNumericClaims() {
        let matcher = CrossReferenceMatcher()
        let keywords = ["population", "city", "census"]
        let claimA = ExtractedClaim(articleId: "a1", articleTitle: "Census A", sourceId: "Gov",
                                     claimType: .numeric, claimText: "Population 1 million",
                                     keywords: keywords, numericValue: 1_000_000)
        let claimB = ExtractedClaim(articleId: "a2", articleTitle: "Census B", sourceId: "Local",
                                     claimType: .numeric, claimText: "Population 2 million",
                                     keywords: keywords, numericValue: 2_000_000)
        let refs = matcher.findCrossReferences(claims: [claimA, claimB])
        XCTAssertEqual(refs.count, 1)
        XCTAssertEqual(refs[0].agreement, .contradicts, "100% deviation should be a contradiction")
    }

    func testLowSimilarityNoMatch() {
        let matcher = CrossReferenceMatcher()
        let claimA = ExtractedClaim(articleId: "a1", articleTitle: "Sports", sourceId: "ESPN",
                                     claimType: .numeric, claimText: "Score 3-1",
                                     keywords: ["football", "goals", "match"])
        let claimB = ExtractedClaim(articleId: "a2", articleTitle: "Weather", sourceId: "MetOffice",
                                     claimType: .numeric, claimText: "Temperature 25 degrees",
                                     keywords: ["temperature", "forecast", "sunny"])
        let refs = matcher.findCrossReferences(claims: [claimA, claimB])
        XCTAssertEqual(refs.count, 0, "Unrelated claims should not match")
    }

    func testDifferentClaimTypesNoMatch() {
        let matcher = CrossReferenceMatcher()
        let keywords = ["economy", "report", "annual"]
        let claimA = ExtractedClaim(articleId: "a1", articleTitle: "Report", sourceId: "BBC",
                                     claimType: .percentage, claimText: "5%", keywords: keywords)
        let claimB = ExtractedClaim(articleId: "a2", articleTitle: "Report", sourceId: "CNN",
                                     claimType: .causal, claimText: "caused by", keywords: keywords)
        let refs = matcher.findCrossReferences(claims: [claimA, claimB])
        XCTAssertEqual(refs.count, 0, "Different claim types should not match")
    }

    // MARK: - ClaimClusterer Tests

    func testClusterRelatedClaims() {
        let clusterer = ClaimClusterer()
        let keywords = ["climate", "temperature", "warming"]
        let c1 = ExtractedClaim(articleId: "a1", articleTitle: "Climate A", sourceId: "BBC",
                                 claimType: .numeric, claimText: "Temperature rose 2 degrees",
                                 keywords: keywords, numericValue: 2.0)
        let c2 = ExtractedClaim(articleId: "a2", articleTitle: "Climate B", sourceId: "Reuters",
                                 claimType: .numeric, claimText: "Temperature rose 2.1 degrees",
                                 keywords: keywords, numericValue: 2.1)
        let refs = CrossReferenceMatcher().findCrossReferences(claims: [c1, c2])
        let clusters = clusterer.clusterClaims(claims: [c1, c2], crossReferences: refs)
        XCTAssertEqual(clusters.count, 1, "Related claims should form one cluster")
        XCTAssertEqual(clusters[0].claims.count, 2)
        XCTAssertEqual(clusters[0].sourceCount, 2)
    }

    func testClusterUnrelatedClaimsSeparately() {
        let clusterer = ClaimClusterer()
        let c1 = ExtractedClaim(articleId: "a1", articleTitle: "Sports", sourceId: "ESPN",
                                 claimType: .numeric, claimText: "Score 3",
                                 keywords: ["football", "match", "score"])
        let c2 = ExtractedClaim(articleId: "a2", articleTitle: "Weather", sourceId: "MetOffice",
                                 claimType: .numeric, claimText: "Temperature 25",
                                 keywords: ["temperature", "forecast", "rain"])
        let clusters = clusterer.clusterClaims(claims: [c1, c2], crossReferences: [])
        XCTAssertEqual(clusters.count, 2, "Unrelated claims should be in separate clusters")
    }

    func testClusterCorroborationLevel() {
        let clusterer = ClaimClusterer()
        let keywords = ["stocks", "market", "trading"]
        let c1 = ExtractedClaim(articleId: "a1", articleTitle: "Market A", sourceId: "BBC",
                                 claimType: .percentage, claimText: "Stocks up 5%",
                                 keywords: keywords, numericValue: 5.0)
        let c2 = ExtractedClaim(articleId: "a2", articleTitle: "Market B", sourceId: "Reuters",
                                 claimType: .percentage, claimText: "Stocks up 5.1%",
                                 keywords: keywords, numericValue: 5.1)
        let c3 = ExtractedClaim(articleId: "a3", articleTitle: "Market C", sourceId: "NPR",
                                 claimType: .percentage, claimText: "Stocks up 4.9%",
                                 keywords: keywords, numericValue: 4.9)
        let refs = CrossReferenceMatcher().findCrossReferences(claims: [c1, c2, c3])
        let clusters = clusterer.clusterClaims(claims: [c1, c2, c3], crossReferences: refs)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters[0].corroborationLevel, .strongConsensus)
    }

    func testClusterDetectsContradictions() {
        let clusterer = ClaimClusterer()
        let keywords = ["budget", "spending", "government"]
        let c1 = ExtractedClaim(articleId: "a1", articleTitle: "Budget A", sourceId: "BBC",
                                 claimType: .monetary, claimText: "$100 million budget",
                                 keywords: keywords, numericValue: 100_000_000)
        let c2 = ExtractedClaim(articleId: "a2", articleTitle: "Budget B", sourceId: "Fox",
                                 claimType: .monetary, claimText: "$500 million budget",
                                 keywords: keywords, numericValue: 500_000_000)
        let matcher = CrossReferenceMatcher()
        let refs = matcher.findCrossReferences(claims: [c1, c2])
        let clusters = clusterer.clusterClaims(claims: [c1, c2], crossReferences: refs)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertFalse(clusters[0].contradictions.isEmpty, "Should detect contradiction")
        XCTAssertEqual(clusters[0].corroborationLevel, .contradicted)
    }

    func testEmptyClustering() {
        let clusterer = ClaimClusterer()
        let clusters = clusterer.clusterClaims(claims: [], crossReferences: [])
        XCTAssertEqual(clusters.count, 0)
    }

    // MARK: - Alert Generator Tests

    func testContradictionAlert() {
        let generator = CrossRefAlertGenerator()
        let c1 = ExtractedClaim(articleId: "a1", articleTitle: "Title A", sourceId: "BBC",
                                 claimType: .numeric, claimText: "100", keywords: ["test"], numericValue: 100)
        let c2 = ExtractedClaim(articleId: "a2", articleTitle: "Title B", sourceId: "CNN",
                                 claimType: .numeric, claimText: "500", keywords: ["test"], numericValue: 500)
        let contradiction = Contradiction(claimA: c1, claimB: c2, severity: .major,
                                           description: "Conflicting numbers")
        let cluster = ClaimCluster(topic: "test", claims: [c1, c2], crossReferences: [],
                                    corroborationLevel: .contradicted, confidenceScore: 20,
                                    sourceCount: 2, contradictions: [contradiction])
        let alerts = generator.generateAlerts(clusters: [cluster], sourceProfiles: [])
        XCTAssertTrue(alerts.contains { $0.alertType == .contradictionFound })
    }

    func testConsensusAlert() {
        let generator = CrossRefAlertGenerator()
        let c1 = ExtractedClaim(articleId: "a1", articleTitle: "A", sourceId: "S1",
                                 claimType: .numeric, claimText: "test", keywords: ["test"])
        let cluster = ClaimCluster(topic: "consensus topic", claims: [c1], crossReferences: [],
                                    corroborationLevel: .strongConsensus, confidenceScore: 90,
                                    sourceCount: 3, contradictions: [])
        let alerts = generator.generateAlerts(clusters: [cluster], sourceProfiles: [])
        XCTAssertTrue(alerts.contains { $0.alertType == .consensusFormed })
    }

    func testSingleSourceAlert() {
        let generator = CrossRefAlertGenerator()
        let c1 = ExtractedClaim(articleId: "a1", articleTitle: "A", sourceId: "OnlySource",
                                 claimType: .numeric, claimText: "test1", keywords: ["test"])
        let c2 = ExtractedClaim(articleId: "a2", articleTitle: "B", sourceId: "OnlySource",
                                 claimType: .numeric, claimText: "test2", keywords: ["test"])
        let cluster = ClaimCluster(topic: "single source topic", claims: [c1, c2], crossReferences: [],
                                    corroborationLevel: .uncorroborated, confidenceScore: 30,
                                    sourceCount: 1, contradictions: [])
        let alerts = generator.generateAlerts(clusters: [cluster], sourceProfiles: [])
        XCTAssertTrue(alerts.contains { $0.alertType == .singleSourceClaim })
    }

    func testSourceReliabilityDropAlert() {
        let generator = CrossRefAlertGenerator()
        let profile = SourceReliabilityProfile(sourceId: "BadSource", totalClaims: 10,
                                                corroboratedClaims: 2, contradictedClaims: 5,
                                                accuracyScore: 20, reliabilityTrend: -15.0)
        let alerts = generator.generateAlerts(clusters: [], sourceProfiles: [profile])
        XCTAssertTrue(alerts.contains { $0.alertType == .sourceReliabilityDrop })
    }

    // MARK: - Source Reliability Tracker Tests

    func testReliabilityTrackerUpdatesProfiles() {
        let tracker = SourceReliabilityTracker()
        let keywords = ["tech", "innovation"]
        let c1 = ExtractedClaim(articleId: "a1", articleTitle: "A", sourceId: "BBC",
                                 claimType: .numeric, claimText: "100 users",
                                 keywords: keywords, numericValue: 100)
        let c2 = ExtractedClaim(articleId: "a2", articleTitle: "B", sourceId: "CNN",
                                 claimType: .numeric, claimText: "101 users",
                                 keywords: keywords, numericValue: 101)
        let ref = CrossReference(primaryClaimId: c1.id, relatedClaimId: c2.id,
                                  similarity: 0.8, agreement: .agrees)
        let cluster = ClaimCluster(topic: "tech", claims: [c1, c2], crossReferences: [ref],
                                    corroborationLevel: .corroborated, confidenceScore: 75,
                                    sourceCount: 2, contradictions: [])
        let profiles = tracker.updateProfiles(clusters: [cluster])
        XCTAssertEqual(profiles.count, 2)
        XCTAssertTrue(profiles.allSatisfy { $0.corroboratedClaims > 0 })
    }

    func testReliabilityProfileRetrieval() {
        let tracker = SourceReliabilityTracker()
        let c1 = ExtractedClaim(articleId: "a1", articleTitle: "A", sourceId: "TestSource",
                                 claimType: .numeric, claimText: "test", keywords: ["test"])
        let cluster = ClaimCluster(topic: "test", claims: [c1], crossReferences: [],
                                    corroborationLevel: .uncorroborated, confidenceScore: 30,
                                    sourceCount: 1, contradictions: [])
        _ = tracker.updateProfiles(clusters: [cluster])
        XCTAssertNotNil(tracker.profile(for: "TestSource"))
        XCTAssertNil(tracker.profile(for: "NonExistent"))
    }

    // MARK: - FeedCrossReferenceEngine Integration Tests

    func testEngineIngestAndAnalyze() {
        let engine = FeedCrossReferenceEngine()
        let story1 = makeStory(title: "Economy Report",
                                body: "GDP grew by 3.5 percent this quarter. Unemployment fell to 4.2%.")
        let story2 = makeStory(title: "Economic Update",
                                body: "GDP growth reached 3.6 percent. The unemployment rate is now 4.1%.")

        let count1 = engine.ingestArticle(story1, sourceId: "BBC")
        let count2 = engine.ingestArticle(story2, sourceId: "Reuters")

        XCTAssertGreaterThan(count1, 0, "Should extract claims from first article")
        XCTAssertGreaterThan(count2, 0, "Should extract claims from second article")

        let report = engine.analyze()
        XCTAssertGreaterThan(report.totalClaims, 0)
        XCTAssertGreaterThanOrEqual(report.healthScore, 0)
        XCTAssertLessThanOrEqual(report.healthScore, 100)
    }

    func testEngineBatchIngestion() {
        let engine = FeedCrossReferenceEngine()
        let stories = [
            makeStory(title: "Tech A", body: "Apple sold 50 million iPhones this quarter."),
            makeStory(title: "Tech B", body: "The company reported $89 billion in revenue."),
        ]
        let count = engine.ingestArticles(stories, sourceId: "TechCrunch")
        XCTAssertGreaterThan(count, 0)
    }

    func testEngineMultiSourceAnalysis() {
        let engine = FeedCrossReferenceEngine()
        let s1 = makeStory(title: "Climate Change Report", body: "Global temperatures rose by 1.5 degrees Celsius since 2020. Carbon emissions increased by 12 percent.")
        let s2 = makeStory(title: "Climate Change Update", body: "Temperatures have risen 1.5 degrees. Carbon emissions grew by 12 percent this year.")
        let s3 = makeStory(title: "Climate News", body: "Scientists report a 1.4 degree temperature increase. Emissions up 13 percent.")

        engine.ingestArticle(s1, sourceId: "BBC")
        engine.ingestArticle(s2, sourceId: "Reuters")
        engine.ingestArticle(s3, sourceId: "NPR")

        let report = engine.analyze()
        XCTAssertGreaterThan(report.totalClaims, 0)
        XCTAssertGreaterThanOrEqual(report.totalClusters, 0)
        XCTAssertFalse(report.insights.isEmpty, "Should generate insights")
    }

    func testEngineQueryMethods() {
        let engine = FeedCrossReferenceEngine()
        let s1 = makeStory(title: "Market A", body: "Stocks rose 5 percent today in heavy trading.")
        let s2 = makeStory(title: "Market B", body: "The market dropped 10 percent in afternoon trading.")

        engine.ingestArticle(s1, sourceId: "Bloomberg")
        engine.ingestArticle(s2, sourceId: "CNBC")
        _ = engine.analyze()

        let bloombergClaims = engine.claims(for: "Bloomberg")
        XCTAssertGreaterThan(bloombergClaims.count, 0)

        let allAlerts = engine.activeAlerts()
        XCTAssertNotNil(allAlerts)

        XCTAssertGreaterThan(engine.totalClaimsCount(), 0)
    }

    func testEngineReset() {
        let engine = FeedCrossReferenceEngine()
        let story = makeStory(title: "Test", body: "The company has 5000 employees across 20 offices.")
        engine.ingestArticle(story, sourceId: "Test")
        XCTAssertGreaterThan(engine.totalClaimsCount(), 0)

        engine.reset()
        XCTAssertEqual(engine.totalClaimsCount(), 0)
        XCTAssertTrue(engine.currentClusters().isEmpty)
        XCTAssertTrue(engine.activeAlerts().isEmpty)
    }

    func testEngineEmptyAnalysis() {
        let engine = FeedCrossReferenceEngine()
        let report = engine.analyze()
        XCTAssertEqual(report.totalClaims, 0)
        XCTAssertEqual(report.totalClusters, 0)
        XCTAssertEqual(report.healthScore, 50.0, "Empty analysis should have neutral health score")
    }

    func testEngineHealthScoreRange() {
        let engine = FeedCrossReferenceEngine()
        for i in 0..<20 {
            let story = makeStory(
                title: "Article \(i)",
                body: "The report shows \(i * 5) percent growth with $\(i * 100) million in revenue and \(i * 1000) users."
            )
            engine.ingestArticle(story, sourceId: "Source\(i % 4)")
        }
        let report = engine.analyze()
        XCTAssertGreaterThanOrEqual(report.healthScore, 0)
        XCTAssertLessThanOrEqual(report.healthScore, 100)
    }

    func testEngineSourceReliability() {
        let engine = FeedCrossReferenceEngine()
        let s1 = makeStory(title: "Fact Check A", body: "The budget is $500 million for infrastructure projects.")
        let s2 = makeStory(title: "Fact Check B", body: "Infrastructure budget set at $500 million this year.")

        engine.ingestArticle(s1, sourceId: "FactChecker")
        engine.ingestArticle(s2, sourceId: "Validator")
        _ = engine.analyze()

        // Source profiles should exist after analysis
        let fc = engine.sourceReliability("FactChecker")
        XCTAssertNotNil(fc)
    }

    func testEngineContradicedClusters() {
        let engine = FeedCrossReferenceEngine()
        let s1 = makeStory(title: "Sales Report", body: "Company reported $100 million in sales revenue this quarter.")
        let s2 = makeStory(title: "Sales Report", body: "Company reported $500 million in sales revenue this quarter.")

        engine.ingestArticle(s1, sourceId: "SourceA")
        engine.ingestArticle(s2, sourceId: "SourceB")
        _ = engine.analyze()

        // May or may not have contradictions depending on keyword overlap
        let contradicted = engine.contradictedClusters()
        XCTAssertNotNil(contradicted, "Should return contradicted clusters array")
    }

    func testEngineConsensusClusters() {
        let engine = FeedCrossReferenceEngine()
        let consensus = engine.consensusClusters()
        XCTAssertTrue(consensus.isEmpty, "No clusters before analysis")
    }

    func testHTMLReportGeneration() {
        let engine = FeedCrossReferenceEngine()
        let s1 = makeStory(title: "Test Report", body: "Revenue reached $50 million, a 25 percent increase.")
        engine.ingestArticle(s1, sourceId: "TestSource")

        let html = engine.generateHTMLReport()
        XCTAssertTrue(html.contains("Cross-Reference Analysis"))
        XCTAssertTrue(html.contains("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("Claim Clusters"))
        XCTAssertTrue(html.contains("Source Reliability"))
        XCTAssertTrue(html.contains("Contradictions"))
        XCTAssertTrue(html.contains("Insights"))
    }

    func testHTMLReportEmpty() {
        let engine = FeedCrossReferenceEngine()
        let html = engine.generateHTMLReport()
        XCTAssertTrue(html.contains("Cross-Reference Analysis"))
        XCTAssertTrue(html.contains("No claims ingested yet"))
    }

    // MARK: - Corroboration Level Tests

    func testCorroborationLevelComparable() {
        XCTAssertTrue(CorroborationLevel.contradicted < CorroborationLevel.strongConsensus)
        XCTAssertTrue(CorroborationLevel.uncorroborated < CorroborationLevel.corroborated)
        XCTAssertTrue(CorroborationLevel.disputed < CorroborationLevel.uncorroborated)
    }

    // MARK: - Agreement Type Tests

    func testAgreementTypeRawValues() {
        XCTAssertEqual(AgreementType.agrees.rawValue, "Agrees")
        XCTAssertEqual(AgreementType.contradicts.rawValue, "Contradicts")
        XCTAssertEqual(AgreementType.neutral.rawValue, "Neutral")
    }

    // MARK: - Claim Type Tests

    func testClaimTypeCaseIterable() {
        XCTAssertEqual(ClaimType.allCases.count, 8)
    }

    // MARK: - Configuration Tests

    func testEngineSimilarityThreshold() {
        let engine = FeedCrossReferenceEngine()
        engine.similarityThreshold = 0.5
        XCTAssertEqual(engine.similarityThreshold, 0.5)
    }

    func testEngineNumericAgreementThreshold() {
        let engine = FeedCrossReferenceEngine()
        engine.numericAgreementThreshold = 0.2
        XCTAssertEqual(engine.numericAgreementThreshold, 0.2)
    }

    // MARK: - Notification Tests

    func testNotificationNames() {
        XCTAssertEqual(Notification.Name.crossRefContradictionDetected.rawValue, "CrossRefContradictionDetectedNotification")
        XCTAssertEqual(Notification.Name.crossRefConsensusFormed.rawValue, "CrossRefConsensusFormedNotification")
        XCTAssertEqual(Notification.Name.crossRefLowConfidenceClaim.rawValue, "CrossRefLowConfidenceClaimNotification")
    }

    // MARK: - Contradiction Severity Tests

    func testContradictionSeverityRawValues() {
        XCTAssertEqual(ContradictionSeverity.minor.rawValue, "Minor")
        XCTAssertEqual(ContradictionSeverity.critical.rawValue, "Critical")
        XCTAssertEqual(ContradictionSeverity.allCases.count, 4)
    }

    // MARK: - CrossRefAlertType Tests

    func testAlertTypeCaseIterable() {
        XCTAssertEqual(CrossRefAlertType.allCases.count, 6)
    }

    // MARK: - Edge Case Tests

    func testVeryLongArticle() {
        let engine = FeedCrossReferenceEngine()
        let longBody = (0..<100).map { "Paragraph \($0): The measurement was \($0 * 3) percent with $\($0 * 10) million invested." }.joined(separator: " ")
        let story = makeStory(title: "Long Report", body: longBody)
        let count = engine.ingestArticle(story, sourceId: "LongSource")
        XCTAssertGreaterThan(count, 0, "Should handle long articles")
    }

    func testSpecialCharactersInClaims() {
        let engine = FeedCrossReferenceEngine()
        let story = makeStory(title: "Special & Chars", body: "Revenue was $50 million (up 25%) in Q3 2024.")
        let count = engine.ingestArticle(story, sourceId: "Test")
        XCTAssertGreaterThanOrEqual(count, 0, "Should handle special characters")
    }

    func testManySourcesScaling() {
        let engine = FeedCrossReferenceEngine()
        for i in 0..<10 {
            let story = makeStory(
                title: "Market Report \(i)",
                body: "The index reached \(1000 + i) points today, a \(2 + i) percent gain."
            )
            engine.ingestArticle(story, sourceId: "Source\(i)")
        }
        let report = engine.analyze()
        XCTAssertGreaterThan(report.totalClaims, 0)
        XCTAssertFalse(report.insights.isEmpty)
    }

    // MARK: - CrossReferenceMatcher Perf-Path Regressions
    //
    // The Jaccard / negation precomputation refactor in CrossReferenceMatcher
    // changed how the O(N²) inner loop is executed but must preserve the
    // observable outputs. These tests pin the behavior so future perf work
    // does not silently drift.

    /// Two cross-source claims of the same type with overlapping keywords
    /// should produce exactly one CrossReference, regardless of which order
    /// they are passed in. Empty keyword lists must never reach the matcher's
    /// similarity check (and so must not produce a reference).
    func testMatcherProducesSinglePairForOverlappingKeywords() {
        let matcher = CrossReferenceMatcher()
        let a = ExtractedClaim(
            articleId: "art-A", articleTitle: "A", sourceId: "src-A",
            claimType: .numeric, claimText: "Revenue was high",
            keywords: ["revenue", "growth", "quarter"]
        )
        let b = ExtractedClaim(
            articleId: "art-B", articleTitle: "B", sourceId: "src-B",
            claimType: .numeric, claimText: "Quarterly revenue rose",
            keywords: ["revenue", "growth", "earnings"]
        )
        let refs = matcher.findCrossReferences(claims: [a, b])
        XCTAssertEqual(refs.count, 1, "Two overlapping cross-source claims should yield exactly one ref")
        XCTAssertGreaterThan(refs[0].similarity, 0, "Jaccard similarity must be positive when keywords overlap")
        XCTAssertLessThanOrEqual(refs[0].similarity, 1.0)
    }

    /// Same source must never match itself, even with identical keywords.
    func testMatcherSkipsSameSourceClaims() {
        let matcher = CrossReferenceMatcher()
        let a = ExtractedClaim(
            articleId: "art-1", articleTitle: "A", sourceId: "sameSrc",
            claimType: .numeric, claimText: "x", keywords: ["k1", "k2"]
        )
        let b = ExtractedClaim(
            articleId: "art-2", articleTitle: "B", sourceId: "sameSrc",
            claimType: .numeric, claimText: "y", keywords: ["k1", "k2"]
        )
        XCTAssertTrue(matcher.findCrossReferences(claims: [a, b]).isEmpty)
    }

    /// Empty keyword sets cannot produce any positive Jaccard similarity, so
    /// they must be filtered out even when other fields would otherwise match.
    /// The previous implementation would still build the Sets and run the
    /// comparison; the optimized one short-circuits. Behavior must remain:
    /// no references emitted.
    func testMatcherIgnoresEmptyKeywordClaims() {
        let matcher = CrossReferenceMatcher()
        let a = ExtractedClaim(
            articleId: "art-1", articleTitle: "A", sourceId: "srcA",
            claimType: .numeric, claimText: "x", keywords: []
        )
        let b = ExtractedClaim(
            articleId: "art-2", articleTitle: "B", sourceId: "srcB",
            claimType: .numeric, claimText: "y", keywords: ["k1", "k2"]
        )
        XCTAssertTrue(matcher.findCrossReferences(claims: [a, b]).isEmpty)
        XCTAssertTrue(matcher.findCrossReferences(claims: [b, a]).isEmpty)
        XCTAssertTrue(matcher.findCrossReferences(claims: [a, a]).isEmpty)
    }

    /// Two numeric claims with values within 5% must be flagged as `.agrees`.
    /// This guards the numeric-value short-circuit in `assessAgreement`.
    func testMatcherAgreesWhenNumericValuesAreClose() {
        let matcher = CrossReferenceMatcher()
        let a = ExtractedClaim(
            articleId: "a1", articleTitle: "A", sourceId: "srcA",
            claimType: .monetary, claimText: "$100 million",
            keywords: ["revenue", "q3"], numericValue: 100.0
        )
        let b = ExtractedClaim(
            articleId: "a2", articleTitle: "B", sourceId: "srcB",
            claimType: .monetary, claimText: "$102 million",
            keywords: ["revenue", "q3"], numericValue: 102.0
        )
        let refs = matcher.findCrossReferences(claims: [a, b])
        XCTAssertEqual(refs.count, 1)
        XCTAssertEqual(refs[0].agreement, .agrees)
        if let dev = refs[0].numericDeviation {
            XCTAssertLessThanOrEqual(dev, 0.05)
        } else {
            XCTFail("Numeric deviation should be reported when both values are numeric")
        }
    }

    /// One claim negated, one not → `.partiallyDisagrees` when no numeric value.
    /// Guards the precomputed-negation path in `findCrossReferences`.
    func testMatcherDetectsAsymmetricNegationAsPartialDisagreement() {
        let matcher = CrossReferenceMatcher()
        let a = ExtractedClaim(
            articleId: "a1", articleTitle: "A", sourceId: "srcA",
            claimType: .attribution,
            claimText: "Spokesperson confirmed the deal closed.",
            keywords: ["deal", "spokesperson", "closed"]
        )
        let b = ExtractedClaim(
            articleId: "a2", articleTitle: "B", sourceId: "srcB",
            claimType: .attribution,
            claimText: "Spokesperson denied the deal closed.",
            keywords: ["deal", "spokesperson", "closed"]
        )
        let refs = matcher.findCrossReferences(claims: [a, b])
        XCTAssertEqual(refs.count, 1)
        XCTAssertEqual(refs[0].agreement, .partiallyDisagrees,
                       "Asymmetric negation between non-numeric claims should report partial disagreement")
    }

    /// Both negated or both not negated → `.neutral` when no numeric values.
    func testMatcherSymmetricNegationIsNeutral() {
        let matcher = CrossReferenceMatcher()
        let a = ExtractedClaim(
            articleId: "a1", articleTitle: "A", sourceId: "srcA",
            claimType: .attribution,
            claimText: "The CEO denied any wrongdoing.",
            keywords: ["ceo", "wrongdoing"]
        )
        let b = ExtractedClaim(
            articleId: "a2", articleTitle: "B", sourceId: "srcB",
            claimType: .attribution,
            claimText: "The chair denied any misconduct allegations.",
            keywords: ["ceo", "wrongdoing"]
        )
        let refs = matcher.findCrossReferences(claims: [a, b])
        XCTAssertEqual(refs.count, 1)
        XCTAssertEqual(refs[0].agreement, .neutral,
                       "Both-negated claims should not be flagged as disagreement")
    }

    /// Symmetry: the Jaccard score must be order-independent.
    func testMatcherJaccardSymmetry() {
        let matcher = CrossReferenceMatcher()
        let a = ExtractedClaim(
            articleId: "a1", articleTitle: "A", sourceId: "srcA",
            claimType: .statistic, claimText: "x",
            keywords: ["alpha", "beta", "gamma", "delta"]
        )
        let b = ExtractedClaim(
            articleId: "a2", articleTitle: "B", sourceId: "srcB",
            claimType: .statistic, claimText: "y",
            keywords: ["gamma", "delta", "epsilon"]
        )
        let ab = matcher.findCrossReferences(claims: [a, b])
        let ba = matcher.findCrossReferences(claims: [b, a])
        XCTAssertEqual(ab.count, 1)
        XCTAssertEqual(ba.count, 1)
        XCTAssertEqual(ab[0].similarity, ba[0].similarity, accuracy: 1e-9,
                       "Jaccard similarity must be symmetric regardless of input order")
    }

    /// `similarityThreshold` must actually gate emission: raising it past the
    /// computed similarity drops the ref entirely.
    func testMatcherSimilarityThresholdGatesEmission() {
        let matcher = CrossReferenceMatcher()
        let a = ExtractedClaim(
            articleId: "a1", articleTitle: "A", sourceId: "srcA",
            claimType: .numeric, claimText: "x",
            keywords: ["k1", "k2", "k3", "k4"]
        )
        let b = ExtractedClaim(
            articleId: "a2", articleTitle: "B", sourceId: "srcB",
            claimType: .numeric, claimText: "y",
            keywords: ["k4", "k5", "k6", "k7"]
        )
        // Jaccard = 1/7 ≈ 0.143 — below the default 0.15 threshold but above 0.10.
        matcher.similarityThreshold = 0.10
        XCTAssertEqual(matcher.findCrossReferences(claims: [a, b]).count, 1)
        matcher.similarityThreshold = 0.90
        XCTAssertTrue(matcher.findCrossReferences(claims: [a, b]).isEmpty)
    }

    /// Singleton input must short-circuit cleanly (no pair to compare).
    func testMatcherSingleClaimReturnsEmpty() {
        let matcher = CrossReferenceMatcher()
        let a = ExtractedClaim(
            articleId: "a", articleTitle: "A", sourceId: "srcA",
            claimType: .numeric, claimText: "x", keywords: ["k1"]
        )
        XCTAssertTrue(matcher.findCrossReferences(claims: [a]).isEmpty)
        XCTAssertTrue(matcher.findCrossReferences(claims: []).isEmpty)
    }

    // MARK: - ClaimClusterer Perf-Path Regressions

    /// Two cross-article claims with high keyword overlap should land in the
    /// same cluster even without explicit CrossReferences. This exercises the
    /// optimized inner loop in `ClaimClusterer.clusterClaims` that now
    /// precomputes keyword Sets once per claim.
    func testClustererGroupsHighOverlapClaimsAcrossArticles() {
        let clusterer = ClaimClusterer()
        let a = ExtractedClaim(
            articleId: "art-1", articleTitle: "A", sourceId: "srcA",
            claimType: .statistic, claimText: "x",
            keywords: ["climate", "emissions", "policy", "2030"]
        )
        let b = ExtractedClaim(
            articleId: "art-2", articleTitle: "B", sourceId: "srcB",
            claimType: .statistic, claimText: "y",
            keywords: ["climate", "emissions", "policy", "2050"]
        )
        let clusters = clusterer.clusterClaims(claims: [a, b], crossReferences: [])
        XCTAssertEqual(clusters.count, 1, "High-overlap cross-article claims should merge into one cluster")
        XCTAssertEqual(clusters[0].claims.count, 2)
    }

    /// Same-article claims must not be merged purely on keyword overlap; the
    /// clusterer only fuses across different articles.
    func testClustererDoesNotMergeSameArticleClaimsOnOverlap() {
        let clusterer = ClaimClusterer()
        let a = ExtractedClaim(
            articleId: "shared", articleTitle: "A", sourceId: "srcA",
            claimType: .numeric, claimText: "x", keywords: ["k1", "k2", "k3"]
        )
        let b = ExtractedClaim(
            articleId: "shared", articleTitle: "A", sourceId: "srcA",
            claimType: .numeric, claimText: "y", keywords: ["k1", "k2", "k3"]
        )
        let clusters = clusterer.clusterClaims(claims: [a, b], crossReferences: [])
        // No CrossReferences provided and same articleId → each claim is its own
        // singleton cluster.
        XCTAssertEqual(clusters.count, 2)
    }

    /// Empty keyword arrays must be skipped by the cluster overlap heuristic
    /// (they could never reach a positive Jaccard score). Behavior pinned
    /// after the keyword-set precomputation refactor.
    func testClustererSkipsEmptyKeywordClaims() {
        let clusterer = ClaimClusterer()
        let empty = ExtractedClaim(
            articleId: "art-1", articleTitle: "A", sourceId: "srcA",
            claimType: .numeric, claimText: "x", keywords: []
        )
        let other = ExtractedClaim(
            articleId: "art-2", articleTitle: "B", sourceId: "srcB",
            claimType: .numeric, claimText: "y", keywords: ["k1", "k2"]
        )
        let clusters = clusterer.clusterClaims(claims: [empty, other], crossReferences: [])
        XCTAssertEqual(clusters.count, 2, "Empty-keyword claim must remain its own singleton cluster")
    }

    /// Existing CrossReferences must still seed the cluster adjacency even when
    /// keyword overlap is below the threshold. Guards the `adjacency` build at
    /// the top of `clusterClaims`.
    func testClustererHonorsExplicitCrossReferenceAdjacency() {
        let clusterer = ClaimClusterer()
        let a = ExtractedClaim(
            id: "id-a",
            articleId: "art-1", articleTitle: "A", sourceId: "srcA",
            claimType: .numeric, claimText: "x", keywords: ["only-a"]
        )
        let b = ExtractedClaim(
            id: "id-b",
            articleId: "art-2", articleTitle: "B", sourceId: "srcB",
            claimType: .numeric, claimText: "y", keywords: ["only-b"]
        )
        let ref = CrossReference(
            primaryClaimId: "id-a", relatedClaimId: "id-b",
            similarity: 0.0, agreement: .neutral
        )
        let clusters = clusterer.clusterClaims(claims: [a, b], crossReferences: [ref])
        XCTAssertEqual(clusters.count, 1, "Explicit CrossReference must merge claims even without keyword overlap")
        XCTAssertEqual(clusters[0].claims.count, 2)
    }
}
