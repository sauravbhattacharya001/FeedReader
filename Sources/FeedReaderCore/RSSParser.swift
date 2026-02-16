//
//  RSSParser.swift
//  FeedReaderCore
//
//  Handles XML parsing of RSS feeds. Supports concurrent multi-feed
//  loading with deduplication. Platform-independent (no UIKit dependency).
//
//  Fix: XML parsing state is now fully isolated per feed via
//  `RSSParseCollector`. A serial DispatchQueue replaces the NSLock for
//  shared-state protection, and in-flight loads are cancelled when a
//  new `loadFeeds` call arrives (prevents stale data from old refreshes).
//  Addresses issue #10 (race condition in concurrent RSS parsing).
//

import Foundation

/// Delegate notified when RSS feed parsing completes.
public protocol RSSParserDelegate: AnyObject {
    /// Called when all requested feeds have finished loading.
    func parserDidFinishLoading(stories: [RSSStory])

    /// Called when a feed fails to load.
    func parserDidFailWithError(_ error: Error?)
}

// MARK: - Per-Feed Parse Collector

/// Isolates XML parsing state for a single feed so that concurrent
/// feeds never share mutable parsing buffers. Each collector acts as
/// its own `XMLParserDelegate`.
private class RSSParseCollector: NSObject, XMLParserDelegate {

    var stories: [RSSStory] = []

    private var currentElement: NSString = ""
    private var insideItem = false
    private var storyTitle = NSMutableString()
    private var storyDescription = NSMutableString()
    private var link = NSMutableString()
    private var imagePath = NSMutableString()

    /// Parse data synchronously, returning extracted stories.
    func parse(data: Data) -> [RSSStory] {
        stories = []
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = self
        xmlParser.parse()
        return stories
    }

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

// MARK: - RSSParser

/// Parses RSS XML feeds into `RSSStory` objects.
///
/// Supports loading multiple feeds concurrently with O(1) deduplication
/// by link URL. Thread-safe: all shared state mutations are serialized
/// on an internal serial queue, and each feed's XML parsing runs in an
/// isolated `RSSParseCollector`.
///
/// ## Usage
/// ```swift
/// let parser = RSSParser()
/// parser.delegate = self
/// parser.loadFeeds(["https://feeds.bbci.co.uk/news/world/rss.xml"])
/// ```
public class RSSParser: NSObject {

    // MARK: - Properties

    /// Delegate to receive parsing results.
    public weak var delegate: RSSParserDelegate?

    /// Accumulated stories from all feeds being parsed.
    public private(set) var stories: [RSSStory] = []

    /// O(1) duplicate detection by link.
    private var seenLinks = Set<String>()

    /// Number of feeds still loading.
    private var pendingFeedCount = 0

    /// Serial queue protecting all mutable shared state.
    private let parseQueue = DispatchQueue(label: "com.feedreadercore.parseQueue")

    /// Cancels in-flight loads when a new `loadFeeds` call arrives.
    private var currentSession: URLSession?

    // MARK: - Public API

    public override init() {
        super.init()
    }

    /// Parse stories from multiple feed URLs concurrently.
    /// Calls delegate on the main thread when all feeds have completed.
    ///
    /// Any in-flight load from a previous call is cancelled first.
    /// - Parameter urls: Array of RSS feed URL strings.
    public func loadFeeds(_ urls: [String]) {
        guard !urls.isEmpty else {
            delegate?.parserDidFinishLoading(stories: [])
            return
        }

        // Cancel any previous in-flight session.
        currentSession?.invalidateAndCancel()

        let session = URLSession(configuration: .default)
        currentSession = session

        parseQueue.sync {
            stories = []
            seenLinks = Set<String>()
            pendingFeedCount = urls.count
        }

        for url in urls {
            parseFeed(url, session: session)
        }
    }

    /// Parse stories from a single feed URL using the given session.
    private func parseFeed(_ url: String, session: URLSession) {
        guard let feedURL = URL(string: url) else {
            feedCompleted()
            return
        }

        let task = session.dataTask(with: feedURL) { [weak self] data, response, error in
            guard let self = self else { return }

            guard let data = data, error == nil else {
                if (error as? URLError)?.code == .cancelled { return }
                self.feedCompleted()
                return
            }

            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                self.feedCompleted()
                return
            }

            // Parse in isolated context — no shared mutable state.
            let collector = RSSParseCollector()
            let feedStories = collector.parse(data: data)

            // Merge results on the serial queue.
            self.parseQueue.async {
                for story in feedStories {
                    if !self.seenLinks.contains(story.link) {
                        self.seenLinks.insert(story.link)
                        self.stories.append(story)
                    }
                }
                self.feedCompletedOnQueue()
            }
        }
        task.resume()
    }

    /// Parse stories from in-memory XML data (useful for testing).
    /// Runs synchronously on the calling thread.
    /// - Parameter data: RSS XML data.
    /// - Returns: Array of parsed stories.
    public func parseData(_ data: Data) -> [RSSStory] {
        let collector = RSSParseCollector()
        return collector.parse(data: data)
    }

    // MARK: - Private

    /// Called from arbitrary threads — bounces to the serial queue.
    private func feedCompleted() {
        parseQueue.async { self.feedCompletedOnQueue() }
    }

    /// Must be called on `parseQueue`.
    private func feedCompletedOnQueue() {
        pendingFeedCount -= 1
        if pendingFeedCount <= 0 {
            let finalStories = stories
            DispatchQueue.main.async {
                self.delegate?.parserDidFinishLoading(stories: finalStories)
            }
        }
    }
}
