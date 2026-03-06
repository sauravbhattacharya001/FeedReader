//
//  RSSFeedParser.swift
//  FeedReader
//
//  Extracted from StoryTableViewController to separate RSS parsing
//  concerns from the view controller. Handles XML parsing for
//  individual feeds and multi-feed aggregation with deduplication.
//
//  Fix: Each feed is now parsed using an isolated FeedParseContext that
//  owns its own XMLParser delegate state. A serial queue serializes all
//  mutations to the shared `stories` / `seenLinks` / `pendingFeedCount`
//  properties, eliminating the race condition described in issue #10.
//

import UIKit

/// Delegate notified when all requested feeds have finished loading.
protocol RSSFeedParserDelegate: AnyObject {
    func parserDidFinishLoading(stories: [Story])
    func parserDidFailWithError(_ error: Error?)
}

// MARK: - Per-Feed Parse Context

/// Isolates XML parsing state for a single feed so that concurrent
/// feeds never share mutable parsing buffers. Each context acts as its
/// own XMLParserDelegate, collecting stories into a local array that is
/// merged into the parent RSSFeedParser on the serial queue.
private class FeedParseContext: NSObject, XMLParserDelegate {

    /// Stories parsed from this single feed.
    private(set) var parsedStories: [Story] = []

    // Per-item XML parsing state — fully isolated per feed.
    private var currentElement: NSString = ""
    private var insideItem = false
    private var storyTitle = NSMutableString()
    private var storyDescription = NSMutableString()
    private var storyContentEncoded = NSMutableString()  // from <content:encoded> (full article body)
    private var storyLink = NSMutableString()  // from <link> element (preferred)
    private var storyGuid = NSMutableString()  // from <guid> element (fallback)
    private var imagePath = NSMutableString()

    /// Parse the given data synchronously on the calling thread.
    /// Returns the stories extracted from the feed.
    func parse(data: Data) -> [Story] {
        parsedStories = []
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = self
        xmlParser.shouldResolveExternalEntities = false  // Prevent XXE
        xmlParser.parse()
        return parsedStories
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {
        currentElement = elementName as NSString

        if (elementName as NSString).isEqual(to: "item") {
            insideItem = true
            storyTitle = NSMutableString()
            storyDescription = NSMutableString()
            storyContentEncoded = NSMutableString()
            storyLink = NSMutableString()
            storyGuid = NSMutableString()
            imagePath = NSMutableString()
        }

        // BBC RSS feeds use <media:thumbnail url="..."/> for images.
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
        } else if currentElement.isEqual(to: "link") {
            storyLink.append(string)
        } else if currentElement.isEqual(to: "guid") {
            storyGuid.append(string)
        } else if currentElement.isEqual(to: "content:encoded") || currentElement.isEqual(to: "encoded") {
            storyContentEncoded.append(string)
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        guard (elementName as NSString).isEqual(to: "item") else { return }

        // Prefer <link> for the article URL; fall back to <guid> which
        // may or may not be a permalink (fixes issue #11).
        let trimmedLink = storyLink.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGuid = storyGuid.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalLink = trimmedLink.isEmpty ? trimmedGuid : trimmedLink

        // Validate article link URL scheme at parse time (defense-in-depth).
        // Reject stories with unsafe schemes (javascript:, data:, file:, etc.)
        // before they reach BookmarkManager, ReadStatusManager, or share actions.
        let linkCandidate = finalLink.components(separatedBy: "\n")[0]
        guard Story.isSafeURL(linkCandidate) else {
            // Skip stories with unsafe links entirely
            storyTitle = NSMutableString()
            storyDescription = NSMutableString()
            storyContentEncoded = NSMutableString()
            storyLink = NSMutableString()
            storyGuid = NSMutableString()
            imagePath = NSMutableString()
            insideItem = false
            return
        }

        // Validate image path URL scheme — strip unsafe image URLs silently.
        let trimmedImagePath = imagePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedImagePath: String?
        if trimmedImagePath.isEmpty {
            sanitizedImagePath = nil
        } else if Story.isSafeURL(trimmedImagePath) {
            sanitizedImagePath = trimmedImagePath
        } else {
            sanitizedImagePath = nil  // Strip unsafe image URLs silently
        }

        // Prefer content:encoded (full article body) over description (often truncated)
        let trimmedContentEncoded = storyContentEncoded.trimmingCharacters(in: .whitespacesAndNewlines)
        let articleBody = trimmedContentEncoded.isEmpty ? storyDescription as String : trimmedContentEncoded

        if let story = Story(
            title: storyTitle as String,
            photo: UIImage(named: "sample")!,
            description: articleBody,
            link: linkCandidate,
            imagePath: sanitizedImagePath
        ) {
            parsedStories.append(story)
        }
        insideItem = false
    }
}

// MARK: - RSSFeedParser

class RSSFeedParser: NSObject {

    // MARK: - Properties

    weak var delegate: RSSFeedParserDelegate?

    /// Accumulated stories from all feeds being parsed.
    private(set) var stories: [Story] = []

    /// O(1) duplicate detection by link during multi-feed loading.
    private var seenLinks = Set<String>()

    /// Number of feeds still loading.
    private var pendingFeedCount = 0

    /// Serial queue that protects all mutable shared state (`stories`,
    /// `seenLinks`, `pendingFeedCount`). Network fetches and XML parsing
    /// still happen concurrently on URLSession threads; only the merge
    /// step is serialized.
    private let parseQueue = DispatchQueue(label: "com.feedreader.parseQueue")

    /// Reusable URL session for feed fetching. Created once and reused
    /// across loads to avoid the overhead of session creation (TLS
    /// session cache, connection pool, delegate setup) on every refresh.
    private lazy var feedSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()

    /// Generation counter to discard results from stale loads.
    private var loadGeneration: UInt64 = 0

    // MARK: - Public API

    /// Parse stories from multiple feed URLs concurrently.
    /// Calls delegate on the main thread when all feeds have completed.
    ///
    /// If a previous load is still in flight its results are discarded
    /// via the generation counter, without destroying the shared session.
    func loadFeeds(_ urls: [String]) {
        guard !urls.isEmpty else {
            delegate?.parserDidFinishLoading(stories: [])
            return
        }

        // Cancel in-flight data tasks (not the session itself) and
        // bump generation so any stragglers from the old load are ignored.
        feedSession.getAllTasks { tasks in
            for task in tasks { task.cancel() }
        }
        loadGeneration &+= 1
        let currentGeneration = loadGeneration

        let session = feedSession

        // Build URL→feedName map from enabled feeds for source attribution
        let enabledFeeds = FeedManager.shared.enabledFeeds
        var feedNameMap: [String: String] = [:]
        for feed in enabledFeeds {
            feedNameMap[feed.url] = feed.name
        }

        parseQueue.sync {
            stories = []
            seenLinks = Set<String>()
            pendingFeedCount = urls.count
        }

        for url in urls {
            let feedName = feedNameMap[url] ?? "Unknown"
            parseFeed(url, session: session, feedName: feedName, generation: currentGeneration)
        }
    }

    /// Parse stories from a single feed URL using the given session.
    private func parseFeed(_ url: String, session: URLSession, feedName: String, generation: UInt64) {
        guard let feedURL = URL(string: url) else {
            print("RSSFeedParser: invalid URL — \(url)")
            feedCompleted(generation: generation)
            return
        }

        let task = session.dataTask(with: feedURL) { [weak self] data, response, error in
            guard let self = self else { return }

            guard let data = data, error == nil else {
                if (error as? URLError)?.code == .cancelled { return }
                print("RSSFeedParser: fetch failed — \(error?.localizedDescription ?? "unknown")")
                self.feedCompleted(generation: generation)
                return
            }

            // Validate HTTP status
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                print("RSSFeedParser: HTTP \(httpResponse.statusCode)")
                self.feedCompleted(generation: generation)
                return
            }

            // Parse in an isolated context — no shared mutable state.
            let context = FeedParseContext()
            let feedStories = context.parse(data: data)

            // Merge results on the serial queue.
            self.parseQueue.async {
                // Discard if a newer load has started.
                guard self.loadGeneration == generation else { return }
                for story in feedStories {
                    if !self.seenLinks.contains(story.link) {
                        self.seenLinks.insert(story.link)
                        story.sourceFeedName = feedName
                        self.stories.append(story)
                    }
                }
                self.feedCompletedOnQueue()
            }
        }
        task.resume()
    }

    /// Parse stories from local file data (for unit testing).
    /// Runs synchronously on the calling thread.
    func parseData(_ data: Data) -> [Story] {
        let context = FeedParseContext()
        return context.parse(data: data)
    }

    // MARK: - Private

    /// Called from arbitrary threads — bounces to the serial queue.
    /// Includes the generation counter to discard completions from stale loads.
    private func feedCompleted(generation: UInt64) {
        parseQueue.async {
            guard self.loadGeneration == generation else { return }
            self.feedCompletedOnQueue()
        }
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
