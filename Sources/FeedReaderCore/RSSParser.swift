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

// MARK: - Active Element Enum

/// Identifies which XML element is currently being parsed inside an item.
/// Using an enum eliminates repeated `NSString.isEqual(to:)` comparisons
/// on every `foundCharacters` / `foundCDATA` callback — a hot path during
/// large feed parsing. The element is resolved once in `didStartElement`
/// via a dictionary lookup, then dispatched via a constant-time `switch`.
private enum ActiveElement {
    case title
    case description  // <description>, <summary>, <content>, <content:encoded>, <encoded>
    case link
    case guid         // <guid> or <id>
    case other
}

// MARK: - Per-Feed Parse Collector

/// Isolates XML parsing state for a single feed so that concurrent
/// feeds never share mutable parsing buffers. Each collector acts as
/// its own `XMLParserDelegate`.
private class RSSParseCollector: NSObject, XMLParserDelegate {

    var stories: [RSSStory] = []

    /// Maps element names to their `ActiveElement` classification.
    /// Looked up once per `didStartElement` instead of running up to
    /// 10 string comparisons per `foundCharacters` call.
    private static let elementMap: [String: ActiveElement] = [
        "title": .title,
        "description": .description,
        "summary": .description,
        "content": .description,
        "content:encoded": .description,
        "encoded": .description,
        "link": .link,
        "guid": .guid,
        "id": .guid,
    ]

    private var activeElement: ActiveElement = .other
    private var insideItem = false

    // Fragment buffers: XML parsers call foundCharacters/foundCDATA many
    // times per element (e.g. every 4KB chunk). Appending to a String
    // with `+=` copies the entire accumulated buffer each time — O(n²)
    // for n total characters. Instead, we collect fragments in arrays
    // and join once when the <item> ends, giving O(n) total cost.
    private var titleFragments: [String] = []
    private var descriptionFragments: [String] = []
    private var linkFragments: [String] = []
    private var guidFragments: [String] = []
    private var imagePath = ""

    /// Whether the current feed uses Atom format (detected from root <feed> element).
    private var isAtomFeed = false

    /// Parse data synchronously, returning extracted stories.
    func parse(data: Data) -> [RSSStory] {
        stories = []
        stories.reserveCapacity(32) // Typical RSS feeds have 10-50 items
        isAtomFeed = false
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = self
        xmlParser.parse()
        return stories
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {
        activeElement = RSSParseCollector.elementMap[elementName] ?? .other

        // Detect Atom feed format from root <feed> element.
        if elementName == "feed" {
            isAtomFeed = true
        }

        let isItemStart = isAtomFeed ? elementName == "entry" : elementName == "item"

        if isItemStart {
            insideItem = true
            titleFragments.removeAll(keepingCapacity: true)
            descriptionFragments.removeAll(keepingCapacity: true)
            linkFragments.removeAll(keepingCapacity: true)
            guidFragments.removeAll(keepingCapacity: true)
            imagePath = ""
        }

        // Atom <link rel="alternate" href="..."> carries URL as attribute
        if isAtomFeed && insideItem && elementName == "link" {
            let rel = attributeDict["rel"] ?? "alternate"
            if rel == "alternate", let href = attributeDict["href"], !href.isEmpty {
                storyLink = href
            }
        }

        if insideItem && (elementName == "media:thumbnail" || elementName == "enclosure") {
            if let urlAttr = attributeDict["url"], !urlAttr.isEmpty, imagePath.isEmpty {
                imagePath = urlAttr
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideItem else { return }

        appendToActiveElement(string)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard insideItem else { return }
        guard let string = String(data: CDATABlock, encoding: .utf8) else { return }

        appendToActiveElement(string)
    }

    /// Appends text to whichever element buffer is currently active.
    /// Uses a `switch` on the pre-resolved `ActiveElement` enum for
    /// constant-time dispatch instead of sequential string comparisons.
    @inline(__always)
    private func appendToActiveElement(_ string: String) {
        switch activeElement {
        case .title:
            titleFragments.append(string)
        case .description:
            descriptionFragments.append(string)
        case .link:
            if !isAtomFeed { linkFragments.append(string) }
        case .guid:
            guidFragments.append(string)
        case .other:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let isItemEnd = isAtomFeed ? elementName == "entry" : elementName == "item"
        guard isItemEnd else { return }

        // Join fragments once per item — O(n) vs O(n²) from repeated `+=`.
        let storyTitle = titleFragments.joined()
        let storyDescription = descriptionFragments.joined()

        // Prefer <link> for the article URL; fall back to <guid> which
        // may or may not be a permalink (fixes parity with iOS parser).
        let trimmedLink = linkFragments.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGuid = guidFragments.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        let finalLink = trimmedLink.isEmpty ? trimmedGuid : trimmedLink

        let trimmedImagePath = imagePath.trimmingCharacters(in: .whitespacesAndNewlines)

        if let story = RSSStory(
            title: storyTitle,
            body: storyDescription,
            link: finalLink.components(separatedBy: "\n")[0],
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

    /// Generation counter to ignore callbacks from cancelled sessions.
    private var loadGeneration: UInt64 = 0

    /// Optional cache manager for HTTP conditional GET (ETag / Last-Modified).
    /// When set, feeds that haven't changed on the server receive a 304
    /// response and skip download + parse entirely — a significant bandwidth
    /// and CPU saving for users with many subscriptions.
    public var cacheManager: FeedCacheManager?

    // MARK: - Public API

    public override init() {
        super.init()
    }

    /// Creates a parser with an optional cache manager for conditional GET support.
    /// - Parameter cacheManager: Cache manager to use for ETag/Last-Modified headers.
    public convenience init(cacheManager: FeedCacheManager) {
        self.init()
        self.cacheManager = cacheManager
    }

    /// Parse stories from multiple feed URLs concurrently.
    /// Calls delegate on the main thread when all feeds have completed.
    ///
    /// Any in-flight load from a previous call is cancelled first.
    /// - Parameter urls: Array of RSS feed URL strings.
    public func loadFeeds(_ urls: [String]) {
        guard !urls.isEmpty else {
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.parserDidFinishLoading(stories: [])
            }
            return
        }

        var generation: UInt64 = 0
        let session = URLSession(configuration: .default)

        // Protect currentSession and all shared state on the serial queue
        // to prevent races when loadFeeds is called from multiple threads.
        parseQueue.sync {
            currentSession?.invalidateAndCancel()
            currentSession = session
            loadGeneration += 1
            generation = loadGeneration
            stories = []
            seenLinks = Set<String>()
            pendingFeedCount = urls.count
        }

        for url in urls {
            parseFeed(url, session: session, generation: generation)
        }
    }

    /// Parse stories from a single feed URL using the given session.
    private func parseFeed(_ url: String, session: URLSession, generation: UInt64) {
        // Delegate full SSRF validation to URLValidator: checks scheme,
        // host presence, and rejects private/reserved/link-local addresses
        // (e.g., 169.254.169.254, 10.x.x.x, localhost). Previously only
        // checked for HTTP(S) scheme, allowing internal network URLs through.
        guard let feedURL = URLValidator.validateFeedURL(url) else {
            feedCompleted(generation: generation)
            return
        }

        // Build request with conditional GET headers if cache is available.
        // Servers that support ETag / Last-Modified will return 304 Not
        // Modified when the feed hasn't changed, avoiding the full download.
        var request = URLRequest(url: feedURL)
        cacheManager?.applyCacheHeaders(to: &request, for: feedURL)

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            guard let data = data, error == nil else {
                if (error as? URLError)?.code == .cancelled { return }
                self.feedCompleted(generation: generation)
                return
            }

            // 304 Not Modified — feed hasn't changed, skip parsing entirely.
            // This saves both bandwidth and CPU for unchanged feeds.
            if let cache = self.cacheManager, cache.isNotModified(response) {
                self.feedCompleted(generation: generation)
                return
            }

            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                self.feedCompleted(generation: generation)
                return
            }

            // Update cache with new ETag/Last-Modified from the server.
            if let feedURL = response?.url ?? URL(string: url) {
                self.cacheManager?.updateCache(from: response, for: feedURL)
            }

            // Validate Content-Type before attempting XML parsing.
            // Feeds redirected to HTML error/login pages or non-XML
            // resources would waste CPU and produce garbled results.
            if let httpResponse = response as? HTTPURLResponse,
               let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased() {
                let validTypes = ["xml", "rss", "atom", "text/plain", "octet-stream"]
                if !validTypes.contains(where: { contentType.contains($0) }) {
                    self.feedCompleted(generation: generation)
                    return
                }
            }

            // Parse in isolated context — no shared mutable state.
            let collector = RSSParseCollector()
            let feedStories = collector.parse(data: data)

            // Merge results on the serial queue.
            self.parseQueue.async {
                // Discard results from a stale generation (previous loadFeeds call).
                guard generation == self.loadGeneration else { return }
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
    private func feedCompleted(generation: UInt64) {
        parseQueue.async {
            guard generation == self.loadGeneration else { return }
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
