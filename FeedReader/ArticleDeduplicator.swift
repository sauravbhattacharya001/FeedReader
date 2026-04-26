//
//  ArticleDeduplicator.swift
//  FeedReader
//
//  Detects and manages duplicate or near-duplicate articles across feeds.
//  Uses URL normalization, title similarity (Levenshtein distance), and
//  content fingerprinting to identify duplicates. Users can auto-hide
//  duplicates, merge highlights/notes from duplicates, and review
//  detected duplicate groups.
//
//  Features:
//  - URL-based exact duplicate detection (with normalization)
//  - Title similarity matching using Levenshtein distance
//  - Content fingerprinting via simhash-style n-gram hashing
//  - Configurable similarity thresholds
//  - Duplicate group management (keep/dismiss/merge)
//  - Auto-hide duplicates in feed view
//  - Statistics and duplicate history log
//  - JSON persistence
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    static let duplicatesDidUpdate = Notification.Name("ArticleDeduplicatorDuplicatesDidUpdate")
    static let deduplicationDidRun = Notification.Name("ArticleDeduplicatorDidRun")
}

// MARK: - Models

/// Represents a lightweight article reference for deduplication.
struct DeduplicationArticle: Codable, Equatable {
    let id: String
    let title: String
    let url: String
    let feedName: String
    let publishedDate: Date?
    let contentSnippet: String

    /// Normalized URL for comparison (strips tracking params, www, trailing slashes).
    var normalizedURL: String {
        var u = url.lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")

        // Strip common tracking parameters
        if let qIndex = u.firstIndex(of: "?") {
            let base = String(u[u.startIndex..<qIndex])
            let query = String(u[u.index(after: qIndex)...])
            let trackingPrefixes = ["utm_", "ref=", "source=", "fbclid", "gclid", "mc_"]
            let filteredParams = query.components(separatedBy: "&").filter { param in
                !trackingPrefixes.contains(where: { param.lowercased().hasPrefix($0) })
            }
            u = filteredParams.isEmpty ? base : base + "?" + filteredParams.joined(separator: "&")
        }

        // Strip trailing slash
        while u.hasSuffix("/") { u = String(u.dropLast()) }
        return u
    }

    /// N-gram fingerprint of the content for similarity comparison.
    var contentFingerprint: UInt64 {
        let text = contentSnippet.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .joined(separator: " ")
        let ngrams = Self.generateNGrams(from: text, n: 3)
        // Simple simhash-style: XOR hashes of n-grams
        var hash: UInt64 = 0
        for gram in ngrams {
            var gramHash: UInt64 = 5381
            for char in gram.utf8 {
                gramHash = ((gramHash &<< 5) &+ gramHash) &+ UInt64(char)
            }
            hash ^= gramHash
        }
        return hash
    }

    private static func generateNGrams(from text: String, n: Int) -> [String] {
        let words = text.components(separatedBy: " ").filter { !$0.isEmpty }
        guard words.count >= n else { return [text] }
        var grams: [String] = []
        for i in 0...(words.count - n) {
            grams.append(words[i..<(i + n)].joined(separator: " "))
        }
        return grams
    }
}

/// A group of articles detected as duplicates.
struct DuplicateGroup: Codable, Identifiable {
    let id: String
    /// The article considered the "primary" (earliest or from preferred feed).
    var primaryArticleId: String
    /// All article IDs in this group (including primary).
    var articleIds: [String]
    /// Similarity score between articles (0.0 - 1.0).
    var similarityScore: Double
    /// How the duplicate was detected.
    var detectionMethod: DetectionMethod
    /// Whether the user has reviewed this group.
    var isReviewed: Bool
    /// Whether duplicates should be auto-hidden.
    var autoHide: Bool
    /// When this group was first detected.
    let detectedAt: Date

    enum DetectionMethod: String, Codable {
        case exactURL = "exact_url"
        case similarTitle = "similar_title"
        case contentFingerprint = "content_fingerprint"
        case combined = "combined"
    }
}

/// Configuration for the deduplication engine.
struct DeduplicationConfig: Codable {
    /// Minimum title similarity (0.0-1.0) to consider a duplicate.
    var titleSimilarityThreshold: Double
    /// Whether to auto-hide detected duplicates.
    var autoHideEnabled: Bool
    /// Whether to check across feeds (vs only within same feed).
    var crossFeedDetection: Bool
    /// Maximum age in days of articles to check.
    var maxArticleAgeDays: Int
    /// Whether URL-based detection is enabled.
    var urlDetectionEnabled: Bool
    /// Whether title-based detection is enabled.
    var titleDetectionEnabled: Bool
    /// Whether content fingerprint detection is enabled.
    var contentDetectionEnabled: Bool

    static var `default`: DeduplicationConfig {
        DeduplicationConfig(
            titleSimilarityThreshold: 0.85,
            autoHideEnabled: false,
            crossFeedDetection: true,
            maxArticleAgeDays: 30,
            urlDetectionEnabled: true,
            titleDetectionEnabled: true,
            contentDetectionEnabled: true
        )
    }
}

/// Stats about deduplication runs.
struct DeduplicationStats: Codable {
    var totalScansRun: Int
    var totalDuplicatesFound: Int
    var totalGroupsCreated: Int
    var totalArticlesHidden: Int
    var lastScanDate: Date?
    var lastScanDuration: TimeInterval?
    var duplicatesByMethod: [String: Int]

    static var empty: DeduplicationStats {
        DeduplicationStats(
            totalScansRun: 0,
            totalDuplicatesFound: 0,
            totalGroupsCreated: 0,
            totalArticlesHidden: 0,
            lastScanDate: nil,
            lastScanDuration: nil,
            duplicatesByMethod: [:]
        )
    }
}

// MARK: - ArticleDeduplicator

/// Detects and manages duplicate articles across feeds.
final class ArticleDeduplicator {

    // MARK: - Properties

    private(set) var config: DeduplicationConfig
    private(set) var duplicateGroups: [DuplicateGroup] = []
    private(set) var stats: DeduplicationStats = .empty
    private(set) var hiddenArticleIds: Set<String> = []

    private let configPath: String
    private let groupsPath: String
    private let statsPath: String
    private let hiddenPath: String

    // MARK: - Initialization

    init(storageDirectory: String? = nil) {
        let dir = storageDirectory ?? NSSearchPathForDirectoriesInDomains(
            .documentDirectory, .userDomainMask, true
        ).first!
        self.configPath = (dir as NSString).appendingPathComponent("dedup_config.json")
        self.groupsPath = (dir as NSString).appendingPathComponent("dedup_groups.json")
        self.statsPath = (dir as NSString).appendingPathComponent("dedup_stats.json")
        self.hiddenPath = (dir as NSString).appendingPathComponent("dedup_hidden.json")

        self.config = Self.loadJSON(from: configPath) ?? .default
        self.duplicateGroups = Self.loadJSON(from: groupsPath) ?? []
        self.stats = Self.loadJSON(from: statsPath) ?? .empty
        self.hiddenArticleIds = Set(Self.loadJSON(from: hiddenPath) as [String]? ?? [])
    }

    // MARK: - Scanning

    /// Scans a list of articles for duplicates.
    /// Returns newly detected duplicate groups.
    @discardableResult
    func scan(articles: [DeduplicationArticle]) -> [DuplicateGroup] {
        let startTime = Date()
        var newGroups: [DuplicateGroup] = []

        // Filter by age
        let cutoff = Calendar.current.date(byAdding: .day, value: -config.maxArticleAgeDays, to: Date())!
        let candidates = articles.filter { ($0.publishedDate ?? Date()) >= cutoff }

        // Pre-compute unique articles once (used by title + fingerprint phases)
        let uniqueArticles = candidates.uniqued(by: \.id)

        // Pre-compute normalized URLs — avoids re-deriving per pair in O(n²) title loop
        var normalizedURLs: [String: String] = [:]
        normalizedURLs.reserveCapacity(uniqueArticles.count)
        for article in uniqueArticles {
            normalizedURLs[article.id] = article.normalizedURL
        }

        // Build lookup maps using pre-computed URLs
        var urlMap: [String: [DeduplicationArticle]] = [:]
        for article in uniqueArticles {
            let key = normalizedURLs[article.id]!
            urlMap[key, default: []].append(article)
        }

        // Build O(1) grouped-article index from existing groups.
        // Maps each article ID to the set of group indices it belongs to,
        // so isAlreadyGrouped checks are O(min-group-count) instead of O(G×A).
        var articleToGroupIndices: [String: [Int]] = [:]
        for (gi, g) in duplicateGroups.enumerated() {
            for aid in g.articleIds {
                articleToGroupIndices[aid, default: []].append(gi)
            }
        }

        // Track new-group pairs with a Set<String> of canonical pair keys
        // so we avoid O(newGroups) scans with Set reconstruction per check.
        var newGroupPairKeys: Set<String> = []

        /// Returns a canonical key for a pair of article IDs.
        func pairKey(_ id1: String, _ id2: String) -> String {
            id1 < id2 ? "\(id1)\0\(id2)" : "\(id2)\0\(id1)"
        }

        /// Checks if all given IDs are already covered by an existing group,
        /// using the indexed lookup instead of scanning all groups.
        func isAlreadyGroupedFast(_ ids: [String]) -> Bool {
            guard let firstId = ids.first,
                  let groupIndices = articleToGroupIndices[firstId] else { return false }
            let idSet = Set(ids)
            for gi in groupIndices {
                if idSet.isSubset(of: duplicateGroups[gi].articleIds) {
                    return true
                }
            }
            return false
        }

        // 1. URL-based detection
        if config.urlDetectionEnabled {
            for (_, group) in urlMap where group.count > 1 {
                let ids = group.map { $0.id }
                if !isAlreadyGroupedFast(ids) {
                    let dg = DuplicateGroup(
                        id: UUID().uuidString,
                        primaryArticleId: group.sorted(by: { ($0.publishedDate ?? .distantFuture) < ($1.publishedDate ?? .distantFuture) }).first!.id,
                        articleIds: ids,
                        similarityScore: 1.0,
                        detectionMethod: .exactURL,
                        isReviewed: false,
                        autoHide: config.autoHideEnabled,
                        detectedAt: Date()
                    )
                    newGroups.append(dg)
                    // Register pair keys for dedup within this scan
                    for k in 0..<ids.count {
                        for l in (k+1)..<ids.count {
                            newGroupPairKeys.insert(pairKey(ids[k], ids[l]))
                        }
                    }
                }
            }
        }

        // 2. Title-based detection — O(n²) pair loop; inner checks now O(1)
        if config.titleDetectionEnabled {
            // Pre-compute lowercased trimmed titles to avoid re-deriving per pair
            let preparedTitles: [(article: DeduplicationArticle, lowerTitle: String)] =
                uniqueArticles.map { ($0, $0.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)) }

            for i in 0..<preparedTitles.count {
                let (a, titleA) = preparedTitles[i]
                let lenA = titleA.count
                for j in (i + 1)..<preparedTitles.count {
                    let (b, titleB) = preparedTitles[j]
                    // Skip if same URL (already caught above) — uses cached values
                    if normalizedURLs[a.id]! == normalizedURLs[b.id]! { continue }
                    // Skip if not cross-feed and same feed
                    if !config.crossFeedDetection && a.feedName == b.feedName { continue }

                    // Early reject: if length difference alone exceeds the
                    // tolerance implied by the threshold, skip the expensive
                    // Levenshtein computation entirely.
                    let lenB = titleB.count
                    let maxLen = max(lenA, lenB)
                    if maxLen > 0 {
                        let maxAllowedDistance = Int(Double(maxLen) * (1.0 - config.titleSimilarityThreshold))
                        if abs(lenA - lenB) > maxAllowedDistance { continue }
                    }

                    let similarity = Self.titleSimilarity(a.title, b.title)
                    if similarity >= config.titleSimilarityThreshold {
                        let pk = pairKey(a.id, b.id)
                        if !isAlreadyGroupedFast([a.id, b.id]) && !newGroupPairKeys.contains(pk) {
                            let dg = DuplicateGroup(
                                id: UUID().uuidString,
                                primaryArticleId: (a.publishedDate ?? .distantFuture) <= (b.publishedDate ?? .distantFuture) ? a.id : b.id,
                                articleIds: [a.id, b.id],
                                similarityScore: similarity,
                                detectionMethod: .similarTitle,
                                isReviewed: false,
                                autoHide: config.autoHideEnabled,
                                detectedAt: Date()
                            )
                            newGroups.append(dg)
                            newGroupPairKeys.insert(pk)
                        }
                    }
                }
            }
        }

        // 3. Content fingerprint detection
        if config.contentDetectionEnabled {
            // Pre-compute fingerprints once (contentFingerprint is O(n) per article)
            var fingerprintMap: [UInt64: [DeduplicationArticle]] = [:]
            for article in uniqueArticles {
                let fp = article.contentFingerprint
                fingerprintMap[fp, default: []].append(article)
            }
            for (_, group) in fingerprintMap where group.count > 1 {
                let ids = group.map { $0.id }
                let idSet = Set(ids)
                // Check existing groups via index
                let alreadyCovered = isAlreadyGroupedFast(ids)
                // Check new groups: any new group that is a superset of these ids
                let newCovered = newGroups.contains { Set($0.articleIds).isSuperset(of: idSet) }
                if !alreadyCovered && !newCovered {
                    let dg = DuplicateGroup(
                        id: UUID().uuidString,
                        primaryArticleId: group.sorted(by: { ($0.publishedDate ?? .distantFuture) < ($1.publishedDate ?? .distantFuture) }).first!.id,
                        articleIds: ids,
                        similarityScore: 0.9,
                        detectionMethod: .contentFingerprint,
                        isReviewed: false,
                        autoHide: config.autoHideEnabled,
                        detectedAt: Date()
                    )
                    newGroups.append(dg)
                }
            }
        }

        // Apply auto-hide
        for group in newGroups where group.autoHide {
            let secondaryIds = group.articleIds.filter { $0 != group.primaryArticleId }
            hiddenArticleIds.formUnion(secondaryIds)
        }

        // Update state
        duplicateGroups.append(contentsOf: newGroups)
        let elapsed = Date().timeIntervalSince(startTime)
        stats.totalScansRun += 1
        stats.totalDuplicatesFound += newGroups.reduce(0) { $0 + $1.articleIds.count - 1 }
        stats.totalGroupsCreated += newGroups.count
        stats.totalArticlesHidden = hiddenArticleIds.count
        stats.lastScanDate = Date()
        stats.lastScanDuration = elapsed
        for g in newGroups {
            stats.duplicatesByMethod[g.detectionMethod.rawValue, default: 0] += 1
        }

        save()
        NotificationCenter.default.post(name: .deduplicationDidRun, object: self)
        if !newGroups.isEmpty {
            NotificationCenter.default.post(name: .duplicatesDidUpdate, object: self)
        }

        return newGroups
    }

    // MARK: - Group Management

    /// Returns whether an article is hidden as a duplicate.
    func isHidden(_ articleId: String) -> Bool {
        hiddenArticleIds.contains(articleId)
    }

    /// Returns the duplicate group containing a given article, if any.
    func group(for articleId: String) -> DuplicateGroup? {
        duplicateGroups.first { $0.articleIds.contains(articleId) }
    }

    /// Returns all unreviewed duplicate groups.
    var unreviewedGroups: [DuplicateGroup] {
        duplicateGroups.filter { !$0.isReviewed }
    }

    /// Marks a group as reviewed.
    func markReviewed(groupId: String) {
        guard let idx = duplicateGroups.firstIndex(where: { $0.id == groupId }) else { return }
        duplicateGroups[idx].isReviewed = true
        save()
    }

    /// Dismisses a duplicate group (removes it, unhides articles).
    func dismissGroup(groupId: String) {
        guard let idx = duplicateGroups.firstIndex(where: { $0.id == groupId }) else { return }
        let group = duplicateGroups[idx]
        let secondaryIds = group.articleIds.filter { $0 != group.primaryArticleId }
        hiddenArticleIds.subtract(secondaryIds)
        duplicateGroups.remove(at: idx)
        stats.totalArticlesHidden = hiddenArticleIds.count
        save()
        NotificationCenter.default.post(name: .duplicatesDidUpdate, object: self)
    }

    /// Changes the primary article in a group.
    func setPrimary(articleId: String, inGroup groupId: String) {
        guard let idx = duplicateGroups.firstIndex(where: { $0.id == groupId }) else { return }
        guard duplicateGroups[idx].articleIds.contains(articleId) else { return }

        // Update hidden: unhide old secondaries, set new ones
        let oldSecondaries = duplicateGroups[idx].articleIds.filter { $0 != duplicateGroups[idx].primaryArticleId }
        hiddenArticleIds.subtract(oldSecondaries)

        duplicateGroups[idx].primaryArticleId = articleId
        if duplicateGroups[idx].autoHide {
            let newSecondaries = duplicateGroups[idx].articleIds.filter { $0 != articleId }
            hiddenArticleIds.formUnion(newSecondaries)
        }

        stats.totalArticlesHidden = hiddenArticleIds.count
        save()
    }

    // MARK: - Configuration

    /// Updates deduplication configuration.
    func updateConfig(_ newConfig: DeduplicationConfig) {
        config = newConfig
        save()
    }

    /// Toggles auto-hide for all existing groups.
    func setAutoHide(_ enabled: Bool) {
        config.autoHideEnabled = enabled
        for i in 0..<duplicateGroups.count {
            duplicateGroups[i].autoHide = enabled
            if enabled {
                let secondaries = duplicateGroups[i].articleIds.filter { $0 != duplicateGroups[i].primaryArticleId }
                hiddenArticleIds.formUnion(secondaries)
            }
        }
        if !enabled {
            hiddenArticleIds.removeAll()
        }
        stats.totalArticlesHidden = hiddenArticleIds.count
        save()
    }

    /// Clears all duplicate groups and hidden articles.
    func reset() {
        duplicateGroups.removeAll()
        hiddenArticleIds.removeAll()
        stats = .empty
        save()
        NotificationCenter.default.post(name: .duplicatesDidUpdate, object: self)
    }

    // MARK: - String Similarity

    /// Computes title similarity using normalized Levenshtein distance.
    /// Uses an early-exit optimization: if the length difference alone
    /// makes it impossible to meet the configured threshold, returns 0
    /// without computing the full edit distance.
    static func titleSimilarity(_ a: String, _ b: String) -> Double {
        let s1 = a.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let s2 = b.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if s1 == s2 { return 1.0 }
        if s1.isEmpty || s2.isEmpty { return 0.0 }

        let maxLen = max(s1.count, s2.count)
        let distance = levenshteinDistance(s1, s2, cutoff: maxLen)
        return 1.0 - (Double(distance) / Double(maxLen))
    }

    /// Two-row Levenshtein distance with early termination.
    ///
    /// Uses O(min(m,n)) space instead of O(m×n) by keeping only two
    /// rows of the DP matrix. Bails out early if every value in the
    /// current row exceeds `cutoff`, since the distance can only
    /// increase from there.
    private static func levenshteinDistance(_ s1: String, _ s2: String, cutoff: Int) -> Int {
        // Ensure s2 is the shorter string for optimal space usage
        let a: [Character], b: [Character]
        if s1.count < s2.count {
            a = Array(s2); b = Array(s1)
        } else {
            a = Array(s1); b = Array(s2)
        }
        let m = a.count, n = b.count

        // Length difference alone exceeds cutoff — no need to compute
        if m - n > cutoff { return cutoff + 1 }

        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            var rowMin = curr[0]
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,       // deletion
                    curr[j - 1] + 1,   // insertion
                    prev[j - 1] + cost // substitution
                )
                rowMin = min(rowMin, curr[j])
            }
            // Early termination: if the minimum value in this row
            // already exceeds the cutoff, the final distance will too
            if rowMin > cutoff { return cutoff + 1 }
            swap(&prev, &curr)
        }
        return prev[n]
    }

    // MARK: - Helpers

    private func isAlreadyGrouped(_ ids: [String]) -> Bool {
        let idSet = Set(ids)
        return duplicateGroups.contains { Set($0.articleIds).isSuperset(of: idSet) }
    }

    private func save() {
        Self.saveJSON(config, to: configPath)
        Self.saveJSON(duplicateGroups, to: groupsPath)
        Self.saveJSON(stats, to: statsPath)
        Self.saveJSON(Array(hiddenArticleIds), to: hiddenPath)
    }

    private static func loadJSON<T: Decodable>(from path: String) -> T? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONCoding.iso8601Decoder.decode(T.self, from: data)
    }

    private static func saveJSON<T: Encodable>(_ value: T, to path: String) {
        guard let data = try? JSONCoding.iso8601PrettyEncoder.encode(value) else { return }
        FileManager.default.createFile(atPath: path, contents: data)
    }
}

// MARK: - Array Extension

private extension Array {
    func uniqued<T: Hashable>(by keyPath: KeyPath<Element, T>) -> [Element] {
        var seen = Set<T>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
