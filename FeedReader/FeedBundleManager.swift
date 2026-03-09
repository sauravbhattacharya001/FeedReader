//
//  FeedBundleManager.swift
//  FeedReader
//
//  Manages curated feed bundles — themed collections of feeds that
//  users can browse by topic, preview, subscribe to in one click,
//  and create from their own subscriptions.
//

import Foundation

/// Notification posted when bundles change.
extension Notification.Name {
    static let feedBundlesDidChange = Notification.Name("FeedBundlesDidChangeNotification")
}

// MARK: - Models

/// A single feed entry within a bundle.
struct BundledFeed: Codable, Equatable {
    let title: String
    let url: String
    let description: String

    static func == (lhs: BundledFeed, rhs: BundledFeed) -> Bool {
        return lhs.url == rhs.url
    }
}

/// A themed collection of feeds.
struct FeedBundle: Codable, Equatable {
    let id: String
    let name: String
    let topic: String
    let description: String
    let icon: String
    var feeds: [BundledFeed]
    let isBuiltIn: Bool
    let createdDate: Date

    static func == (lhs: FeedBundle, rhs: FeedBundle) -> Bool {
        return lhs.id == rhs.id
    }
}

/// Result of subscribing to a bundle.
struct BundleSubscriptionResult {
    let bundleId: String
    let bundleName: String
    let totalFeeds: Int
    let newlySubscribed: Int
    let alreadySubscribed: Int
    let failed: Int
}

// MARK: - FeedBundleManager

class FeedBundleManager {

    // MARK: - Singleton

    static let shared = FeedBundleManager()

    // MARK: - Properties

    private(set) var bundles: [FeedBundle] = []
    private var subscribedBundleIds = Set<String>()

    private static let customBundlesKey = "FeedBundleManager.customBundles"
    private static let subscribedKey = "FeedBundleManager.subscribedBundleIds"

    // MARK: - Initialization

    private init() {
        bundles = FeedBundleManager.builtInBundles()
        loadCustomBundles()
        loadSubscribedIds()
    }

    /// Test-only initializer that skips persistence.
    init(testBundles: [FeedBundle]) {
        self.bundles = testBundles
    }

    // MARK: - Built-in Bundles

    static func builtInBundles() -> [FeedBundle] {
        let epoch = Date(timeIntervalSince1970: 0)
        return [
            FeedBundle(
                id: "tech-essentials",
                name: "Tech Essentials",
                topic: "Technology",
                description: "Must-read technology news and analysis from top sources.",
                icon: "💻",
                feeds: [
                    BundledFeed(title: "Ars Technica", url: "https://feeds.arstechnica.com/arstechnica/index", description: "In-depth tech reporting and analysis"),
                    BundledFeed(title: "TechCrunch", url: "https://techcrunch.com/feed/", description: "Startup and technology news"),
                    BundledFeed(title: "The Verge", url: "https://www.theverge.com/rss/index.xml", description: "Technology, science, art, and culture"),
                    BundledFeed(title: "Hacker News", url: "https://hnrss.org/frontpage", description: "Top stories from Hacker News"),
                    BundledFeed(title: "Wired", url: "https://www.wired.com/feed/rss", description: "Future technology and culture"),
                ],
                isBuiltIn: true,
                createdDate: epoch
            ),
            FeedBundle(
                id: "dev-tools",
                name: "Developer Corner",
                topic: "Programming",
                description: "Programming tutorials, tools, and engineering blogs.",
                icon: "🛠",
                feeds: [
                    BundledFeed(title: "CSS-Tricks", url: "https://css-tricks.com/feed/", description: "Web development tips and techniques"),
                    BundledFeed(title: "Smashing Magazine", url: "https://www.smashingmagazine.com/feed/", description: "Web design and development"),
                    BundledFeed(title: "Dev.to", url: "https://dev.to/feed", description: "Community-driven developer articles"),
                    BundledFeed(title: "Martin Fowler", url: "https://martinfowler.com/feed.atom", description: "Software architecture and design"),
                    BundledFeed(title: "GitHub Blog", url: "https://github.blog/feed/", description: "GitHub product and engineering updates"),
                ],
                isBuiltIn: true,
                createdDate: epoch
            ),
            FeedBundle(
                id: "science-nature",
                name: "Science & Nature",
                topic: "Science",
                description: "Scientific discoveries, research, and the natural world.",
                icon: "🔬",
                feeds: [
                    BundledFeed(title: "Nature News", url: "https://www.nature.com/nature.rss", description: "Latest research from Nature journal"),
                    BundledFeed(title: "NASA", url: "https://www.nasa.gov/rss/dyn/breaking_news.rss", description: "Space exploration and discoveries"),
                    BundledFeed(title: "Quanta Magazine", url: "https://api.quantamagazine.org/feed/", description: "Math, physics, biology, and computer science"),
                    BundledFeed(title: "Science Daily", url: "https://www.sciencedaily.com/rss/all.xml", description: "Latest scientific research news"),
                ],
                isBuiltIn: true,
                createdDate: epoch
            ),
            FeedBundle(
                id: "design-creative",
                name: "Design & Creative",
                topic: "Design",
                description: "UI/UX design, typography, and creative inspiration.",
                icon: "🎨",
                feeds: [
                    BundledFeed(title: "A List Apart", url: "https://alistapart.com/main/feed/", description: "Web standards and best practices"),
                    BundledFeed(title: "Dribbble Blog", url: "https://dribbble.com/stories.rss", description: "Design community stories"),
                    BundledFeed(title: "UX Collective", url: "https://uxdesign.cc/feed", description: "User experience design articles"),
                    BundledFeed(title: "Codrops", url: "https://tympanus.net/codrops/feed/", description: "Creative web development tutorials"),
                ],
                isBuiltIn: true,
                createdDate: epoch
            ),
            FeedBundle(
                id: "ai-ml",
                name: "AI & Machine Learning",
                topic: "AI",
                description: "Artificial intelligence research, tools, and industry news.",
                icon: "🤖",
                feeds: [
                    BundledFeed(title: "MIT Technology Review AI", url: "https://www.technologyreview.com/topic/artificial-intelligence/feed", description: "AI coverage from MIT Tech Review"),
                    BundledFeed(title: "Distill", url: "https://distill.pub/rss.xml", description: "Clear explanations of ML concepts"),
                    BundledFeed(title: "The Gradient", url: "https://thegradient.pub/rss/", description: "AI research perspectives and analysis"),
                    BundledFeed(title: "Import AI", url: "https://jack-clark.net/feed/", description: "Weekly AI newsletter digest"),
                ],
                isBuiltIn: true,
                createdDate: epoch
            ),
            FeedBundle(
                id: "world-news",
                name: "World News",
                topic: "News",
                description: "Global news from trusted independent sources.",
                icon: "🌍",
                feeds: [
                    BundledFeed(title: "Reuters World", url: "https://feeds.reuters.com/reuters/worldNews", description: "International wire service"),
                    BundledFeed(title: "BBC World", url: "https://feeds.bbci.co.uk/news/world/rss.xml", description: "Global news from the BBC"),
                    BundledFeed(title: "AP News", url: "https://rsshub.app/apnews/topics/apf-topnews", description: "Associated Press top stories"),
                    BundledFeed(title: "The Guardian World", url: "https://www.theguardian.com/world/rss", description: "World news from The Guardian"),
                ],
                isBuiltIn: true,
                createdDate: epoch
            ),
        ]
    }

    // MARK: - Browse

    /// All available topics (unique, sorted).
    func topics() -> [String] {
        let set = Set(bundles.map { $0.topic })
        return set.sorted()
    }

    /// Get bundles filtered by topic.
    func bundles(forTopic topic: String) -> [FeedBundle] {
        return bundles.filter { $0.topic == topic }
    }

    /// Find a bundle by ID.
    func bundle(withId id: String) -> FeedBundle? {
        return bundles.first(where: { $0.id == id })
    }

    /// Search bundles by name, topic, or feed titles.
    func search(query: String) -> [FeedBundle] {
        let lower = query.lowercased()
        return bundles.filter { bundle in
            bundle.name.lowercased().contains(lower)
                || bundle.topic.lowercased().contains(lower)
                || bundle.description.lowercased().contains(lower)
                || bundle.feeds.contains(where: { $0.title.lowercased().contains(lower) })
        }
    }

    // MARK: - Subscribe

    /// Check if a bundle has been subscribed.
    func isSubscribed(bundleId: String) -> Bool {
        return subscribedBundleIds.contains(bundleId)
    }

    /// Subscribe to all feeds in a bundle.
    /// Returns a result with counts of new vs already-subscribed feeds.
    /// The `isSubscribedCheck` closure lets callers plug in their own
    /// FeedManager subscription check (avoids tight coupling).
    func subscribe(
        bundleId: String,
        isAlreadySubscribed: (String) -> Bool,
        addFeed: (String, String) -> Bool
    ) -> BundleSubscriptionResult? {
        guard let bundle = bundle(withId: bundleId) else { return nil }

        var newCount = 0
        var existingCount = 0
        var failCount = 0

        for feed in bundle.feeds {
            if isAlreadySubscribed(feed.url) {
                existingCount += 1
            } else if addFeed(feed.url, feed.title) {
                newCount += 1
            } else {
                failCount += 1
            }
        }

        subscribedBundleIds.insert(bundleId)
        saveSubscribedIds()
        NotificationCenter.default.post(name: .feedBundlesDidChange, object: nil)

        return BundleSubscriptionResult(
            bundleId: bundleId,
            bundleName: bundle.name,
            totalFeeds: bundle.feeds.count,
            newlySubscribed: newCount,
            alreadySubscribed: existingCount,
            failed: failCount
        )
    }

    /// Unsubscribe (untrack) a bundle. Does NOT remove individual feeds.
    func unsubscribe(bundleId: String) -> Bool {
        guard subscribedBundleIds.contains(bundleId) else { return false }
        subscribedBundleIds.remove(bundleId)
        saveSubscribedIds()
        NotificationCenter.default.post(name: .feedBundlesDidChange, object: nil)
        return true
    }

    // MARK: - Custom Bundles

    /// Create a custom bundle from user-provided feeds.
    @discardableResult
    func createBundle(
        name: String,
        topic: String,
        description: String,
        icon: String,
        feeds: [BundledFeed]
    ) -> FeedBundle? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        guard !feeds.isEmpty else { return nil }
        // Deduplicate feeds by URL
        var seen = Set<String>()
        var uniqueFeeds: [BundledFeed] = []
        for feed in feeds {
            if !seen.contains(feed.url) {
                seen.insert(feed.url)
                uniqueFeeds.append(feed)
            }
        }

        let bundle = FeedBundle(
            id: "custom-" + UUID().uuidString,
            name: trimmedName,
            topic: topic.isEmpty ? "Custom" : topic,
            description: description,
            icon: icon.isEmpty ? "📦" : icon,
            feeds: uniqueFeeds,
            isBuiltIn: false,
            createdDate: Date()
        )
        bundles.append(bundle)
        saveCustomBundles()
        NotificationCenter.default.post(name: .feedBundlesDidChange, object: nil)
        return bundle
    }

    /// Delete a custom bundle. Built-in bundles cannot be deleted.
    func deleteBundle(id: String) -> Bool {
        guard let index = bundles.firstIndex(where: { $0.id == id }) else {
            return false
        }
        guard !bundles[index].isBuiltIn else { return false }
        bundles.remove(at: index)
        subscribedBundleIds.remove(id)
        saveCustomBundles()
        saveSubscribedIds()
        NotificationCenter.default.post(name: .feedBundlesDidChange, object: nil)
        return true
    }

    /// Add a feed to an existing custom bundle.
    func addFeed(_ feed: BundledFeed, toBundleId id: String) -> Bool {
        guard let index = bundles.firstIndex(where: { $0.id == id }) else {
            return false
        }
        guard !bundles[index].isBuiltIn else { return false }
        guard !bundles[index].feeds.contains(where: { $0.url == feed.url }) else {
            return false
        }
        bundles[index].feeds.append(feed)
        saveCustomBundles()
        NotificationCenter.default.post(name: .feedBundlesDidChange, object: nil)
        return true
    }

    /// Remove a feed from a custom bundle.
    func removeFeed(url: String, fromBundleId id: String) -> Bool {
        guard let index = bundles.firstIndex(where: { $0.id == id }) else {
            return false
        }
        guard !bundles[index].isBuiltIn else { return false }
        let before = bundles[index].feeds.count
        bundles[index].feeds.removeAll(where: { $0.url == url })
        if bundles[index].feeds.count < before {
            saveCustomBundles()
            NotificationCenter.default.post(name: .feedBundlesDidChange, object: nil)
            return true
        }
        return false
    }

    // MARK: - Export / Import

    /// Export a bundle to JSON data.
    func exportBundle(id: String) -> Data? {
        guard let bundle = bundle(withId: id) else { return nil }
        let encoder = JSONCoding.epochPrettyEncoder
        return try? encoder.encode(bundle)
    }

    /// Import a bundle from JSON data.
    func importBundle(from data: Data) -> FeedBundle? {
        let decoder = JSONCoding.epochDecoder
        guard var bundle = try? decoder.decode(FeedBundle.self, from: data) else {
            return nil
        }
        // Generate new ID to avoid collisions and mark as custom
        let imported = FeedBundle(
            id: "imported-" + UUID().uuidString,
            name: bundle.name,
            topic: bundle.topic,
            description: bundle.description,
            icon: bundle.icon,
            feeds: bundle.feeds,
            isBuiltIn: false,
            createdDate: Date()
        )
        bundles.append(imported)
        saveCustomBundles()
        NotificationCenter.default.post(name: .feedBundlesDidChange, object: nil)
        return imported
    }

    // MARK: - Statistics

    /// Total number of unique feeds across all bundles.
    func totalUniqueFeedCount() -> Int {
        var urls = Set<String>()
        for bundle in bundles {
            for feed in bundle.feeds {
                urls.insert(feed.url)
            }
        }
        return urls.count
    }

    /// Summary: bundles per topic.
    func bundlesPerTopic() -> [String: Int] {
        var result: [String: Int] = [:]
        for bundle in bundles {
            result[bundle.topic, default: 0] += 1
        }
        return result
    }

    /// Get IDs of all subscribed bundles.
    func subscribedBundleList() -> [FeedBundle] {
        return bundles.filter { subscribedBundleIds.contains($0.id) }
    }

    // MARK: - Persistence

    private func saveCustomBundles() {
        let custom = bundles.filter { !$0.isBuiltIn }
        let encoder = JSONCoding.epochEncoder
        if let data = try? encoder.encode(custom) {
            UserDefaults.standard.set(data, forKey: FeedBundleManager.customBundlesKey)
        }
    }

    private func loadCustomBundles() {
        guard let data = UserDefaults.standard.data(
            forKey: FeedBundleManager.customBundlesKey) else { return }
        let decoder = JSONCoding.epochDecoder
        if let custom = try? decoder.decode([FeedBundle].self, from: data) {
            bundles.append(contentsOf: custom)
        }
    }

    private func saveSubscribedIds() {
        UserDefaults.standard.set(Array(subscribedBundleIds),
                                  forKey: FeedBundleManager.subscribedKey)
    }

    private func loadSubscribedIds() {
        if let arr = UserDefaults.standard.stringArray(
            forKey: FeedBundleManager.subscribedKey) {
            subscribedBundleIds = Set(arr)
        }
    }
}
