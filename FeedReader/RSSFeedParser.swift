//
//  RSSFeedParser.swift
//  FeedReader
//
//  Extracted from StoryTableViewController to separate RSS parsing
//  concerns from the view controller. Handles XML parsing for
//  individual feeds and multi-feed aggregation with deduplication.
//

import UIKit

/// Delegate notified when all requested feeds have finished loading.
protocol RSSFeedParserDelegate: AnyObject {
    func parserDidFinishLoading(stories: [Story])
    func parserDidFailWithError(_ error: Error?)
}

class RSSFeedParser: NSObject, XMLParserDelegate {

    // MARK: - Properties

    weak var delegate: RSSFeedParserDelegate?

    /// Accumulated stories from all feeds being parsed.
    private(set) var stories: [Story] = []

    /// O(1) duplicate detection by link during multi-feed loading.
    private var seenLinks = Set<String>()

    /// Number of feeds still loading.
    private var pendingFeedCount = 0

    // XML parsing state
    private var currentElement: NSString = ""
    private var insideItem = false
    private var storyTitle = NSMutableString()
    private var storyDescription = NSMutableString()
    private var link = NSMutableString()
    private var imagePath = NSMutableString()

    // MARK: - Public API

    /// Parse stories from multiple feed URLs concurrently.
    /// Calls delegate when all feeds have completed.
    func loadFeeds(_ urls: [String]) {
        guard !urls.isEmpty else {
            delegate?.parserDidFinishLoading(stories: [])
            return
        }

        stories = []
        seenLinks = Set<String>()
        pendingFeedCount = urls.count

        for url in urls {
            parseFeed(url)
        }
    }

    /// Parse stories from a single feed URL.
    func parseFeed(_ url: String) {
        guard let feedURL = URL(string: url) else {
            print("RSSFeedParser: invalid URL — \(url)")
            feedCompleted()
            return
        }

        let task = URLSession.shared.dataTask(with: feedURL) { [weak self] data, response, error in
            guard let self = self else { return }

            guard let data = data, error == nil else {
                print("RSSFeedParser: fetch failed — \(error?.localizedDescription ?? "unknown")")
                DispatchQueue.main.async { self.feedCompleted() }
                return
            }

            // Validate HTTP status
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                print("RSSFeedParser: HTTP \(httpResponse.statusCode)")
                DispatchQueue.main.async { self.feedCompleted() }
                return
            }

            let xmlParser = XMLParser(data: data)
            xmlParser.delegate = self
            xmlParser.parse()

            DispatchQueue.main.async { self.feedCompleted() }
        }
        task.resume()
    }

    /// Parse stories from local file data (for unit testing).
    func parseData(_ data: Data) -> [Story] {
        stories = []
        seenLinks = Set<String>()
        pendingFeedCount = 1

        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = self
        xmlParser.parse()

        pendingFeedCount = 0
        return stories
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
            if !seenLinks.contains(story.link) {
                seenLinks.insert(story.link)
                stories.append(story)
            }
        }
        insideItem = false
    }

    // MARK: - Private

    private func feedCompleted() {
        pendingFeedCount -= 1
        if pendingFeedCount <= 0 {
            delegate?.parserDidFinishLoading(stories: stories)
        }
    }
}
