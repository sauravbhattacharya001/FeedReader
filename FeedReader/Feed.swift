//
//  Feed.swift
//  FeedReader
//
//  Data model representing an RSS feed source. Supports NSSecureCoding
//  for persistent storage. Each feed has a name, URL, and enabled flag.
//

import Foundation

class Feed: NSObject, NSSecureCoding {
    
    // MARK: - NSSecureCoding
    
    static var supportsSecureCoding: Bool { return true }
    
    // MARK: - Properties
    
    var name: String
    var url: String
    var isEnabled: Bool
    
    /// Unique identifier based on URL for deduplication.
    var identifier: String {
        return url.lowercased()
    }
    
    // MARK: - Archiving
    
    private static let archiveURL: URL = {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory.appendingPathComponent("feeds")
    }()
    
    struct PropertyKey {
        static let nameKey = "feedName"
        static let urlKey = "feedUrl"
        static let isEnabledKey = "feedIsEnabled"
    }
    
    // MARK: - Preset Feeds
    
    /// Built-in feed sources users can choose from.
    static let presets: [Feed] = [
        Feed(name: "BBC World News", url: "https://feeds.bbci.co.uk/news/world/rss.xml", isEnabled: true),
        Feed(name: "BBC Technology", url: "https://feeds.bbci.co.uk/news/technology/rss.xml", isEnabled: false),
        Feed(name: "BBC Science", url: "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml", isEnabled: false),
        Feed(name: "BBC Business", url: "https://feeds.bbci.co.uk/news/business/rss.xml", isEnabled: false),
        Feed(name: "NPR News", url: "https://feeds.npr.org/1001/rss.xml", isEnabled: false),
        Feed(name: "Reuters World", url: "https://www.reutersagency.com/feed/?best-topics=world&post_type=best", isEnabled: false),
        Feed(name: "TechCrunch", url: "https://techcrunch.com/feed/", isEnabled: false),
        Feed(name: "Ars Technica", url: "https://feeds.arstechnica.com/arstechnica/index", isEnabled: false),
        Feed(name: "Hacker News", url: "https://hnrss.org/frontpage", isEnabled: false),
        Feed(name: "The Verge", url: "https://www.theverge.com/rss/index.xml", isEnabled: false)
    ]
    
    // MARK: - Initialization
    
    init(name: String, url: String, isEnabled: Bool = true) {
        self.name = name
        self.url = url
        self.isEnabled = isEnabled
        super.init()
    }
    
    // MARK: - NSCoding
    
    func encode(with aCoder: NSCoder) {
        aCoder.encode(name, forKey: PropertyKey.nameKey)
        aCoder.encode(url, forKey: PropertyKey.urlKey)
        aCoder.encode(isEnabled, forKey: PropertyKey.isEnabledKey)
    }
    
    required convenience init?(coder aDecoder: NSCoder) {
        guard let name = aDecoder.decodeObject(of: NSString.self, forKey: PropertyKey.nameKey) as String?,
              let url = aDecoder.decodeObject(of: NSString.self, forKey: PropertyKey.urlKey) as String? else {
            return nil
        }
        let isEnabled = aDecoder.decodeBool(forKey: PropertyKey.isEnabledKey)
        self.init(name: name, url: url, isEnabled: isEnabled)
    }
    
    // MARK: - Equality
    
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? Feed else { return false }
        return self.identifier == other.identifier
    }
    
    override var hash: Int {
        return identifier.hashValue
    }
}
