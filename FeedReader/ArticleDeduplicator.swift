//
//  ArticleDeduplicator.swift
//  FeedReader
//
//  Detects duplicate and near-duplicate articles across feeds using
//  multi-signal fingerprinting. Typical RSS users subscribe to overlapping
//  sources that re-publish the same story; this groups them so the UI can
//  collapse duplicates and show the best version.
//
//  Signals used (weighted):
//    1. Normalized title similarity (Jaccard on 3-grams)
//    2. Content fingerprint (simhash-style via top-term frequency vector)
//    3. Link domain+path match (catches syndicated rewrites)
//
//  Fully offline - no network, no dependencies beyond Foundation.
//

import Foundation
import CryptoKit

// MARK: - DuplicateGroup

/// A cluster of articles that represent the same underlying story.
struct DuplicateGroup: Equatable {
    /// Unique group identifier (derived from canonical fingerprint).
    let id: String
    /// All article links in this group, ordered by detection time.
    var memberLinks: [String]
    /// The "best" representative link (earliest discovered, shortest title).
    var canonicalLink: String
    /// Confidence score for the grouping (0.0-1.0).
    var confidence: Double
    /// Short reason explaining why these were grouped.
    var reason: String

    static func == (lhs: DuplicateGroup, rhs: DuplicateGroup) -> Bool {
        return lhs.id == rhs.id && lhs.memberLinks == rhs.memberLinks
    }
}

// MARK: - DeduplicationResult

/// Outcome of scanning a set of articles.
struct DeduplicationResult {
    /// Groups containing 2+ duplicate articles.
    let groups: [DuplicateGroup]
    /// Total articles scanned.
    let totalScanned: Int
    /// Number of articles identified as duplicates (not counting canonicals).
    let duplicateCount: Int
    /// Wall-clock time for the scan (seconds).
    let scanDuration: TimeInterval

    /// Links that are duplicates (non-canonical members of groups).
    var duplicateLinks: Set<String> {
        var result = Set<String>()
        for group in groups {
            for link in group.memberLinks where link != group.canonicalLink {
                result.insert(link)
            }
        }
        return result
    }
}

// MARK: - ArticleDeduplicator

/// Detects duplicate articles across feeds using multi-signal fingerprinting.
class ArticleDeduplicator {

    // MARK: - Configuration

    /// Minimum combined similarity score to consider two articles duplicates.
    let threshold: Double

    /// Weight for title similarity signal (0.0-1.0).
    let titleWeight: Double

    /// Weight for content fingerprint signal (0.0-1.0).
    let contentWeight: Double

    /// Weight for URL similarity signal (0.0-1.0).
    let urlWeight: Double

    /// Size of character n-grams for title comparison.
    let ngramSize: Int

    /// Number of top terms to use for content fingerprinting.
    let fingerprintTermCount: Int

    // MARK: - Internal State

    /// Indexed articles: link -> fingerprint data.
    private var index: [String: ArticleFingerprint] = [:]

    /// Insertion order for deterministic canonical selection.
    private var insertionOrder: [String] = []

    /// Position lookup: link → index in insertionOrder for O(1) access.
    /// Maintained incrementally by indexStory/removeStory/reset to avoid
    /// O(n) firstIndex(of:) scans in selectCanonical.
    private var positionCache: [String: Int] = [:]

    // MARK: - Types

    /// Pre-computed fingerprint for an article.
    struct ArticleFingerprint {
        let link: String
        let normalizedTitle: String
        let titleNgrams: Set<String>
        let contentTerms: [String: Int]
        let urlDomainPath: String
        let titleLength: Int
        let feedName: String
    }

    // MARK: - Init

    init(threshold: Double = 0.6,
         titleWeight: Double = 0.45,
         contentWeight: Double = 0.35,
         urlWeight: Double = 0.20,
         ngramSize: Int = 3,
         fingerprintTermCount: Int = 20) {
        self.threshold = max(0.0, min(1.0, threshold))
        let total = titleWeight + contentWeight + urlWeight
        if total > 0 {
            self.titleWeight = titleWeight / total
            self.contentWeight = contentWeight / total
            self.urlWeight = urlWeight / total
        } else {
            self.titleWeight = 1.0 / 3.0
            self.contentWeight = 1.0 / 3.0
            self.urlWeight = 1.0 / 3.0
        }
        self.ngramSize = max(2, ngramSize)
        self.fingerprintTermCount = max(5, fingerprintTermCount)
    }

    // MARK: - Indexing

    /// Index a batch of stories for deduplication.
    func index(_ stories: [Story]) {
        for story in stories {
            indexStory(story)
        }
    }

    /// Index a single story. Skips if already indexed (by link).
    func indexStory(_ story: Story) {
        let link = story.link
        guard !link.isEmpty, index[link] == nil else { return }

        let normalizedTitle = normalizeText(story.title)
        let ngrams = characterNgrams(normalizedTitle, n: ngramSize)
        let terms = extractTopTerms(story.body, count: fingerprintTermCount)
        let domainPath = extractDomainPath(link)

        let fingerprint = ArticleFingerprint(
            link: link,
            normalizedTitle: normalizedTitle,
            titleNgrams: ngrams,
            contentTerms: terms,
            urlDomainPath: domainPath,
            titleLength: normalizedTitle.count,
            feedName: story.sourceFeedName ?? ""
        )

        index[link] = fingerprint
        positionCache[link] = insertionOrder.count
        insertionOrder.append(link)
    }

    /// Remove a story from the index.
    func removeStory(link: String) {
        index.removeValue(forKey: link)
        if let removedPos = positionCache.removeValue(forKey: link) {
            insertionOrder.removeAll { $0 == link }
            // Rebuild positions for entries that shifted
            for i in removedPos..<insertionOrder.count {
                positionCache[insertionOrder[i]] = i
            }
        }
    }

    /// Clear the entire index.
    func reset() {
        index.removeAll()
        insertionOrder.removeAll()
        positionCache.removeAll()
    }

    /// Number of indexed articles.
    var count: Int { return index.count }

    // MARK: - Duplicate Detection

    /// Scan all indexed articles and return duplicate groups.
    ///
    /// Uses union-find clustering with pairwise verification to avoid
    /// the greedy single-pass problem where articles B and C can end up
    /// grouped together via a shared neighbor A even though B and C
    /// themselves are not similar (see issue #25).
    func findDuplicates() -> DeduplicationResult {
        let start = Date()
        let links = insertionOrder.filter { index[$0] != nil }

        // Build a union-find structure over link indices
        var parent = Array(0..<links.count)
        var rank = Array(repeating: 0, count: links.count)

        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x {
                parent[x] = parent[parent[x]]  // path compression
                x = parent[x]
            }
            return x
        }

        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            guard ra != rb else { return }
            if rank[ra] < rank[rb] { parent[ra] = rb }
            else if rank[ra] > rank[rb] { parent[rb] = ra }
            else { parent[rb] = ra; rank[ra] += 1 }
        }

        // Pairwise similarity: only union articles that directly meet
        // the threshold. This ensures every merged pair is genuinely
        // similar — transitivity is explicit via the union-find edges.
        var pairScores: [String: (Double, String)] = [:]

        for i in 0..<links.count {
            guard let fpA = index[links[i]] else { continue }
            for j in (i + 1)..<links.count {
                guard let fpB = index[links[j]] else { continue }
                let (score, reason) = computeSimilarity(fpA, fpB)
                if score >= threshold {
                    union(i, j)
                    let key = "\(i)-\(j)"
                    pairScores[key] = (score, reason)
                }
            }
        }

        // Collect groups from union-find roots
        var rootToMembers: [Int: [Int]] = [:]
        for i in 0..<links.count {
            let root = find(i)
            rootToMembers[root, default: []].append(i)
        }

        var groups: [DuplicateGroup] = []
        for (_, memberIndices) in rootToMembers {
            guard memberIndices.count > 1 else { continue }

            let memberLinks = memberIndices.map { links[$0] }

            // Find best pairwise confidence within this group
            var bestConfidence = 0.0
            var bestReason = ""
            for mi in 0..<memberIndices.count {
                for mj in (mi + 1)..<memberIndices.count {
                    let a = min(memberIndices[mi], memberIndices[mj])
                    let b = max(memberIndices[mi], memberIndices[mj])
                    if let (score, reason) = pairScores["\(a)-\(b)"] {
                        if score > bestConfidence {
                            bestConfidence = score
                            bestReason = reason
                        }
                    }
                }
            }

            let canonical = selectCanonical(memberLinks)
            let groupId = stableHash(canonical)

            groups.append(DuplicateGroup(
                id: groupId,
                memberLinks: memberLinks,
                canonicalLink: canonical,
                confidence: bestConfidence,
                reason: bestReason
            ))
        }

        let duration = Date().timeIntervalSince(start)
        let dupCount = groups.reduce(0) { $0 + $1.memberLinks.count - 1 }

        return DeduplicationResult(
            groups: groups,
            totalScanned: links.count,
            duplicateCount: dupCount,
            scanDuration: duration
        )
    }

    /// Check if a specific article has duplicates. Returns the group or nil.
    func duplicatesOf(link: String) -> DuplicateGroup? {
        guard let fp = index[link] else { return nil }

        var members = [link]
        var bestConfidence = 0.0
        var bestReason = ""

        for (otherLink, otherFp) in index {
            guard otherLink != link else { continue }
            let (score, reason) = computeSimilarity(fp, otherFp)
            if score >= threshold {
                members.append(otherLink)
                if score > bestConfidence {
                    bestConfidence = score
                    bestReason = reason
                }
            }
        }

        guard members.count > 1 else { return nil }

        let canonical = selectCanonical(members)
        return DuplicateGroup(
            id: stableHash(canonical),
            memberLinks: members,
            canonicalLink: canonical,
            confidence: bestConfidence,
            reason: bestReason
        )
    }

    /// Compute raw similarity between two indexed articles (for debugging).
    func similarity(linkA: String, linkB: String) -> (score: Double, reason: String)? {
        guard let fpA = index[linkA], let fpB = index[linkB] else { return nil }
        return computeSimilarity(fpA, fpB)
    }

    // MARK: - Similarity Computation

    internal func computeSimilarity(_ a: ArticleFingerprint, _ b: ArticleFingerprint) -> (Double, String) {
        let titleSim = jaccardSimilarity(a.titleNgrams, b.titleNgrams)
        let contentSim = termOverlap(a.contentTerms, b.contentTerms)
        let urlSim = urlSimilarity(a.urlDomainPath, b.urlDomainPath)

        let combined = titleSim * titleWeight + contentSim * contentWeight + urlSim * urlWeight

        var reasons: [(String, Double)] = []
        if titleSim > 0.3 { reasons.append(("title \(pct(titleSim))", titleSim)) }
        if contentSim > 0.3 { reasons.append(("content \(pct(contentSim))", contentSim)) }
        if urlSim > 0.3 { reasons.append(("url \(pct(urlSim))", urlSim)) }

        let reason: String
        if reasons.isEmpty {
            reason = "combined \(pct(combined))"
        } else {
            reasons.sort { $0.1 > $1.1 }
            reason = reasons.map { $0.0 }.joined(separator: " + ")
        }

        return (combined, reason)
    }

    // MARK: - Text Processing

    internal func normalizeText(_ text: String) -> String {
        let lower = text.lowercased()
        var result = ""
        result.reserveCapacity(lower.count)
        var lastWasSpace = true

        for char in lower {
            if char.isLetter || char.isNumber {
                result.append(char)
                lastWasSpace = false
            } else if !lastWasSpace {
                result.append(" ")
                lastWasSpace = true
            }
        }

        return result.trimmingCharacters(in: .whitespaces)
    }

    internal func characterNgrams(_ text: String, n: Int) -> Set<String> {
        guard text.count >= n else {
            return text.isEmpty ? [] : [text]
        }

        var ngrams = Set<String>()
        let chars = Array(text)
        for i in 0...(chars.count - n) {
            ngrams.insert(String(chars[i..<(i + n)]))
        }
        return ngrams
    }

    internal func extractTopTerms(_ text: String, count: Int) -> [String: Int] {
        let normalized = normalizeText(text)
        let words = normalized.split(separator: " ").map(String.init)

        let filtered = words.filter { word in
            word.count >= 3 && !ArticleDeduplicator.stopWords.contains(word)
        }

        var freq: [String: Int] = [:]
        for word in filtered {
            freq[word, default: 0] += 1
        }

        let sorted = freq.sorted { $0.value > $1.value }
        var result: [String: Int] = [:]
        for (i, pair) in sorted.enumerated() {
            if i >= count { break }
            result[pair.key] = pair.value
        }
        return result
    }

    internal func extractDomainPath(_ urlString: String) -> String {
        guard let url = URL(string: urlString) else {
            return urlString.lowercased()
        }
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        let cleanHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return cleanHost + path
    }

    // MARK: - Similarity Metrics

    internal func jaccardSimilarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 0.0 }
        let intersection = a.intersection(b).count
        let union = a.union(b).count
        return Double(intersection) / Double(union)
    }

    internal func termOverlap(_ a: [String: Int], _ b: [String: Int]) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 0.0 }

        let keysA = Set(a.keys)
        let keysB = Set(b.keys)
        let shared = keysA.intersection(keysB)

        guard !shared.isEmpty else { return 0.0 }

        var sharedSum = 0
        var totalA = 0
        var totalB = 0

        for key in keysA { totalA += a[key]! }
        for key in keysB { totalB += b[key]! }
        for key in shared { sharedSum += min(a[key]!, b[key]!) }

        let denom = sqrt(Double(totalA) * Double(totalB))
        guard denom > 0 else { return 0.0 }

        return Double(sharedSum) / denom
    }

    internal func urlSimilarity(_ a: String, _ b: String) -> Double {
        guard !a.isEmpty && !b.isEmpty else { return 0.0 }
        if a == b { return 1.0 }

        let partsA = splitDomainPath(a)
        let partsB = splitDomainPath(b)

        if partsA.domain == partsB.domain && !partsA.domain.isEmpty {
            let pathSim = jaccardSimilarity(
                characterNgrams(partsA.path, n: 4),
                characterNgrams(partsB.path, n: 4)
            )
            return 0.3 + 0.7 * pathSim
        }

        if !partsA.path.isEmpty && !partsB.path.isEmpty {
            let pathSim = jaccardSimilarity(
                characterNgrams(partsA.path, n: 4),
                characterNgrams(partsB.path, n: 4)
            )
            if pathSim > 0.7 { return 0.4 * pathSim }
        }

        return 0.0
    }

    private func splitDomainPath(_ domainPath: String) -> (domain: String, path: String) {
        guard let slashIndex = domainPath.firstIndex(of: "/") else {
            return (domainPath, "")
        }
        let domain = String(domainPath[..<slashIndex])
        let path = String(domainPath[slashIndex...])
        return (domain, path)
    }

    // MARK: - Canonical Selection

    private func selectCanonical(_ links: [String]) -> String {
        var best = links[0]
        var bestOrder = positionCache[best] ?? Int.max
        var bestTitleLen = index[best]?.titleLength ?? Int.max

        for link in links.dropFirst() {
            let order = positionCache[link] ?? Int.max
            let titleLen = index[link]?.titleLength ?? Int.max

            if order < bestOrder || (order == bestOrder && titleLen < bestTitleLen) {
                best = link
                bestOrder = order
                bestTitleLen = titleLen
            }
        }

        return best
    }

    // MARK: - Utilities

    private func pct(_ value: Double) -> String {
        return "\(Int(value * 100))%"
    }

    /// Compute a stable, collision-resistant hash for group IDs using SHA-256.
    /// Previous implementation used djb2 (UInt64) which has a high collision
    /// probability at scale — two different canonical links mapping to the
    /// same group ID would incorrectly merge unrelated duplicate groups.
    /// This mirrors the fix applied to ImageCache.diskPath (see commit history).
    private func stableHash(_ text: String) -> String {
        let data = Data(text.utf8)
        let digest = SHA256.hash(data: data)
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Stop Words

    static let stopWords: Set<String> = [
        "the", "and", "for", "are", "but", "not", "you", "all", "can",
        "had", "her", "was", "one", "our", "out", "has", "his", "how",
        "its", "may", "new", "now", "old", "see", "way", "who", "did",
        "get", "got", "him", "let", "say", "she", "too", "use", "with",
        "this", "that", "have", "from", "they", "been", "said", "each",
        "will", "than", "them", "then", "what", "when", "were", "your",
        "into", "more", "some", "such", "just", "also", "over", "only",
        "very", "most", "both", "much", "many", "well", "back", "even",
        "about", "after", "could", "would", "other", "which", "their",
        "there", "first", "being", "those", "still", "where", "every",
        "should", "before", "between", "through", "because", "during",
    ]
}
