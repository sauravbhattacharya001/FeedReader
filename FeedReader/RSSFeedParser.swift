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
    private var link = NSMutableString()
    private var imagePath = NSMutableString()

    /// Parse the given data synchronously on the calling thread.
    /// Returns the stories extracted from the feed.
    func parse(data: Data) -> [Story] {
        parsedStories = []
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = self
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
            link = NSMutableString()
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
        } else if currentElement.isEqual(to: "guid") {
            link.append(string)
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        guard (elementName as NSString).isEqual(to: "item") else { return }

        let trimmedImagePath = imagePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if let story = Story(
            title: storyTitle as String,
            photo: UIImage(named: "sample")!,
            description: storyDescription as String,
            link: link.components(separatedBy: "\n")[0],
            imagePath: trimmedImagePath.isEmpty ? nil : trimmedImagePath
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

    /// Cancels any in-progress load when a new one starts, so stale
    /// results from an old refresh don't overwrite a newer one.
    private var currentSession: URLSession?

    // MARK: - Public API

    /// Parse stories from multiple feed URLs concurrently.
    /// Calls delegate on the main thread when all feeds have completed.
    ///
    /// If a previous load is still in flight it is cancelled first,
    /// preventing stale data from arriving after the new request.
    func loadFeeds(_ urls: [String]) {
        guard !urls.isEmpty else {
            delegate?.parserDidFinishLoading(stories: [])
            return
        }

        // Cancel any in-progress load to avoid stale results.
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
            print("RSSFeedParser: invalid URL — \(url)")
            feedCompleted()
            return
        }

        let task = session.dataTask(with: feedURL) { [weak self] data, response, error in
            guard let self = self else { return }

            guard let data = data, error == nil else {
                if (error as? URLError)?.code == .cancelled { return }
                print("RSSFeedParser: fetch failed — \(error?.localizedDescription ?? "unknown")")
                self.feedCompleted()
                return
            }

            // Validate HTTP status
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                print("RSSFeedParser: HTTP \(httpResponse.statusCode)")
                self.feedCompleted()
                return
            }

            // Parse in an isolated context — no shared mutable state.
            let context = FeedParseContext()
            let feedStories = context.parse(data: data)

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

    /// Parse stories from local file data (for unit testing).
    /// Runs synchronously on the calling thread.
    func parseData(_ data: Data) -> [Story] {
        let context = FeedParseContext()
        return context.parse(data: data)
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
