//
//  FeedItem.swift
//  FeedReaderCore
//
//  Public model representing an RSS feed source.
//  Suitable for consumption by any iOS app that needs RSS feed management.
//

import Foundation

/// Represents a single RSS feed source with a name, URL, and enabled state.
public class FeedItem: NSObject, NSSecureCoding, @unchecked Sendable {

    // MARK: - NSSecureCoding

    public static var supportsSecureCoding: Bool { return true }

    // MARK: - Properties

    /// Display name for the feed.
    public var name: String

    /// RSS feed URL string.
    public var url: String

    /// Whether the feed is currently enabled for fetching.
    public var isEnabled: Bool

    /// Unique identifier based on the lowercased URL for deduplication.
    public var identifier: String {
        return url.lowercased()
    }

    // MARK: - Coding Keys

    private enum CodingKeys {
        static let name = "feedName"
        static let url = "feedUrl"
        static let isEnabled = "feedIsEnabled"
    }

    // MARK: - Preset Feeds

    /// Built-in feed sources users can choose from.
    public static let presets: [FeedItem] = [
        FeedItem(name: "BBC World News", url: "https://feeds.bbci.co.uk/news/world/rss.xml", isEnabled: true),
        FeedItem(name: "BBC Technology", url: "https://feeds.bbci.co.uk/news/technology/rss.xml"),
        FeedItem(name: "BBC Science", url: "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml"),
        FeedItem(name: "BBC Business", url: "https://feeds.bbci.co.uk/news/business/rss.xml"),
        FeedItem(name: "NPR News", url: "https://feeds.npr.org/1001/rss.xml"),
        FeedItem(name: "Reuters World", url: "https://www.reutersagency.com/feed/?best-topics=world&post_type=best"),
        FeedItem(name: "TechCrunch", url: "https://techcrunch.com/feed/"),
        FeedItem(name: "Ars Technica", url: "https://feeds.arstechnica.com/arstechnica/index"),
        FeedItem(name: "Hacker News", url: "https://hnrss.org/frontpage"),
        FeedItem(name: "The Verge", url: "https://www.theverge.com/rss/index.xml"),
    ]

    // MARK: - Initialization

    /// Creates a new feed item.
    /// - Parameters:
    ///   - name: Display name for the feed.
    ///   - url: RSS feed URL string.
    ///   - isEnabled: Whether the feed is enabled (default: `false`).
    public init(name: String, url: String, isEnabled: Bool = false) {
        self.name = name
        self.url = url
        self.isEnabled = isEnabled
        super.init()
    }

    // MARK: - NSCoding

    public func encode(with coder: NSCoder) {
        coder.encode(name, forKey: CodingKeys.name)
        coder.encode(url, forKey: CodingKeys.url)
        coder.encode(isEnabled, forKey: CodingKeys.isEnabled)
    }

    public required convenience init?(coder: NSCoder) {
        guard let name = coder.decodeObject(of: NSString.self, forKey: CodingKeys.name) as String?,
              let url = coder.decodeObject(of: NSString.self, forKey: CodingKeys.url) as String? else {
            return nil
        }
        let isEnabled = coder.decodeBool(forKey: CodingKeys.isEnabled)
        self.init(name: name, url: url, isEnabled: isEnabled)
    }

    // MARK: - Equality

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? FeedItem else { return false }
        return self.identifier == other.identifier
    }

    public override var hash: Int {
        return identifier.hashValue
    }
}
