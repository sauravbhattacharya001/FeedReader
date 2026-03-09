//
//  ArticleCrossReferenceTests.swift
//  FeedReaderTests
//
//  Tests for the ArticleCrossReferenceEngine — entity extraction,
//  cross-referencing, trending, merge, export/import.
//

import XCTest
@testable import FeedReader

class ArticleCrossReferenceTests: XCTestCase {

    var engine: ArticleCrossReferenceEngine!

    override func setUp() {
        super.setUp()
        engine = ArticleCrossReferenceEngine.shared
        engine.clearIndex()
    }

    override func tearDown() {
        engine.clearIndex()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeStory(title: String, body: String, link: String = UUID().uuidString,
                           feed: String = "Test Feed") -> Story {
        let story = Story(title: title, photo: nil, body: body, link: link)
        story.sourceFeedName = feed
        return story
    }

    // MARK: - Entity Extraction

    func testExtractEntities_PersonName() {
        let entities = engine.extractEntitiesFromText(
            "Today Elon Musk announced a new plan. Elon Musk said it would change everything.")
        let names = entities.keys.map { $0.name.lowercased() }
        XCTAssertTrue(names.contains(where: { $0.contains("elon") || $0.contains("musk") }),
                      "Should extract 'Elon Musk' as entity. Got: \(names)")
    }

    func testExtractEntities_Organization() {
        let entities = engine.extractEntitiesFromText(
            "Officials at Goldman Sachs Group released quarterly earnings. Goldman Sachs Group reported growth.")
        let names = entities.keys.map { $0.name.lowercased() }
        XCTAssertTrue(names.contains(where: { $0.contains("goldman") }),
                      "Should extract Goldman Sachs. Got: \(names)")
    }

    func testExtractEntities_MultipleEntities() {
        let entities = engine.extractEntitiesFromText(
            "Tim Cook spoke at Apple Inc about iPhone sales. Tim Cook said Apple Inc is growing.")
        XCTAssertGreaterThanOrEqual(entities.count, 1, "Should extract at least one entity")
    }

    func testExtractEntities_CountsMentions() {
        let entities = engine.extractEntitiesFromText(
            "Google Inc is big. People love Google Inc products. Google Inc announced today.")
        let googleEntity = entities.first { $0.key.name.lowercased().contains("google") }
        if let (_, count) = googleEntity {
            XCTAssertGreaterThanOrEqual(count, 2, "Google should have multiple mentions")
        }
    }

    func testExtractEntities_IgnoresStopPhrases() {
        let entities = engine.extractEntitiesFromText(
            "Read More about the latest. Click Here for details. Sign Up now.")
        let names = entities.keys.map { $0.name.lowercased() }
        XCTAssertFalse(names.contains("read more"))
        XCTAssertFalse(names.contains("click here"))
        XCTAssertFalse(names.contains("sign up"))
    }

    func testExtractEntities_IgnoresDates() {
        let entities = engine.extractEntitiesFromText(
            "The event on January 2024 was great. March 15 was special.")
        let names = entities.keys.map { $0.name.lowercased() }
        XCTAssertFalse(names.contains(where: { $0.contains("january") }),
                       "Should not extract dates as entities")
    }

    func testExtractEntities_StripsHTML() {
        let entities = engine.extractEntitiesFromText(
            "<p>Microsoft Corp announced today.</p> <a href='#'>Microsoft Corp</a> is leading.")
        let names = entities.keys.map { $0.name.lowercased() }
        // Should still find Microsoft despite HTML tags
        XCTAssertTrue(names.contains(where: { $0.contains("microsoft") }),
                      "Should extract entities from HTML-stripped text")
    }

    func testExtractEntities_EmptyText() {
        let entities = engine.extractEntitiesFromText("")
        XCTAssertTrue(entities.isEmpty)
    }

    // MARK: - Entity Classification

    func testClassify_OrganizationSuffix() {
        let entities = engine.extractEntitiesFromText(
            "We visited Tesla Inc today. Tesla Inc has new products.")
        let teslaEntity = entities.keys.first { $0.name.lowercased().contains("tesla") }
        if let entity = teslaEntity {
            XCTAssertEqual(entity.type, .organization, "Entity with 'Inc' suffix should be .organization")
        }
    }

    func testClassify_PersonFromVerb() {
        let entities = engine.extractEntitiesFromText(
            "Today Warren Buffett said markets are strong. Warren Buffett announced new investments.")
        let person = entities.keys.first { $0.name.lowercased().contains("buffett") }
        if let entity = person {
            XCTAssertEqual(entity.type, .person, "Person who 'said' something should be .person")
        }
    }

    // MARK: - Indexing

    func testIndexArticle_AddsToIndex() {
        let story = makeStory(
            title: "Apple Inc Reports Record Revenue",
            body: "Apple Inc CEO Tim Cook said quarterly revenue hit new highs. Apple Inc stock rose 5%.")
        engine.indexArticle(story)

        let summary = engine.indexSummary()
        XCTAssertEqual(summary.totalArticlesIndexed, 1)
        XCTAssertGreaterThan(summary.totalEntities, 0)
    }

    func testIndexArticle_NoDuplicates() {
        let story = makeStory(
            title: "Tesla News",
            body: "Tesla Inc announced new models. Tesla Inc is growing fast.")
        engine.indexArticle(story)
        engine.indexArticle(story) // Index again

        let summary = engine.indexSummary()
        XCTAssertEqual(summary.totalArticlesIndexed, 1, "Should not double-index same article")
    }

    func testIndexMultipleArticles() {
        let s1 = makeStory(title: "Tech News", body: "Google Inc launched new AI. Google Inc is leading.")
        let s2 = makeStory(title: "More Tech", body: "Amazon Inc reports earnings. Amazon Inc grew 20%.")
        engine.indexArticles([s1, s2])

        let summary = engine.indexSummary()
        XCTAssertEqual(summary.totalArticlesIndexed, 2)
    }

    func testRemoveArticle() {
        let story = makeStory(
            title: "News", body: "Facebook Inc changed name. Facebook Inc is Meta now.",
            link: "https://example.com/1")
        engine.indexArticle(story)
        XCTAssertEqual(engine.indexSummary().totalArticlesIndexed, 1)

        engine.removeArticle(link: "https://example.com/1")
        XCTAssertEqual(engine.indexSummary().totalArticlesIndexed, 0)
    }

    func testClearIndex() {
        let story = makeStory(title: "News", body: "Google Inc is big. Google Inc announced today.")
        engine.indexArticle(story)
        XCTAssertGreaterThan(engine.indexSummary().totalEntities, 0)

        engine.clearIndex()
        XCTAssertEqual(engine.indexSummary().totalEntities, 0)
        XCTAssertEqual(engine.indexSummary().totalArticlesIndexed, 0)
    }

    // MARK: - Cross-Referencing

    func testFindCrossReferences_SharedEntity() {
        let s1 = makeStory(
            title: "Google AI Announcement",
            body: "Google Inc unveiled new AI technology. Google Inc CEO spoke about the future.",
            link: "link-1", feed: "Tech News")
        let s2 = makeStory(
            title: "Big Tech Revenue",
            body: "Google Inc reported strong revenue growth. Google Inc beat analyst expectations.",
            link: "link-2", feed: "Finance")

        engine.indexArticles([s1, s2])

        let refs = engine.findCrossReferences(for: s1)
        XCTAssertEqual(refs.count, 1, "Should find s2 as cross-reference via Google Inc")
        if let first = refs.first {
            XCTAssertEqual(first.relatedArticleLink, "link-2")
            XCTAssertTrue(first.sharedEntities.contains(where: {
                $0.name.lowercased().contains("google")
            }))
        }
    }

    func testFindCrossReferences_NoSharedEntities() {
        let s1 = makeStory(
            title: "Apple News",
            body: "Apple Inc launched iPhone. Apple Inc reported growth.",
            link: "link-1")
        let s2 = makeStory(
            title: "Sports Update",
            body: "Manchester United won the match. Manchester United celebrated victory.",
            link: "link-2")

        engine.indexArticles([s1, s2])

        let refs = engine.findCrossReferences(for: s1)
        // Should not cross-reference unrelated articles
        let relatedLinks = refs.map(\.relatedArticleLink)
        XCTAssertFalse(relatedLinks.contains("link-2"),
                       "Unrelated articles should not be cross-referenced")
    }

    func testFindCrossReferences_RespectsLimit() {
        // Create many articles mentioning same entity
        var stories: [Story] = []
        for i in 0..<15 {
            stories.append(makeStory(
                title: "News \(i) about Microsoft Corp",
                body: "Microsoft Corp did something interesting. Microsoft Corp announced today.",
                link: "link-\(i)"))
        }
        engine.indexArticles(stories)

        let refs = engine.findCrossReferences(for: stories[0], limit: 5)
        XCTAssertLessThanOrEqual(refs.count, 5)
    }

    func testFindCrossReferences_DoesNotIncludeSelf() {
        let story = makeStory(
            title: "Tesla Update",
            body: "Tesla Inc announced new factory. Tesla Inc expanded production.",
            link: "self-link")
        engine.indexArticle(story)

        let refs = engine.findCrossReferences(for: story)
        XCTAssertFalse(refs.contains(where: { $0.relatedArticleLink == "self-link" }),
                       "Should not include the article itself in cross-references")
    }

    // MARK: - Entity Lookup

    func testArticlesMentioning() {
        let s1 = makeStory(
            title: "Amazon News",
            body: "Amazon Inc expanded globally. Amazon Inc is growing.",
            link: "link-1")
        engine.indexArticle(s1)

        let occs = engine.articles(mentioning: "Amazon Inc")
        XCTAssertEqual(occs.count, 1)
        XCTAssertEqual(occs.first?.articleLink, "link-1")
    }

    func testArticlesMentioning_CaseInsensitive() {
        let story = makeStory(
            title: "News", body: "Netflix Inc is streaming. Netflix Inc leads market.",
            link: "link-1")
        engine.indexArticle(story)

        let upper = engine.articles(mentioning: "NETFLIX INC")
        let lower = engine.articles(mentioning: "netflix inc")
        XCTAssertEqual(upper.count, lower.count, "Lookup should be case-insensitive")
    }

    func testEntityProfile() {
        let story = makeStory(
            title: "Report",
            body: "SpaceX Inc launched rocket. SpaceX Inc made history. SpaceX Inc plans more.",
            link: "link-1", feed: "Space News")
        engine.indexArticle(story)

        let profile = engine.profile(for: "SpaceX Inc")
        XCTAssertNotNil(profile)
        if let p = profile {
            XCTAssertGreaterThanOrEqual(p.totalMentions, 1)
            XCTAssertEqual(p.articleCount, 1)
            XCTAssertEqual(p.feedCount, 1)
        }
    }

    func testEntityProfile_NotFound() {
        let profile = engine.profile(for: "Nonexistent Corp")
        XCTAssertNil(profile)
    }

    // MARK: - Entity Discovery

    func testAllEntities() {
        let story = makeStory(
            title: "Tech Giants",
            body: "Apple Inc and Google Inc compete. Apple Inc and Google Inc announced today.")
        engine.indexArticle(story)

        let all = engine.allEntities()
        XCTAssertGreaterThanOrEqual(all.count, 1)
    }

    func testAllEntities_FilterByType() {
        let story = makeStory(
            title: "Report",
            body: "Oracle Corp unveiled new tech. Oracle Corp is an enterprise company.")
        engine.indexArticle(story)

        let orgs = engine.allEntities(ofType: .organization)
        let people = engine.allEntities(ofType: .person)
        // At least Oracle Corp should be .organization
        if !orgs.isEmpty {
            XCTAssertTrue(orgs.allSatisfy { $0.type == .organization })
        }
        if !people.isEmpty {
            XCTAssertTrue(people.allSatisfy { $0.type == .person })
        }
    }

    func testSearchEntities() {
        let story = makeStory(
            title: "News",
            body: "Alphabet Inc reported earnings. Alphabet Inc owns Google.")
        engine.indexArticle(story)

        let results = engine.searchEntities(prefix: "Alph")
        XCTAssertTrue(results.contains(where: { $0.name.lowercased().hasPrefix("alph") }),
                      "Search should find entities by prefix")
    }

    func testSearchEntities_NoMatch() {
        let results = engine.searchEntities(prefix: "Zzzzzzz")
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Trending

    func testTrendingEntities() {
        // Index several articles mentioning same entity
        for i in 0..<5 {
            let story = makeStory(
                title: "Nvidia News \(i)",
                body: "Nvidia Corp hit new highs. Nvidia Corp announced GPUs.",
                link: "nvidia-\(i)")
            engine.indexArticle(story)
        }

        let trending = engine.trendingEntities(limit: 5)
        // Nvidia should be trending
        XCTAssertTrue(trending.contains(where: {
            $0.entity.name.lowercased().contains("nvidia")
        }), "Nvidia should be trending after 5 articles")
    }

    // MARK: - Entity Merge

    func testMergeEntities() {
        let s1 = makeStory(
            title: "News 1",
            body: "Google Inc is big. Google Inc announced today.",
            link: "link-1")
        let s2 = makeStory(
            title: "News 2",
            body: "Alphabet Inc reported. Alphabet Inc owns Google.",
            link: "link-2")
        engine.indexArticles([s1, s2])

        engine.mergeEntities(primary: "Google Inc", duplicate: "Alphabet Inc")

        // Alphabet should no longer exist as separate entity
        let alphabet = engine.profile(for: "Alphabet Inc")
        XCTAssertNil(alphabet, "Duplicate should be removed after merge")

        // Google should have occurrences from both
        let google = engine.profile(for: "Google Inc")
        XCTAssertNotNil(google)
        if let g = google {
            XCTAssertEqual(g.articleCount, 2, "Merged entity should have occurrences from both articles")
        }
    }

    func testMergeEntities_NonExistent() {
        // Should not crash
        engine.mergeEntities(primary: "Real Corp", duplicate: "Fake Corp")
    }

    // MARK: - Export/Import

    func testExportJSON() {
        let story = makeStory(
            title: "Export Test",
            body: "Samsung Corp released new phone. Samsung Corp leads market.")
        engine.indexArticle(story)

        let data = engine.exportJSON()
        XCTAssertNotNil(data)
        if let d = data {
            XCTAssertGreaterThan(d.count, 0)
        }
    }

    func testImportJSON_Merge() {
        let s1 = makeStory(
            title: "Original",
            body: "IBM Corp is historic. IBM Corp announced today.",
            link: "link-1")
        engine.indexArticle(s1)

        let exported = engine.exportJSON()!

        engine.clearIndex()
        XCTAssertEqual(engine.indexSummary().totalEntities, 0)

        let success = engine.importJSON(exported, merge: true)
        XCTAssertTrue(success)
        XCTAssertGreaterThan(engine.indexSummary().totalEntities, 0)
    }

    func testImportJSON_Replace() {
        let s1 = makeStory(
            title: "Old",
            body: "Old Corp is gone. Old Corp closed down.",
            link: "link-1")
        engine.indexArticle(s1)
        let exported = engine.exportJSON()!

        engine.clearIndex()
        let s2 = makeStory(
            title: "New",
            body: "New Corp opened. New Corp is exciting.",
            link: "link-2")
        engine.indexArticle(s2)

        let success = engine.importJSON(exported, merge: false)
        XCTAssertTrue(success)
        // Should only have old entities (replaced)
        XCTAssertEqual(engine.indexSummary().totalArticlesIndexed, 1)
    }

    func testImportJSON_InvalidData() {
        let garbage = "not json".data(using: .utf8)!
        let success = engine.importJSON(garbage)
        XCTAssertFalse(success)
    }

    // MARK: - Index Summary

    func testIndexSummary_Empty() {
        let summary = engine.indexSummary()
        XCTAssertEqual(summary.totalEntities, 0)
        XCTAssertEqual(summary.totalArticlesIndexed, 0)
        XCTAssertTrue(summary.topEntities.isEmpty)
        XCTAssertTrue(summary.trendingEntities.isEmpty)
    }

    func testIndexSummary_WithData() {
        for i in 0..<3 {
            engine.indexArticle(makeStory(
                title: "Article \(i)",
                body: "Intel Corp is manufacturing chips. Intel Corp invested billions.",
                link: "art-\(i)"))
        }

        let summary = engine.indexSummary()
        XCTAssertEqual(summary.totalArticlesIndexed, 3)
        XCTAssertGreaterThan(summary.totalEntities, 0)
        XCTAssertFalse(summary.topEntities.isEmpty)
    }

    // MARK: - CrossReference Properties

    func testCrossReference_HasExplanation() {
        let s1 = makeStory(
            title: "Tech News",
            body: "Meta Inc changed strategy. Meta Inc CEO spoke out.",
            link: "link-1")
        let s2 = makeStory(
            title: "Social Media",
            body: "Meta Inc reported user growth. Meta Inc expanded globally.",
            link: "link-2")
        engine.indexArticles([s1, s2])

        let refs = engine.findCrossReferences(for: s1)
        if let first = refs.first {
            XCTAssertFalse(first.explanation.isEmpty, "Cross-reference should have explanation")
            XCTAssertTrue(first.explanation.contains("Shares:"))
        }
    }

    func testCrossReference_RelevanceScore() {
        let s1 = makeStory(
            title: "AI Report",
            body: "OpenAI Inc built GPT. OpenAI Inc leads AI research.",
            link: "link-1")
        let s2 = makeStory(
            title: "AI Safety",
            body: "OpenAI Inc discussed safety. OpenAI Inc published report.",
            link: "link-2")
        engine.indexArticles([s1, s2])

        let refs = engine.findCrossReferences(for: s1)
        for ref in refs {
            XCTAssertGreaterThanOrEqual(ref.relevanceScore, 0.0)
            XCTAssertLessThanOrEqual(ref.relevanceScore, 1.0)
        }
    }

    // MARK: - Edge Cases

    func testExtractEntities_OnlyHTML() {
        let entities = engine.extractEntitiesFromText("<div><span></span></div>")
        XCTAssertTrue(entities.isEmpty)
    }

    func testExtractEntities_SpecialCharacters() {
        let entities = engine.extractEntitiesFromText(
            "AT&T Corp reported. AT&T Corp announced today.")
        // Should handle & gracefully
        XCTAssertTrue(true) // No crash = pass
    }

    func testNamedEntity_Equality() {
        let e1 = NamedEntity(name: "Google", type: .organization, originalForms: ["Google"])
        let e2 = NamedEntity(name: "google", type: .organization, originalForms: ["google"])
        let e3 = NamedEntity(name: "Google", type: .person, originalForms: ["Google"])
        XCTAssertEqual(e1, e2, "Entity equality should be case-insensitive")
        XCTAssertNotEqual(e1, e3, "Different types should not be equal")
    }

    func testNamedEntity_Hashable() {
        let e1 = NamedEntity(name: "Apple", type: .organization, originalForms: ["Apple"])
        let e2 = NamedEntity(name: "apple", type: .organization, originalForms: ["apple"])
        var set: Set<NamedEntity> = [e1]
        set.insert(e2)
        XCTAssertEqual(set.count, 1, "Case-insensitive same entities should dedup in Set")
    }

    func testEntityProfile_RecentVelocity() {
        // Profile with recent occurrences should have positive velocity
        let story = makeStory(
            title: "Fresh News",
            body: "Adobe Inc released update. Adobe Inc announced features.",
            link: "link-1")
        engine.indexArticle(story)

        let profile = engine.profile(for: "Adobe Inc")
        XCTAssertNotNil(profile)
        if let p = profile {
            // Just indexed, so it's within the last 7 days
            XCTAssertGreaterThan(p.recentVelocity, 0.0)
        }
    }
}
