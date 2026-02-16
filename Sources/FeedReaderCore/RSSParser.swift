//
//  RSSParser.swift
//  FeedReaderCore
//
//  Handles XML parsing of RSS feeds. Supports concurrent multi-feed
//  loading with deduplication. Platform-independent (no UIKit dependency).
//

import Foundation

/// Delegate notified when RSS feed parsing completes.
public protocol RSSParserDelegate: AnyObject {
    /// Called when all requested feeds have finished loading.
    func parserDidFinishLoading(stories: [RSSStory])

    /// Called when a feed fails to load.
    func parserDidFailWithError(_ error: Error?)
}

/// Parses RSS XML feeds into `RSSStory` objects.
///
/// Supports loading multiple feeds concurrently with O(1) deduplication
/// by link URL. Thread-safe for concurrent feed loading.
///
/// ## Usage
/// ```swift
/// let parser = RSSParser()
/// parser.delegate = self
/// parser.loadFeeds(["https://feeds.bbci.co.uk/news/world/rss.xml"])
/// ```
public class RSSParser: NSObject, XMLParserDelegate {

    // MARK: - Properties

    /// Delegate to receive parsing results.
    public weak var delegate: RSSParserDelegate?

    /// Accumulated stories from all feeds being parsed.
    public private(set) var stories: [RSSStory] = []

    /// O(1) duplicate detection by link.
    private var seenLinks = Set<String>()

    /// Number of feeds still loading.
    private var pendingFeedCount = 0

    /// Lock for thread-safe access to shared state during concurrent parsing.
    private let lock = NSLock()

    // XML parsing state (per-parse, not thread-safe — each parse runs serially)
    private var currentElement: NSString = ""
    private var insideItem = false
    private var storyTitle = NSMutableString()
    private var storyDescription = NSMutableString()
    private var link = NSMutableString()
    private var imagePath = NSMutableString()

    // MARK: - Public API

    public override init() {
        super.init()
    }

    /// Parse stories from multiple feed URLs concurrently.
    /// Calls delegate when all feeds have completed.
    /// - Parameter urls: Array of RSS feed URL strings.
    public func loadFeeds(_ urls: [String]) {
        guard !urls.isEmpty else {
            delegate?.parserDidFinishLoading(stories: [])
            return
        }

        lock.lock()
        stories = []
        seenLinks = Set<String>()
        pendingFeedCount = urls.count
        lock.unlock()

        for url in urls {
            parseFeed(url)
        }
    }

    /// Parse stories from a single feed URL.
    /// - Parameter url: RSS feed URL string.
    public func parseFeed(_ url: String) {
        guard let feedURL = URL(string: url) else {
            feedCompleted()
            return
        }

        let task = URLSession.shared.dataTask(with: feedURL) { [weak self] data, response, error in
            guard let self = self else { return }

            guard let data = data, error == nil else {
                DispatchQueue.main.async { self.feedCompleted() }
                return
            }

            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                DispatchQueue.main.async { self.feedCompleted() }
                return
            }

            // Parse on background thread, then report on main
            let parsed = self.parseData(data)
            self.lock.lock()
            for story in parsed {
                if !self.seenLinks.contains(story.link) {
                    self.seenLinks.insert(story.link)
                    self.stories.append(story)
                }
            }
            self.lock.unlock()

            DispatchQueue.main.async { self.feedCompleted() }
        }
        task.resume()
    }

    /// Parse stories from in-memory XML data (useful for testing).
    /// - Parameter data: RSS XML data.
    /// - Returns: Array of parsed stories.
    public func parseData(_ data: Data) -> [RSSStory] {
        // Reset per-parse state
        var localStories: [RSSStory] = []
        var localSeenLinks = Set<String>()

        currentElement = ""
        insideItem = false

        let xmlParser = XMLParser(data: data)
        // Use a temporary delegate proxy to collect results without shared state issues
        let collector = ParserCollector()
        xmlParser.delegate = collector
        xmlParser.parse()

        for story in collector.stories {
            if !localSeenLinks.contains(story.link) {
                localSeenLinks.insert(story.link)
                localStories.append(story)
            }
        }

        return localStories
    }

    // MARK: - XMLParserDelegate

    public func parser(_ parser: XMLParser, didStartElement elementName: String,
                       namespaceURI: String?, qualifiedName qName: String?,
                       attributes attributeDict: [String: String]) {
        currentElement = elementName as NSString

        if elementName == "item" {
            insideItem = true
            storyTitle = NSMutableString()
            storyDescription = NSMutableString()
            link = NSMutableString()
            imagePath = NSMutableString()
        }

        if insideItem && (elementName == "media:thumbnail" || elementName == "enclosure") {
            if let urlAttr = attributeDict["url"], !urlAttr.isEmpty, imagePath.length == 0 {
                imagePath.setString(urlAttr)
            }
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideItem else { return }

        if currentElement.isEqual(to: "title") {
            storyTitle.append(string)
        } else if currentElement.isEqual(to: "description") {
            storyDescription.append(string)
        } else if currentElement.isEqual(to: "guid") {
            link.append(string)
        }
    }

    public func parser(_ parser: XMLParser, didEndElement elementName: String,
                       namespaceURI: String?, qualifiedName qName: String?) {
        guard elementName == "item" else { return }

        let trimmedImagePath = imagePath.trimmingCharacters(in: .whitespacesAndNewlines)

        if let story = RSSStory(
            title: storyTitle as String,
            body: storyDescription as String,
            link: link.components(separatedBy: "\n")[0],
            imagePath: trimmedImagePath.isEmpty ? nil : trimmedImagePath
        ) {
            lock.lock()
            if !seenLinks.contains(story.link) {
                seenLinks.insert(story.link)
                stories.append(story)
            }
            lock.unlock()
        }
        insideItem = false
    }

    // MARK: - Private

    private func feedCompleted() {
        lock.lock()
        pendingFeedCount -= 1
        let remaining = pendingFeedCount
        let currentStories = stories
        lock.unlock()

        if remaining <= 0 {
            delegate?.parserDidFinishLoading(stories: currentStories)
        }
    }
}

// MARK: - ParserCollector

/// Internal helper that collects parsed stories from a single XML parse pass.
/// Used by `parseData(_:)` to avoid shared state issues.
private class ParserCollector: NSObject, XMLParserDelegate {

    var stories: [RSSStory] = []

    private var currentElement: NSString = ""
    private var insideItem = false
    private var storyTitle = NSMutableString()
    private var storyDescription = NSMutableString()
    private var link = NSMutableString()
    private var imagePath = NSMutableString()

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {
        currentElement = elementName as NSString

        if elementName == "item" {
            insideItem = true
            storyTitle = NSMutableString()
            storyDescription = NSMutableString()
            link = NSMutableString()
            imagePath = NSMutableString()
        }

        if insideItem && (elementName == "media:thumbnail" || elementName == "enclosure") {
            if let urlAttr = attributeDict["url"], !urlAttr.isEmpty, imagePath.length == 0 {
                imagePath.setString(urlAttr)
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideItem else { return }

        if currentElement.isEqual(to: "title") {
            storyTitle.append(string)
        } else if currentElement.isEqual(to: "description") {
            storyDescription.append(string)
        } else if currentElement.isEqual(to: "guid") {
            link.append(string)
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        guard elementName == "item" else { return }

        let trimmedImagePath = imagePath.trimmingCharacters(in: .whitespacesAndNewlines)

        if let story = RSSStory(
            title: storyTitle as String,
            body: storyDescription as String,
            link: link.components(separatedBy: "\n")[0],
            imagePath: trimmedImagePath.isEmpty ? nil : trimmedImagePath
        ) {
            stories.append(story)
        }
        insideItem = false
    }
}
