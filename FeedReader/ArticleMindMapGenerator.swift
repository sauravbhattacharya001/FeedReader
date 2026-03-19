//
//  ArticleMindMapGenerator.swift
//  FeedReader
//
//  Generates mind maps from article content, extracting key concepts
//  and their relationships into a visual-friendly tree structure.
//  Helps users grasp article structure at a glance.
//
//  Features:
//  - Extract key concepts from article text via NLP-like heuristics
//  - Build hierarchical mind map with central topic + branches
//  - Detect concept relationships (co-occurrence, proximity)
//  - Assign branch colors and importance weights
//  - Export as JSON, Markdown (indented), and ASCII art
//  - Compare mind maps between articles (shared concepts)
//  - Merge mind maps from multiple articles into a unified view
//  - Cache generated maps with content-hash invalidation
//
//  Persistence: UserDefaults via UserDefaultsCodableStore.
//  Works entirely offline with no external dependencies.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when a mind map is generated or updated.
    static let articleMindMapDidUpdate = Notification.Name("ArticleMindMapDidUpdateNotification")
}

// MARK: - Models

/// A single node in a mind map tree.
struct MindMapNode: Codable, Equatable, Identifiable {
    let id: String
    let label: String
    let weight: Double          // 0.0–1.0 importance
    let category: NodeCategory
    let children: [MindMapNode]

    enum NodeCategory: String, Codable, CaseIterable {
        case central    // Root topic
        case theme      // Major theme / section topic
        case concept    // Key concept or entity
        case detail     // Supporting detail
        case keyword    // Individual keyword leaf
    }
}

/// Complete mind map for an article.
struct ArticleMindMap: Codable, Equatable {
    let articleURL: String
    let articleTitle: String
    let generatedAt: Date
    let wordCount: Int
    let root: MindMapNode
    let conceptCount: Int
    let maxDepth: Int
}

/// Comparison between two mind maps.
struct MindMapComparison: Codable {
    let articleA: String
    let articleB: String
    let sharedConcepts: [String]
    let uniqueToA: [String]
    let uniqueToB: [String]
    let overlapScore: Double // 0.0–1.0
}

/// Merged mind map from multiple articles.
struct MergedMindMap: Codable {
    let articleURLs: [String]
    let mergedAt: Date
    let root: MindMapNode
    let sourceCount: Int
}

/// Cached entry with content hash for invalidation.
private struct MindMapEntry: Codable {
    let map: ArticleMindMap
    let textHash: Int
}

// MARK: - Generator

/// Generates mind maps from article text for visual concept exploration.
///
/// Usage:
/// ```
/// let generator = ArticleMindMapGenerator()
/// let map = generator.generate(
///     url: "https://example.com/article",
///     title: "AI Safety in 2026",
///     text: articleBodyText
/// )
/// print(generator.renderASCII(map))
/// print(generator.renderMarkdown(map))
/// let json = generator.renderJSON(map)
/// ```
final class ArticleMindMapGenerator {

    // MARK: - Storage

    private let store = UserDefaultsCodableStore<[String: MindMapEntry]>(key: "ArticleMindMaps", defaultValue: [:])
    private let maxCached = 100

    // MARK: - Stop Words

    private static let stopWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
        "of", "with", "by", "from", "is", "it", "that", "this", "was", "are",
        "be", "has", "had", "have", "will", "would", "could", "should", "may",
        "can", "do", "did", "not", "so", "if", "its", "as", "up", "out",
        "no", "he", "she", "we", "they", "you", "i", "my", "your", "our",
        "their", "his", "her", "them", "us", "me", "been", "being", "were",
        "what", "when", "where", "which", "who", "how", "than", "then",
        "also", "just", "more", "some", "any", "all", "most", "other",
        "into", "over", "such", "about", "only", "very", "after", "before",
        "between", "each", "few", "these", "those", "both", "while", "does",
        "through", "during", "because", "since", "until", "although", "though",
        "even", "still", "already", "yet", "here", "there", "much", "many",
        "well", "back", "own", "same", "able", "said", "one", "two"
    ]

    // MARK: - Generation

    /// Generate a mind map from article text.
    func generate(url: String, title: String, text: String) -> ArticleMindMap {
        // Check cache
        var cache = store.value
        if let entry = cache[url], entry.textHash == text.hashValue {
            return entry.map
        }

        let words = tokenize(text)
        let wordCount = words.count
        let phrases = extractPhrases(from: text)
        let frequencies = wordFrequencies(words)
        let topConcepts = rankedConcepts(frequencies: frequencies, phrases: phrases, limit: 30)

        // Build tree: central → themes → concepts → details
        let themes = clusterIntoThemes(concepts: topConcepts, text: text)
        let root = buildTree(title: title, themes: themes)
        let maxDepth = computeDepth(root)

        let map = ArticleMindMap(
            articleURL: url,
            articleTitle: title,
            generatedAt: Date(),
            wordCount: wordCount,
            root: root,
            conceptCount: countNodes(root) - 1, // exclude root
            maxDepth: maxDepth
        )

        // Cache
        cache[url] = MindMapEntry(map: map, textHash: text.hashValue)
        if cache.count > maxCached {
            // Evict oldest
            let sorted = cache.sorted { ($0.value.map.generatedAt) < ($1.value.map.generatedAt) }
            let toRemove = sorted.prefix(cache.count - maxCached)
            for (key, _) in toRemove { cache.removeValue(forKey: key) }
        }
        store.value = cache

        NotificationCenter.default.post(name: .articleMindMapDidUpdate, object: self)
        return map
    }

    /// Get cached mind map for URL, if any.
    func cachedMap(for url: String) -> ArticleMindMap? {
        store.value[url]?.map
    }

    /// All cached maps.
    var allMaps: [ArticleMindMap] {
        store.value.values.map(\.map).sorted { $0.generatedAt > $1.generatedAt }
    }

    /// Remove cached map.
    func removeMap(for url: String) {
        var cache = store.value
        cache.removeValue(forKey: url)
        store.value = cache
    }

    /// Clear all cached maps.
    func clearAll() {
        store.value = [:]
    }

    // MARK: - Comparison

    /// Compare two mind maps by shared/unique concepts.
    func compare(_ a: ArticleMindMap, _ b: ArticleMindMap) -> MindMapComparison {
        let conceptsA = Set(collectLabels(a.root).map { $0.lowercased() })
        let conceptsB = Set(collectLabels(b.root).map { $0.lowercased() })
        let shared = conceptsA.intersection(conceptsB).sorted()
        let uniqueA = conceptsA.subtracting(conceptsB).sorted()
        let uniqueB = conceptsB.subtracting(conceptsA).sorted()
        let union = conceptsA.union(conceptsB)
        let overlap = union.isEmpty ? 0.0 : Double(shared.count) / Double(union.count)

        return MindMapComparison(
            articleA: a.articleURL,
            articleB: b.articleURL,
            sharedConcepts: shared,
            uniqueToA: uniqueA,
            uniqueToB: uniqueB,
            overlapScore: overlap
        )
    }

    // MARK: - Merge

    /// Merge multiple mind maps into a unified view.
    func merge(_ maps: [ArticleMindMap]) -> MergedMindMap? {
        guard !maps.isEmpty else { return nil }
        if maps.count == 1 {
            return MergedMindMap(
                articleURLs: [maps[0].articleURL],
                mergedAt: Date(),
                root: maps[0].root,
                sourceCount: 1
            )
        }

        // Collect all theme-level children, merge by similar labels
        var themeMap: [String: [MindMapNode]] = [:]
        for map in maps {
            for child in map.root.children {
                let key = child.label.lowercased()
                themeMap[key, default: []].append(child)
            }
        }

        let mergedThemes: [MindMapNode] = themeMap.map { (key, nodes) in
            // Merge children of same-label themes
            let allChildren = nodes.flatMap(\.children)
            let uniqueChildren = deduplicateNodes(allChildren)
            let avgWeight = nodes.map(\.weight).reduce(0, +) / Double(nodes.count)
            return MindMapNode(
                id: UUID().uuidString,
                label: nodes.first?.label ?? key,
                weight: min(avgWeight * 1.2, 1.0), // Boost for cross-article themes
                category: .theme,
                children: Array(uniqueChildren.prefix(8))
            )
        }
        .sorted { $0.weight > $1.weight }

        let root = MindMapNode(
            id: UUID().uuidString,
            label: "Merged (\(maps.count) articles)",
            weight: 1.0,
            category: .central,
            children: Array(mergedThemes.prefix(10))
        )

        return MergedMindMap(
            articleURLs: maps.map(\.articleURL),
            mergedAt: Date(),
            root: root,
            sourceCount: maps.count
        )
    }

    // MARK: - Rendering: ASCII

    /// Render mind map as ASCII art tree.
    func renderASCII(_ map: ArticleMindMap) -> String {
        var lines: [String] = []
        lines.append("🧠 \(map.root.label)")
        renderASCIINode(map.root, prefix: "", isLast: true, isRoot: true, lines: &lines)
        return lines.joined(separator: "\n")
    }

    private func renderASCIINode(_ node: MindMapNode, prefix: String, isLast: Bool, isRoot: Bool, lines: inout [String]) {
        guard !isRoot else {
            for (i, child) in node.children.enumerated() {
                let last = i == node.children.count - 1
                let connector = last ? "└── " : "├── "
                let icon = iconFor(child.category)
                lines.append("\(prefix)\(connector)\(icon) \(child.label)")
                let childPrefix = prefix + (last ? "    " : "│   ")
                renderASCIINode(child, prefix: childPrefix, isLast: last, isRoot: false, lines: &lines)
            }
            return
        }
        for (i, child) in node.children.enumerated() {
            let last = i == node.children.count - 1
            let connector = last ? "└── " : "├── "
            let icon = iconFor(child.category)
            lines.append("\(prefix)\(connector)\(icon) \(child.label)")
            let childPrefix = prefix + (last ? "    " : "│   ")
            renderASCIINode(child, prefix: childPrefix, isLast: last, isRoot: false, lines: &lines)
        }
    }

    private func iconFor(_ category: MindMapNode.NodeCategory) -> String {
        switch category {
        case .central:  return "🧠"
        case .theme:    return "📌"
        case .concept:  return "💡"
        case .detail:   return "📝"
        case .keyword:  return "🔑"
        }
    }

    // MARK: - Rendering: Markdown

    /// Render mind map as indented Markdown.
    func renderMarkdown(_ map: ArticleMindMap) -> String {
        var lines: [String] = []
        lines.append("# \(map.root.label)")
        lines.append("")
        for theme in map.root.children {
            lines.append("## \(theme.label)")
            for concept in theme.children {
                lines.append("- **\(concept.label)**")
                for detail in concept.children {
                    lines.append("  - \(detail.label)")
                }
            }
            lines.append("")
        }
        lines.append("---")
        lines.append("*\(map.conceptCount) concepts • \(map.wordCount) words • Generated \(formatDate(map.generatedAt))*")
        return lines.joined(separator: "\n")
    }

    // MARK: - Rendering: JSON

    /// Render mind map as pretty-printed JSON string.
    func renderJSON(_ map: ArticleMindMap) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(map) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Private Helpers

    private func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !Self.stopWords.contains($0) }
    }

    private func extractPhrases(from text: String) -> [String: Int] {
        // Extract 2-word and 3-word phrases
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
        var phraseCount: [String: Int] = [:]

        for sentence in sentences {
            let words = sentence.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }

            // Bigrams
            for i in 0..<max(0, words.count - 1) {
                let a = words[i], b = words[i + 1]
                guard a.count > 2, b.count > 2,
                      !Self.stopWords.contains(a), !Self.stopWords.contains(b) else { continue }
                let phrase = "\(a) \(b)"
                phraseCount[phrase, default: 0] += 1
            }

            // Trigrams
            for i in 0..<max(0, words.count - 2) {
                let a = words[i], b = words[i + 1], c = words[i + 2]
                guard a.count > 2, c.count > 2,
                      !Self.stopWords.contains(a), !Self.stopWords.contains(c) else { continue }
                let phrase = "\(a) \(b) \(c)"
                phraseCount[phrase, default: 0] += 1
            }
        }

        return phraseCount.filter { $0.value >= 2 }
    }

    private func wordFrequencies(_ words: [String]) -> [String: Int] {
        var freq: [String: Int] = [:]
        for w in words { freq[w, default: 0] += 1 }
        return freq
    }

    private struct RankedConcept {
        let label: String
        let score: Double
        let isPhrase: Bool
    }

    private func rankedConcepts(frequencies: [String: Int], phrases: [String: Int], limit: Int) -> [RankedConcept] {
        var concepts: [RankedConcept] = []

        // Single words scored by frequency
        let maxFreq = Double(frequencies.values.max() ?? 1)
        for (word, count) in frequencies {
            let score = Double(count) / maxFreq
            concepts.append(RankedConcept(label: word, score: score, isPhrase: false))
        }

        // Phrases get a boost
        let maxPhraseFreq = Double(phrases.values.max() ?? 1)
        for (phrase, count) in phrases {
            let score = (Double(count) / maxPhraseFreq) * 1.5 // Boost phrases
            concepts.append(RankedConcept(label: phrase, score: min(score, 1.0), isPhrase: true))
        }

        // Sort by score, deduplicate (phrases subsume their component words)
        let sorted = concepts.sorted { $0.score > $1.score }
        var result: [RankedConcept] = []
        var seen: Set<String> = []

        for concept in sorted {
            guard result.count < limit else { break }
            let key = concept.label.lowercased()
            if seen.contains(key) { continue }

            // If phrase, mark component words as seen
            if concept.isPhrase {
                for word in key.split(separator: " ").map(String.init) {
                    seen.insert(word)
                }
            }
            seen.insert(key)
            result.append(concept)
        }

        return result
    }

    private struct ThemeCluster {
        let name: String
        let concepts: [RankedConcept]
        let weight: Double
    }

    private func clusterIntoThemes(concepts: [RankedConcept], text: String) -> [ThemeCluster] {
        // Simple clustering: group concepts by co-occurrence in paragraphs
        let paragraphs = text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard !paragraphs.isEmpty else {
            // Fallback: single theme with all concepts
            let weight = concepts.map(\.score).reduce(0, +) / max(Double(concepts.count), 1)
            return [ThemeCluster(name: concepts.first?.label.capitalized ?? "Topic", concepts: concepts, weight: weight)]
        }

        // Assign each concept to the paragraph where it appears most
        var paraGroups: [Int: [RankedConcept]] = [:]
        for concept in concepts {
            var bestPara = 0
            var bestCount = 0
            for (i, para) in paragraphs.enumerated() {
                let lower = para.lowercased()
                let count = lower.components(separatedBy: concept.label).count - 1
                if count > bestCount {
                    bestCount = count
                    bestPara = i
                }
            }
            paraGroups[bestPara, default: []].append(concept)
        }

        // Build themes from paragraph groups
        var themes: [ThemeCluster] = []
        for (_, group) in paraGroups.sorted(by: { $0.key < $1.key }) {
            guard !group.isEmpty else { continue }
            // Theme name = highest-scored concept (prefer phrases)
            let name = group
                .sorted { ($0.isPhrase ? 1 : 0, $0.score) > ($1.isPhrase ? 1 : 0, $1.score) }
                .first!.label.capitalized
            let weight = group.map(\.score).reduce(0, +) / max(Double(group.count), 1)
            themes.append(ThemeCluster(name: name, concepts: group, weight: weight))
        }

        // Limit to 8 themes
        return Array(themes.sorted { $0.weight > $1.weight }.prefix(8))
    }

    private func buildTree(title: String, themes: [ThemeCluster]) -> MindMapNode {
        let themeNodes = themes.map { theme -> MindMapNode in
            let conceptNodes = theme.concepts.prefix(6).map { concept -> MindMapNode in
                // For phrases, split into keyword children
                let keywords: [MindMapNode]
                if concept.isPhrase {
                    keywords = concept.label.split(separator: " ")
                        .filter { $0.count > 2 && !Self.stopWords.contains(String($0)) }
                        .map { word in
                            MindMapNode(
                                id: UUID().uuidString,
                                label: String(word),
                                weight: concept.score * 0.5,
                                category: .keyword,
                                children: []
                            )
                        }
                } else {
                    keywords = []
                }

                return MindMapNode(
                    id: UUID().uuidString,
                    label: concept.label.capitalized,
                    weight: concept.score,
                    category: concept.isPhrase ? .concept : .detail,
                    children: keywords
                )
            }

            return MindMapNode(
                id: UUID().uuidString,
                label: theme.name,
                weight: theme.weight,
                category: .theme,
                children: Array(conceptNodes)
            )
        }

        return MindMapNode(
            id: UUID().uuidString,
            label: title,
            weight: 1.0,
            category: .central,
            children: themeNodes
        )
    }

    private func computeDepth(_ node: MindMapNode) -> Int {
        if node.children.isEmpty { return 0 }
        return 1 + (node.children.map { computeDepth($0) }.max() ?? 0)
    }

    private func countNodes(_ node: MindMapNode) -> Int {
        1 + node.children.map { countNodes($0) }.reduce(0, +)
    }

    private func collectLabels(_ node: MindMapNode) -> [String] {
        [node.label] + node.children.flatMap { collectLabels($0) }
    }

    private func deduplicateNodes(_ nodes: [MindMapNode]) -> [MindMapNode] {
        var seen: Set<String> = []
        return nodes.filter { node in
            let key = node.label.lowercased()
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
