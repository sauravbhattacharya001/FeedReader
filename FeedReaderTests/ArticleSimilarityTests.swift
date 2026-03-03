//
//  ArticleSimilarityTests.swift
//  FeedReaderTests
//
//  Tests for ArticleSimilarityManager — TF-IDF keyword similarity.
//

import XCTest
@testable import FeedReader

class ArticleSimilarityTests: XCTestCase {
    
    var manager: ArticleSimilarityManager!
    
    override func setUp() {
        super.setUp()
        manager = ArticleSimilarityManager()
    }
    
    override func tearDown() {
        manager.clearIndex()
        manager = nil
        super.tearDown()
    }
    
    // MARK: - Helpers
    
    private func makeStory(title: String, body: String, link: String, feed: String = "TestFeed") -> Story? {
        let story = Story(title: title, photo: nil, description: body, link: link)
        story?.sourceFeedName = feed
        return story
    }
    
    // MARK: - Indexing Tests
    
    func testIndexSingleStory() {
        let story = makeStory(title: "Swift Programming Guide", body: "Learn Swift programming language basics and advanced features", link: "https://example.com/swift")!
        manager.index(story: story)
        XCTAssertEqual(manager.documentCount, 1)
        XCTAssertGreaterThan(manager.termCount, 0)
    }
    
    func testIndexMultipleStories() {
        let stories = [
            makeStory(title: "Python Tutorial", body: "Python programming basics", link: "https://example.com/1")!,
            makeStory(title: "Java Guide", body: "Java programming fundamentals", link: "https://example.com/2")!,
            makeStory(title: "Rust Overview", body: "Rust systems programming language", link: "https://example.com/3")!
        ]
        manager.indexAll(stories: stories)
        XCTAssertEqual(manager.documentCount, 3)
    }
    
    func testRemoveFromIndex() {
        let story = makeStory(title: "Test Article", body: "Some content here", link: "https://example.com/test")!
        manager.index(story: story)
        XCTAssertEqual(manager.documentCount, 1)
        
        manager.remove(link: "https://example.com/test")
        XCTAssertEqual(manager.documentCount, 0)
    }
    
    func testReindexUpdatesDocument() {
        let story = makeStory(title: "Original Title", body: "Original content", link: "https://example.com/1")!
        manager.index(story: story)
        XCTAssertEqual(manager.documentCount, 1)
        
        // Re-index same link with different content
        let updated = makeStory(title: "Updated Title", body: "Updated content entirely", link: "https://example.com/1")!
        manager.index(story: updated)
        XCTAssertEqual(manager.documentCount, 1)  // Should still be 1
    }
    
    // MARK: - Similarity Tests
    
    func testSimilarArticlesFound() {
        let s1 = makeStory(title: "Machine Learning Basics", body: "Introduction to machine learning algorithms and neural networks", link: "https://example.com/ml1", feed: "AI Blog")!
        let s2 = makeStory(title: "Deep Learning Neural Networks", body: "Advanced neural networks and machine learning techniques", link: "https://example.com/ml2", feed: "Tech News")!
        let s3 = makeStory(title: "Cooking Italian Pasta", body: "How to make perfect pasta with tomato sauce", link: "https://example.com/food", feed: "Food Blog")!
        
        manager.indexAll(stories: [s1, s2, s3])
        
        let similar = manager.findSimilar(to: s1)
        
        // ML article should be more similar than cooking
        XCTAssertFalse(similar.isEmpty)
        if let first = similar.first {
            XCTAssertEqual(first.story.link, "https://example.com/ml2")
        }
    }
    
    func testExcludeSameFeed() {
        let s1 = makeStory(title: "AI News Today", body: "Artificial intelligence updates", link: "https://example.com/1", feed: "AI Blog")!
        let s2 = makeStory(title: "AI Research Papers", body: "New artificial intelligence research", link: "https://example.com/2", feed: "AI Blog")!
        let s3 = makeStory(title: "AI Industry Trends", body: "Artificial intelligence in business", link: "https://example.com/3", feed: "Tech News")!
        
        manager.indexAll(stories: [s1, s2, s3])
        
        let withSameFeed = manager.findSimilar(to: s1, excludeSameFeed: false)
        let withoutSameFeed = manager.findSimilar(to: s1, excludeSameFeed: true)
        
        XCTAssertGreaterThanOrEqual(withSameFeed.count, withoutSameFeed.count)
        
        // When excluding same feed, no results should be from "AI Blog"
        for result in withoutSameFeed {
            XCTAssertNotEqual(result.story.sourceFeedName, "AI Blog")
        }
    }
    
    func testSimilarityScoreRange() {
        let s1 = makeStory(title: "Programming Languages", body: "Comparing modern programming languages", link: "https://example.com/1")!
        let s2 = makeStory(title: "Language Comparison", body: "Programming language features compared", link: "https://example.com/2")!
        
        manager.indexAll(stories: [s1, s2])
        
        let similar = manager.findSimilar(to: s1)
        for result in similar {
            XCTAssertGreaterThanOrEqual(result.score, 0.0)
            XCTAssertLessThanOrEqual(result.score, 1.0)
        }
    }
    
    func testSharedKeywordsReturned() {
        let s1 = makeStory(title: "Kubernetes Deployment", body: "Deploy containers using kubernetes orchestration", link: "https://example.com/1")!
        let s2 = makeStory(title: "Container Orchestration", body: "Kubernetes container deployment strategies", link: "https://example.com/2")!
        
        manager.indexAll(stories: [s1, s2])
        
        let similar = manager.findSimilar(to: s1)
        if let first = similar.first {
            XCTAssertFalse(first.sharedKeywords.isEmpty)
        }
    }
    
    // MARK: - Text Query Tests
    
    func testFindSimilarToText() {
        let s1 = makeStory(title: "Weather Forecast Today", body: "Rain expected in Seattle area tomorrow", link: "https://example.com/weather")!
        let s2 = makeStory(title: "Stock Market Update", body: "Markets rally on economic data", link: "https://example.com/stocks")!
        
        manager.indexAll(stories: [s1, s2])
        
        let results = manager.findSimilar(toText: "Seattle weather rain forecast")
        if !results.isEmpty {
            XCTAssertEqual(results.first?.story.link, "https://example.com/weather")
        }
    }
    
    // MARK: - Clustering Tests
    
    func testClusterArticles() {
        let stories = [
            makeStory(title: "Python Machine Learning", body: "Machine learning with Python and scikit-learn", link: "https://example.com/1")!,
            makeStory(title: "Python Deep Learning", body: "Deep learning neural networks in Python", link: "https://example.com/2")!,
            makeStory(title: "Italian Cooking Recipes", body: "Traditional Italian pasta and pizza recipes", link: "https://example.com/3")!,
            makeStory(title: "Mediterranean Diet", body: "Italian food and Mediterranean cooking guide", link: "https://example.com/4")!,
        ]
        
        manager.indexAll(stories: stories)
        let clusters = manager.clusterArticles(threshold: 0.1)
        
        XCTAssertGreaterThan(clusters.count, 0)
        // Total links across clusters should equal document count
        let totalLinks = clusters.reduce(0) { $0 + $1.count }
        XCTAssertEqual(totalLinks, 4)
    }
    
    func testClusterKeywords() {
        let stories = [
            makeStory(title: "Swift iOS Development", body: "Building iOS apps with Swift programming", link: "https://example.com/1")!,
            makeStory(title: "iOS App Tutorial", body: "Swift tutorial for iOS development beginners", link: "https://example.com/2")!,
        ]
        
        manager.indexAll(stories: stories)
        let clusters = manager.clusterArticles(threshold: 0.05)
        
        if let firstCluster = clusters.first, firstCluster.count > 1 {
            let keywords = manager.clusterKeywords(links: firstCluster)
            XCTAssertFalse(keywords.isEmpty)
        }
    }
    
    // MARK: - Edge Cases
    
    func testEmptyIndex() {
        let story = makeStory(title: "Test", body: "Some content", link: "https://example.com/1")!
        let similar = manager.findSimilar(to: story)
        XCTAssertTrue(similar.isEmpty)
    }
    
    func testClearIndex() {
        let story = makeStory(title: "Test", body: "Some content", link: "https://example.com/1")!
        manager.index(story: story)
        XCTAssertEqual(manager.documentCount, 1)
        
        manager.clearIndex()
        XCTAssertEqual(manager.documentCount, 0)
        XCTAssertEqual(manager.termCount, 0)
    }
    
    func testThresholdFiltering() {
        let s1 = makeStory(title: "Quantum Computing", body: "Quantum bits and quantum gates", link: "https://example.com/1")!
        let s2 = makeStory(title: "Classical Computing", body: "Traditional CPU architecture", link: "https://example.com/2")!
        
        manager.indexAll(stories: [s1, s2])
        
        let lowThreshold = manager.findSimilar(to: s1, threshold: 0.01)
        let highThreshold = manager.findSimilar(to: s1, threshold: 0.99)
        
        XCTAssertGreaterThanOrEqual(lowThreshold.count, highThreshold.count)
    }
    
    func testLimitParameter() {
        var stories: [Story] = []
        for i in 0..<20 {
            if let s = makeStory(title: "Programming Language \(i)", body: "Programming language features and syntax guide number \(i)", link: "https://example.com/\(i)") {
                stories.append(s)
            }
        }
        manager.indexAll(stories: stories)
        
        let limited = manager.findSimilar(to: stories[0], limit: 3)
        XCTAssertLessThanOrEqual(limited.count, 3)
    }
}
