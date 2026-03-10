//
//  ArticleRelationshipMapperTests.swift
//  FeedReaderTests
//

import XCTest
@testable import FeedReader

class ArticleRelationshipMapperTests: XCTestCase {

    var mapper: ArticleRelationshipMapper!

    override func setUp() {
        super.setUp()
        mapper = ArticleRelationshipMapper()
        mapper.removeAll()
    }

    override func tearDown() {
        mapper.removeAll()
        super.tearDown()
    }

    // MARK: - Add

    func testAddRelationship() {
        let rel = mapper.addRelationship(
            sourceLink: "https://a.com/1",
            sourceTitle: "Article A",
            targetLink: "https://b.com/2",
            targetTitle: "Article B",
            type: .buildsOn
        )
        XCTAssertNotNil(rel)
        XCTAssertEqual(mapper.count, 1)
        XCTAssertEqual(rel?.type, .buildsOn)
        XCTAssertEqual(rel?.strength, .moderate)
    }

    func testAddRelationshipWithCustomStrengthAndNote() {
        let rel = mapper.addRelationship(
            sourceLink: "https://a.com/1",
            sourceTitle: "A",
            targetLink: "https://b.com/2",
            targetTitle: "B",
            type: .contradictsBy,
            strength: .strong,
            note: "Directly refutes the main claim"
        )
        XCTAssertEqual(rel?.strength, .strong)
        XCTAssertEqual(rel?.note, "Directly refutes the main claim")
    }

    func testAddSelfReferentialReturnsNil() {
        let rel = mapper.addRelationship(
            sourceLink: "https://a.com/1",
            sourceTitle: "A",
            targetLink: "https://a.com/1",
            targetTitle: "A",
            type: .relatedTo
        )
        XCTAssertNil(rel)
        XCTAssertEqual(mapper.count, 0)
    }

    func testAddDuplicateReturnsNil() {
        mapper.addRelationship(
            sourceLink: "https://a.com/1", sourceTitle: "A",
            targetLink: "https://b.com/2", targetTitle: "B",
            type: .buildsOn
        )
        let dup = mapper.addRelationship(
            sourceLink: "https://a.com/1", sourceTitle: "A",
            targetLink: "https://b.com/2", targetTitle: "B",
            type: .buildsOn
        )
        XCTAssertNil(dup)
        XCTAssertEqual(mapper.count, 1)
    }

    func testAddSameArticlesDifferentTypeAllowed() {
        mapper.addRelationship(
            sourceLink: "https://a.com/1", sourceTitle: "A",
            targetLink: "https://b.com/2", targetTitle: "B",
            type: .buildsOn
        )
        let second = mapper.addRelationship(
            sourceLink: "https://a.com/1", sourceTitle: "A",
            targetLink: "https://b.com/2", targetTitle: "B",
            type: .supplements
        )
        XCTAssertNotNil(second)
        XCTAssertEqual(mapper.count, 2)
    }

    // MARK: - Remove

    func testRemoveRelationship() {
        let rel = mapper.addRelationship(
            sourceLink: "https://a.com/1", sourceTitle: "A",
            targetLink: "https://b.com/2", targetTitle: "B",
            type: .relatedTo
        )!
        XCTAssertTrue(mapper.removeRelationship(id: rel.id))
        XCTAssertEqual(mapper.count, 0)
    }

    func testRemoveNonexistentReturnsFalse() {
        XCTAssertFalse(mapper.removeRelationship(id: "nonexistent"))
    }

    func testRemoveAllRelationshipsForArticle() {
        mapper.addRelationship(
            sourceLink: "https://a.com/1", sourceTitle: "A",
            targetLink: "https://b.com/2", targetTitle: "B",
            type: .buildsOn
        )
        mapper.addRelationship(
            sourceLink: "https://c.com/3", sourceTitle: "C",
            targetLink: "https://a.com/1", targetTitle: "A",
            type: .supplements
        )
        mapper.addRelationship(
            sourceLink: "https://b.com/2", sourceTitle: "B",
            targetLink: "https://c.com/3", targetTitle: "C",
            type: .relatedTo
        )
        XCTAssertEqual(mapper.count, 3)

        let removed = mapper.removeAllRelationships(forArticle: "https://a.com/1")
        XCTAssertEqual(removed, 2)
        XCTAssertEqual(mapper.count, 1)
    }

    // MARK: - Update

    func testUpdateRelationship() {
        let rel = mapper.addRelationship(
            sourceLink: "https://a.com/1", sourceTitle: "A",
            targetLink: "https://b.com/2", targetTitle: "B",
            type: .relatedTo,
            strength: .weak
        )!
        let updated = mapper.updateRelationship(
            id: rel.id,
            type: .buildsOn,
            strength: .strong,
            note: "Updated note"
        )
        XCTAssertNotNil(updated)
        XCTAssertEqual(updated?.type, .buildsOn)
        XCTAssertEqual(updated?.strength, .strong)
        XCTAssertEqual(updated?.note, "Updated note")
    }

    func testUpdateNonexistentReturnsNil() {
        let result = mapper.updateRelationship(id: "fake", type: .refutes)
        XCTAssertNil(result)
    }

    // MARK: - Queries

    func testOutgoingRelationships() {
        mapper.addRelationship(
            sourceLink: "https://a.com/1", sourceTitle: "A",
            targetLink: "https://b.com/2", targetTitle: "B",
            type: .buildsOn
        )
        mapper.addRelationship(
            sourceLink: "https://a.com/1", sourceTitle: "A",
            targetLink: "https://c.com/3", targetTitle: "C",
            type: .supplements
        )
        mapper.addRelationship(
            sourceLink: "https://b.com/2", sourceTitle: "B",
            targetLink: "https://a.com/1", targetTitle: "A",
            type: .refutes
        )

        let outgoing = mapper.outgoingRelationships(forArticle: "https://a.com/1")
        XCTAssertEqual(outgoing.count, 2)
    }

    func testIncomingRelationships() {
        mapper.addRelationship(
            sourceLink: "https://b.com/2", sourceTitle: "B",
            targetLink: "https://a.com/1", targetTitle: "A",
            type: .buildsOn
        )
        mapper.addRelationship(
            sourceLink: "https://c.com/3", sourceTitle: "C",
            targetLink: "https://a.com/1", targetTitle: "A",
            type: .supplements
        )

        let incoming = mapper.incomingRelationships(forArticle: "https://a.com/1")
        XCTAssertEqual(incoming.count, 2)
    }

    func testNeighbors() {
        mapper.addRelationship(
            sourceLink: "https://a.com/1", sourceTitle: "A",
            targetLink: "https://b.com/2", targetTitle: "B",
            type: .buildsOn
        )
        mapper.addRelationship(
            sourceLink: "https://c.com/3", sourceTitle: "C",
            targetLink: "https://a.com/1", targetTitle: "A",
            type: .updates
        )

        let neighbors = mapper.neighbors(ofArticle: "https://a.com/1")
        XCTAssertEqual(neighbors.count, 2)

        let links = Set(neighbors.map { $0.link })
        XCTAssertTrue(links.contains("https://b.com/2"))
        XCTAssertTrue(links.contains("https://c.com/3"))
    }

    func testRelationshipsByType() {
        mapper.addRelationship(
            sourceLink: "https://a.com/1", sourceTitle: "A",
            targetLink: "https://b.com/2", targetTitle: "B",
            type: .buildsOn
        )
        mapper.addRelationship(
            sourceLink: "https://c.com/3", sourceTitle: "C",
            targetLink: "https://d.com/4", targetTitle: "D",
            type: .buildsOn
        )
        mapper.addRelationship(
            sourceLink: "https://a.com/1", sourceTitle: "A",
            targetLink: "https://c.com/3", targetTitle: "C",
            type: .refutes
        )

        XCTAssertEqual(mapper.relationships(ofType: .buildsOn).count, 2)
        XCTAssertEqual(mapper.relationships(ofType: .refutes).count, 1)
        XCTAssertEqual(mapper.relationships(ofType: .supplements).count, 0)
    }

    func testRelationshipsByMinStrength() {
        mapper.addRelationship(
            sourceLink: "https://a.com/1", sourceTitle: "A",
            targetLink: "https://b.com/2", targetTitle: "B",
            type: .relatedTo, strength: .weak
        )
        mapper.addRelationship(
            sourceLink: "https://c.com/3", sourceTitle: "C",
            targetLink: "https://d.com/4", targetTitle: "D",
            type: .buildsOn, strength: .strong
        )
        mapper.addRelationship(
            sourceLink: "https://e.com/5", sourceTitle: "E",
            targetLink: "https://f.com/6", targetTitle: "F",
            type: .supplements, strength: .moderate
        )

        XCTAssertEqual(mapper.relationships(minStrength: .strong).count, 1)
        XCTAssertEqual(mapper.relationships(minStrength: .moderate).count, 2)
        XCTAssertEqual(mapper.relationships(minStrength: .weak).count, 3)
    }

    func testSearchByNote() {
        mapper.addRelationship(
            sourceLink: "https://a.com/1", sourceTitle: "A",
            targetLink: "https://b.com/2", targetTitle: "B",
            type: .contradictsBy,
            note: "Uses different methodology for the same dataset"
        )
        mapper.addRelationship(
            sourceLink: "https://c.com/3", sourceTitle: "C",
            targetLink: "https://d.com/4", targetTitle: "D",
            type: .buildsOn,
            note: "Extends the algorithm with GPU support"
        )

        XCTAssertEqual(mapper.searchByNote(query: "methodology").count, 1)
        XCTAssertEqual(mapper.searchByNote(query: "GPU").count, 1)
        XCTAssertEqual(mapper.searchByNote(query: "nonexistent").count, 0)
    }

    func testConnectionCount() {
        mapper.addRelationship(
            sourceLink: "https://a.com/1", sourceTitle: "A",
            targetLink: "https://b.com/2", targetTitle: "B",
            type: .buildsOn
        )
        mapper.addRelationship(
            sourceLink: "https://a.com/1", sourceTitle: "A",
            targetLink: "https://c.com/3", targetTitle: "C",
            type: .supplements
        )
        mapper.addRelationship(
            sourceLink: "https://d.com/4", sourceTitle: "D",
            targetLink: "https://a.com/1", targetTitle: "A",
            type: .refutes
        )

        XCTAssertEqual(mapper.connectionCount(forArticle: "https://a.com/1"), 3)
        XCTAssertEqual(mapper.connectionCount(forArticle: "https://b.com/2"), 1)
        XCTAssertEqual(mapper.connectionCount(forArticle: "https://nonexistent.com"), 0)
    }

    // MARK: - Graph Analysis

    func testFindClusters() {
        mapper.addRelationship(
            sourceLink: "https://a.com/1", sourceTitle: "A",
            targetLink: "https://b.com/2", targetTitle: "B",
            type: .buildsOn
        )
        mapper.addRelationship(
            sourceLink: "https://b.com/2", sourceTitle: "B",
            targetLink: "https://c.com/3", targetTitle: "C",
            type: .supplements
        )
        mapper.addRelationship(
            sourceLink: "https://d.com/4", sourceTitle: "D",
            targetLink: "https://e.com/5", targetTitle: "E",
            type: .relatedTo
        )

        let clusters = mapper.findClusters()
        XCTAssertEqual(clusters.count, 2)
        XCTAssertEqual(clusters[0].count, 3)
        XCTAssertEqual(clusters[1].count, 2)
    }

    func testComputeStats() {
        mapper.addRelationship(
            sourceLink: "https://a.com/1", sourceTitle: "A",
            targetLink: "https://b.com/2", targetTitle: "B",
            type: .buildsOn, strength: .strong
        )
        mapper.addRelationship(
            sourceLink: "https://a.com/1", sourceTitle: "A",
            targetLink: "https://c.com/3", targetTitle: "C",
            type: .supplements, strength: .weak
        )

        let stats = mapper.computeStats()
        XCTAssertEqual(stats.totalRelationships, 2)
        XCTAssertEqual(stats.uniqueArticles, 3)
        XCTAssertEqual(stats.typeDistribution[.buildsOn], 1)
        XCTAssertEqual(stats.typeDistribution[.supplements], 1)
        XCTAssertEqual(stats.strengthDistribution[.strong], 1)
        XCTAssertEqual(stats.strengthDistribution[.weak], 1)
        XCTAssertEqual(stats.mostConnected?.link, "https://a.com/1")
        XCTAssertEqual(stats.mostConnected?.count, 2)
        XCTAssertEqual(stats.clusterCount, 1)
    }

    func testEmptyGraphStats() {
        let stats = mapper.computeStats()
        XCTAssertEqual(stats.totalRelationships, 0)
        XCTAssertEqual(stats.uniqueArticles, 0)
        XCTAssertNil(stats.mostConnected)
        XCTAssertEqual(stats.averageConnections, 0.0)
        XCTAssertEqual(stats.clusterCount, 0)
    }

    // MARK: - Export / Import

    func testExportImportJSON() {
        mapper.addRelationship(
            sourceLink: "https://a.com/1", sourceTitle: "Article A",
            targetLink: "https://b.com/2", targetTitle: "Article B",
            type: .buildsOn, strength: .strong, note: "Key insight"
        )
        mapper.addRelationship(
            sourceLink: "https://c.com/3", sourceTitle: "Article C",
            targetLink: "https://d.com/4", targetTitle: "Article D",
            type: .contradictsBy
        )

        guard let jsonData = mapper.exportJSON() else {
            XCTFail("Export returned nil")
            return
        }

        let mapper2 = ArticleRelationshipMapper()
        mapper2.removeAll()
        let imported = mapper2.importJSON(data: jsonData)
        XCTAssertEqual(imported, 2)
        XCTAssertEqual(mapper2.count, 2)

        let rels = mapper2.allRelationships
        let types = Set(rels.map { $0.type })
        XCTAssertTrue(types.contains(.buildsOn))
        XCTAssertTrue(types.contains(.contradictsBy))

        mapper2.removeAll()
    }

    func testImportSkipsDuplicates() {
        mapper.addRelationship(
            sourceLink: "https://a.com/1", sourceTitle: "A",
            targetLink: "https://b.com/2", targetTitle: "B",
            type: .buildsOn
        )

        guard let jsonData = mapper.exportJSON() else {
            XCTFail("Export returned nil")
            return
        }

        let imported = mapper.importJSON(data: jsonData, skipDuplicates: true)
        XCTAssertEqual(imported, 0)
        XCTAssertEqual(mapper.count, 1)
    }

    func testExportJSONString() {
        mapper.addRelationship(
            sourceLink: "https://a.com/1", sourceTitle: "A",
            targetLink: "https://b.com/2", targetTitle: "B",
            type: .relatedTo
        )
        let jsonString = mapper.exportJSONString()
        XCTAssertNotNil(jsonString)
        XCTAssertTrue(jsonString!.contains("related-to"))
    }

    // MARK: - Relationship Types

    func testRelationshipTypeProperties() {
        XCTAssertEqual(RelationshipType.contradictsBy.displayName, "Contradicts")
        XCTAssertEqual(RelationshipType.buildsOn.emoji, "🧱")
        XCTAssertTrue(RelationshipType.relatedTo.isSymmetric)
        XCTAssertFalse(RelationshipType.buildsOn.isSymmetric)
        XCTAssertEqual(RelationshipType.buildsOn.inverse, .inspiredBy)
        XCTAssertEqual(RelationshipType.inspiredBy.inverse, .buildsOn)
    }

    func testAllRelationshipTypesHaveDisplayNames() {
        for type in RelationshipType.allCases {
            XCTAssertFalse(type.displayName.isEmpty, "\(type) has empty displayName")
            XCTAssertFalse(type.emoji.isEmpty, "\(type) has empty emoji")
        }
    }

    // MARK: - Strength Comparison

    func testStrengthComparable() {
        XCTAssertTrue(RelationshipStrength.weak < .moderate)
        XCTAssertTrue(RelationshipStrength.moderate < .strong)
        XCTAssertFalse(RelationshipStrength.strong < .weak)
    }

    // MARK: - Custom Type

    func testCustomRelationshipType() {
        let rel = mapper.addRelationship(
            sourceLink: "https://a.com/1", sourceTitle: "A",
            targetLink: "https://b.com/2", targetTitle: "B",
            type: .custom,
            customLabel: "precursor-to"
        )
        XCTAssertEqual(rel?.type, .custom)
        XCTAssertEqual(rel?.customLabel, "precursor-to")
    }

    // MARK: - Remove All

    func testRemoveAll() {
        mapper.addRelationship(
            sourceLink: "https://a.com/1", sourceTitle: "A",
            targetLink: "https://b.com/2", targetTitle: "B",
            type: .buildsOn
        )
        mapper.addRelationship(
            sourceLink: "https://c.com/3", sourceTitle: "C",
            targetLink: "https://d.com/4", targetTitle: "D",
            type: .refutes
        )
        XCTAssertEqual(mapper.count, 2)

        mapper.removeAll()
        XCTAssertEqual(mapper.count, 0)
        XCTAssertTrue(mapper.allArticleLinks.isEmpty)
    }

    // MARK: - All Article Links

    func testAllArticleLinks() {
        mapper.addRelationship(
            sourceLink: "https://a.com/1", sourceTitle: "A",
            targetLink: "https://b.com/2", targetTitle: "B",
            type: .buildsOn
        )
        mapper.addRelationship(
            sourceLink: "https://b.com/2", sourceTitle: "B",
            targetLink: "https://c.com/3", targetTitle: "C",
            type: .supplements
        )
        let links = mapper.allArticleLinks
        XCTAssertEqual(links.count, 3)
        XCTAssertTrue(links.contains("https://a.com/1"))
        XCTAssertTrue(links.contains("https://b.com/2"))
        XCTAssertTrue(links.contains("https://c.com/3"))
    }

    // MARK: - Notification

    func testNotificationPostedOnAdd() {
        let expectation = XCTestExpectation(description: "Notification posted")
        let observer = NotificationCenter.default.addObserver(
            forName: .articleRelationshipsDidChange,
            object: nil,
            queue: nil
        ) { _ in
            expectation.fulfill()
        }

        mapper.addRelationship(
            sourceLink: "https://a.com/1", sourceTitle: "A",
            targetLink: "https://b.com/2", targetTitle: "B",
            type: .relatedTo
        )

        wait(for: [expectation], timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }
}
