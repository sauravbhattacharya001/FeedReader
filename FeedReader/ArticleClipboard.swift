//
//  ArticleClipboard.swift
//  FeedReader
//
//  Cross-article snippet clipboard for research and note-taking.
//  Collects quotes from multiple articles into a unified clipboard
//  with tags, search, and formatted export (Markdown, plain text).
//

import Foundation

/// Notification posted when clipboard contents change.
extension Notification.Name {
    static let articleClipboardDidChange = Notification.Name("ArticleClipboardDidChangeNotification")
}

// MARK: - ClipboardSnippet

/// A single clipped snippet from an article.
class ClipboardSnippet {

    // MARK: - Cached Date Formatters

    private static let mediumDateShortTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static let mediumDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()
    static var supportsSecureCoding: Bool { true }

    /// Unique identifier.
    let id: String

    /// URL of the source article.
    let sourceURL: String

    /// Title of the source article.
    let sourceTitle: String

    /// The clipped text.
    let text: String

    /// Optional user note on this snippet.
    var note: String?

    /// Tags for organizing snippets.
    private(set) var tags: [String]

    /// When the snippet was clipped.
    let clippedDate: Date

    /// Maximum text length.
    static let maxTextLength = 5000

    /// Maximum note length.
    static let maxNoteLength = 1000

    /// Maximum tags per snippet.
    static let maxTags = 10

    /// Maximum tag length.
    static let maxTagLength = 50

    init?(sourceURL: String, sourceTitle: String, text: String,
          note: String? = nil, tags: [String] = [],
          id: String = UUID().uuidString, clippedDate: Date = Date()) {

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, !sourceURL.isEmpty else { return nil }

        self.id = id
        self.sourceURL = sourceURL
        self.sourceTitle = sourceTitle.isEmpty ? "Untitled" : sourceTitle
        self.text = String(trimmedText.prefix(ClipboardSnippet.maxTextLength))
        self.clippedDate = clippedDate

        if let n = note?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            self.note = String(n.prefix(ClipboardSnippet.maxNoteLength))
        }

        self.tags = ClipboardSnippet.sanitizeTags(tags)

        super.init()
    }

    /// Sanitize and deduplicate tags.
    static func sanitizeTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in tags {
            let cleaned = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .prefix(maxTagLength)
            let str = String(cleaned)
            guard !str.isEmpty, !seen.contains(str) else { continue }
            seen.insert(str)
            result.append(str)
            if result.count >= maxTags { break }
        }
        return result
    }

    /// Add a tag. Returns false if at limit, empty, or duplicate.
    @discardableResult
    func addTag(_ tag: String) -> Bool {
        let cleaned = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .prefix(ClipboardSnippet.maxTagLength)
        let str = String(cleaned)
        guard !str.isEmpty, !tags.contains(str),
              tags.count < ClipboardSnippet.maxTags else { return false }
        tags.append(str)
        return true
    }

    /// Remove a tag. Returns false if not found.
    @discardableResult
    func removeTag(_ tag: String) -> Bool {
        let lower = tag.lowercased()
        guard let idx = tags.firstIndex(of: lower) else { return false }
        tags.remove(at: idx)
        return true
    }

    /// Word count of the snippet text.
    var wordCount: Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    // MARK: - NSSecureCoding

    private enum CodingKeys {
        static let id = "snippetId"
        static let sourceURL = "snippetSourceURL"
        static let sourceTitle = "snippetSourceTitle"
        static let text = "snippetText"
        static let note = "snippetNote"
        static let tags = "snippetTags"
        static let clippedDate = "snippetClippedDate"
    }

    func encode(with coder: NSCoder) {
        coder.encode(id as NSString, forKey: CodingKeys.id)
        coder.encode(sourceURL as NSString, forKey: CodingKeys.sourceURL)
        coder.encode(sourceTitle as NSString, forKey: CodingKeys.sourceTitle)
        coder.encode(text as NSString, forKey: CodingKeys.text)
        coder.encode(note as NSString?, forKey: CodingKeys.note)
        coder.encode(tags as NSArray, forKey: CodingKeys.tags)
        coder.encode(clippedDate as NSDate, forKey: CodingKeys.clippedDate)
    }

    required init?(coder: NSCoder) {
        guard let id = coder.decodeObject(of: NSString.self, forKey: CodingKeys.id) as String?,
              let sourceURL = coder.decodeObject(of: NSString.self, forKey: CodingKeys.sourceURL) as String?,
              let sourceTitle = coder.decodeObject(of: NSString.self, forKey: CodingKeys.sourceTitle) as String?,
              let text = coder.decodeObject(of: NSString.self, forKey: CodingKeys.text) as String?,
              let clippedDate = coder.decodeObject(of: NSDate.self, forKey: CodingKeys.clippedDate) as Date? else {
            return nil
        }

        self.id = id
        self.sourceURL = sourceURL
        self.sourceTitle = sourceTitle
        self.text = text
        self.note = coder.decodeObject(of: NSString.self, forKey: CodingKeys.note) as String?
        self.clippedDate = clippedDate

        if let rawTags = coder.decodeObject(of: NSArray.self, forKey: CodingKeys.tags) as? [String] {
            self.tags = ClipboardSnippet.sanitizeTags(rawTags)
        } else {
            self.tags = []
        }

        super.init()
    }
}

// MARK: - ArticleClipboard

/// Manages a cross-article snippet clipboard for collecting research quotes.
///
/// Usage:
///   let clipboard = ArticleClipboard.shared
///
///   // Clip a quote from an article
///   clipboard.clip(sourceURL: "https://example.com/article",
///                  sourceTitle: "Great Article",
///                  text: "An insightful quote from the article.",
///                  tags: ["ai", "research"])
///
///   // Search snippets
///   let results = clipboard.search("insightful")
///
///   // Export as Markdown
///   let markdown = clipboard.exportMarkdown()
///
///   // Export snippets for a specific tag
///   let aiSnippets = clipboard.snippets(tagged: "ai")
///   let tagExport = clipboard.exportMarkdown(snippets: aiSnippets)
///
class ArticleClipboard {

    // MARK: - Singleton

    static let shared = ArticleClipboard()

    // MARK: - Constants

    /// Maximum number of snippets in the clipboard.
    static let maxSnippets = 500

    private static let userDefaultsKey = "ArticleClipboard.snippets"

    // MARK: - Properties

    /// Snippets keyed by ID for O(1) lookup.
    private var snippetsById: [String: ClipboardSnippet]

    /// Ordered list of snippet IDs (newest first).
    private var orderedIds: [String]

    // MARK: - Initialization

    private init() {
        let loaded = ArticleClipboard.loadFromDefaults()
        self.snippetsById = loaded.byId
        self.orderedIds = loaded.ordered
    }

    /// For testing: create with initial snippets.
    init(snippets: [ClipboardSnippet]) {
        var byId = [String: ClipboardSnippet]()
        var ordered = [String]()
        for s in snippets.prefix(ArticleClipboard.maxSnippets) {
            byId[s.id] = s
            ordered.append(s.id)
        }
        self.snippetsById = byId
        self.orderedIds = ordered
    }

    // MARK: - Clip

    /// Add a snippet to the clipboard. Returns the snippet, or nil if invalid
    /// or at capacity.
    @discardableResult
    func clip(sourceURL: String, sourceTitle: String, text: String,
              note: String? = nil, tags: [String] = []) -> ClipboardSnippet? {

        guard snippetsById.count < ArticleClipboard.maxSnippets else { return nil }

        guard let snippet = ClipboardSnippet(
            sourceURL: sourceURL,
            sourceTitle: sourceTitle,
            text: text,
            note: note,
            tags: tags
        ) else { return nil }

        snippetsById[snippet.id] = snippet
        orderedIds.insert(snippet.id, at: 0)
        persistAndNotify()
        return snippet
    }

    // MARK: - Remove

    /// Remove a snippet by ID. Returns true if found and removed.
    @discardableResult
    func remove(id: String) -> Bool {
        guard snippetsById.removeValue(forKey: id) != nil else { return false }
        orderedIds.removeAll { $0 == id }
        persistAndNotify()
        return true
    }

    /// Remove all snippets.
    func removeAll() {
        guard !snippetsById.isEmpty else { return }
        snippetsById.removeAll()
        orderedIds.removeAll()
        persistAndNotify()
    }

    // MARK: - Query

    /// Get a snippet by ID.
    func snippet(id: String) -> ClipboardSnippet? {
        snippetsById[id]
    }

    /// All snippets in order (newest first).
    var allSnippets: [ClipboardSnippet] {
        orderedIds.compactMap { snippetsById[$0] }
    }

    /// Number of snippets.
    var count: Int { snippetsById.count }

    /// Whether the clipboard is empty.
    var isEmpty: Bool { snippetsById.isEmpty }

    /// Whether the clipboard is at capacity.
    var isFull: Bool { snippetsById.count >= ArticleClipboard.maxSnippets }

    /// Snippets from a specific article URL.
    func snippets(fromArticle url: String) -> [ClipboardSnippet] {
        allSnippets.filter { $0.sourceURL == url }
    }

    /// Snippets with a specific tag.
    func snippets(tagged tag: String) -> [ClipboardSnippet] {
        let lower = tag.lowercased()
        return allSnippets.filter { $0.tags.contains(lower) }
    }

    /// All unique tags across all snippets, sorted alphabetically.
    var allTags: [String] {
        var tagSet = Set<String>()
        for snippet in snippetsById.values {
            for tag in snippet.tags {
                tagSet.insert(tag)
            }
        }
        return tagSet.sorted()
    }

    /// Tag usage counts: [tag: count], sorted by count descending.
    var tagCounts: [(tag: String, count: Int)] {
        var counts = [String: Int]()
        for snippet in snippetsById.values {
            for tag in snippet.tags {
                counts[tag, default: 0] += 1
            }
        }
        return counts.map { (tag: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    /// Unique source article count.
    var sourceCount: Int {
        Set(snippetsById.values.map { $0.sourceURL }).count
    }

    /// Total word count across all snippets.
    var totalWordCount: Int {
        snippetsById.values.reduce(0) { $0 + $1.wordCount }
    }

    // MARK: - Search

    /// Search snippets by text, note, source title, or tags.
    /// Case-insensitive substring match.
    func search(_ query: String) -> [ClipboardSnippet] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return allSnippets }

        return allSnippets.filter { snippet in
            snippet.text.lowercased().contains(q) ||
            snippet.sourceTitle.lowercased().contains(q) ||
            (snippet.note?.lowercased().contains(q) ?? false) ||
            snippet.tags.contains(where: { $0.contains(q) })
        }
    }

    // MARK: - Update

    /// Update a snippet's note. Returns false if not found.
    @discardableResult
    func updateNote(id: String, note: String?) -> Bool {
        guard let snippet = snippetsById[id] else { return false }
        if let n = note?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            snippet.note = String(n.prefix(ClipboardSnippet.maxNoteLength))
        } else {
            snippet.note = nil
        }
        persistAndNotify()
        return true
    }

    /// Add a tag to a snippet. Returns false if not found or tag rejected.
    @discardableResult
    func addTag(id: String, tag: String) -> Bool {
        guard let snippet = snippetsById[id] else { return false }
        guard snippet.addTag(tag) else { return false }
        persistAndNotify()
        return true
    }

    /// Remove a tag from a snippet. Returns false if not found.
    @discardableResult
    func removeTag(id: String, tag: String) -> Bool {
        guard let snippet = snippetsById[id] else { return false }
        guard snippet.removeTag(tag) else { return false }
        persistAndNotify()
        return true
    }

    // MARK: - Export

    /// Export format options.
    enum ExportFormat {
        case markdown
        case plainText
        case json
    }

    /// Export snippets as formatted text.
    /// - Parameters:
    ///   - snippets: Snippets to export. Defaults to all.
    ///   - format: Output format. Defaults to Markdown.
    ///   - includeMetadata: Whether to include dates, tags, notes.
    func export(snippets: [ClipboardSnippet]? = nil, format: ExportFormat = .markdown,
                includeMetadata: Bool = true) -> String {
        let items = snippets ?? allSnippets
        guard !items.isEmpty else { return format == .json ? "[]" : "" }

        switch format {
        case .markdown:
            return formatMarkdown(items: items, includeMetadata: includeMetadata)
        case .plainText:
            return formatPlainText(items: items, includeMetadata: includeMetadata)
        case .json:
            return formatJSON(items: items)
        }
    }

    /// Export as Markdown document.
    func exportMarkdown(snippets: [ClipboardSnippet]? = nil,
                        includeMetadata: Bool = true) -> String {
        export(snippets: snippets, format: .markdown, includeMetadata: includeMetadata)
    }

    /// Export as plain text.
    func exportPlainText(snippets: [ClipboardSnippet]? = nil,
                         includeMetadata: Bool = true) -> String {
        export(snippets: snippets, format: .plainText, includeMetadata: includeMetadata)
    }

    /// Export as JSON string.
    func exportJSON(snippets: [ClipboardSnippet]? = nil) -> String {
        export(snippets: snippets, format: .json)
    }

    // MARK: - Export Formatting (Private)

    /// Group snippets by source URL, preserving encounter order.
    private func groupBySource(_ items: [ClipboardSnippet])
        -> [(url: String, title: String, snippets: [ClipboardSnippet])] {

        var groups = [(url: String, title: String, snippets: [ClipboardSnippet])]()
        var urlIndex = [String: Int]()

        for snippet in items {
            if let idx = urlIndex[snippet.sourceURL] {
                groups[idx].snippets.append(snippet)
            } else {
                urlIndex[snippet.sourceURL] = groups.count
                groups.append((url: snippet.sourceURL, title: snippet.sourceTitle,
                               snippets: [snippet]))
            }
        }
        return groups
    }

    private func formatMarkdown(items: [ClipboardSnippet], includeMetadata: Bool) -> String {
        let grouped = groupBySource(items)

        var lines: [String] = ["# Research Clipboard", ""]
        lines.append("\(items.count) snippet\(items.count == 1 ? "" : "s") from \(grouped.count) source\(grouped.count == 1 ? "" : "s")")
        lines.append("")

        for group in grouped {
            lines.append("## \(group.title)")
            lines.append("Source: \(group.url)")
            lines.append("")

            for snippet in group.snippets {
                lines.append("> \(snippet.text)")
                lines.append("")

                if includeMetadata {
                    if let note = snippet.note {
                        lines.append("**Note:** \(note)")
                        lines.append("")
                    }
                    var meta: [String] = []
                    if !snippet.tags.isEmpty {
                        meta.append("Tags: \(snippet.tags.map { "#\($0)" }.joined(separator: " "))")
                    }
                    meta.append("Clipped: \(Self.mediumDateShortTimeFormatter.string(from: snippet.clippedDate))")
                    lines.append("*\(meta.joined(separator: " · "))*")
                    lines.append("")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private func formatPlainText(items: [ClipboardSnippet], includeMetadata: Bool) -> String {
        var lines: [String] = ["RESEARCH CLIPBOARD", String(repeating: "=", count: 20), ""]

        for (index, snippet) in items.enumerated() {
            lines.append("[\(index + 1)] \"\(snippet.text)\"")
            lines.append("    — \(snippet.sourceTitle)")

            if includeMetadata {
                if let note = snippet.note {
                    lines.append("    Note: \(note)")
                }
                if !snippet.tags.isEmpty {
                    lines.append("    Tags: \(snippet.tags.joined(separator: ", "))")
                }
            }

            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func formatJSON(items: [ClipboardSnippet]) -> String {
        var jsonArray: [[String: Any]] = []

        for snippet in items {
            var dict: [String: Any] = [
                "id": snippet.id,
                "sourceURL": snippet.sourceURL,
                "sourceTitle": snippet.sourceTitle,
                "text": snippet.text,
                "tags": snippet.tags,
                "clippedDate": Self.mediumDateShortTimeFormatter.string(from: snippet.clippedDate),
                "wordCount": snippet.wordCount
            ]
            if let note = snippet.note {
                dict["note"] = note
            }
            jsonArray.append(dict)
        }

        guard let data = try? JSONSerialization.data(
            withJSONObject: jsonArray,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return "[]" }

        return String(data: data, encoding: .utf8) ?? "[]"
    }

    // MARK: - Statistics

    /// Summary statistics for the clipboard.
    struct ClipboardStats {
        let snippetCount: Int
        let sourceCount: Int
        let totalWordCount: Int
        let tagCount: Int
        let topTags: [(tag: String, count: Int)]
        let oldestClip: Date?
        let newestClip: Date?

        var dateRange: String {
guard let oldest = oldestClip, let newest = newestClip else { return "N/A" }
            if Calendar.current.isDate(oldest, inSameDayAs: newest) {
                return Self.mediumDateFormatter.string(from: oldest)
            }
            return "\(Self.mediumDateFormatter.string(from: oldest)) – \(Self.mediumDateFormatter.string(from: newest))"
        }
    }

    /// Get clipboard statistics.
    var stats: ClipboardStats {
        let items = allSnippets
        let dates = items.map { $0.clippedDate }
        return ClipboardStats(
            snippetCount: items.count,
            sourceCount: sourceCount,
            totalWordCount: totalWordCount,
            tagCount: allTags.count,
            topTags: Array(tagCounts.prefix(5)),
            oldestClip: dates.min(),
            newestClip: dates.max()
        )
    }

    // MARK: - Persistence

    /// Persist to UserDefaults and post change notification.
    /// All mutation methods call this instead of separate save()+notify().
    private func persistAndNotify() {
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: allSnippets as NSArray,
            requiringSecureCoding: true
        ) else { return }
        UserDefaults.standard.set(data, forKey: ArticleClipboard.userDefaultsKey)
        NotificationCenter.default.post(name: .articleClipboardDidChange, object: self)
    }

    private static func loadFromDefaults() -> (byId: [String: ClipboardSnippet], ordered: [String]) {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let array = try? NSKeyedUnarchiver.unarchivedArrayOfObjects(
                ofClass: ClipboardSnippet.self, from: data
              ) else {
            return (byId: [:], ordered: [])
        }

        var byId = [String: ClipboardSnippet]()
        var ordered = [String]()
        for snippet in array {
            byId[snippet.id] = snippet
            ordered.append(snippet.id)
        }
        return (byId: byId, ordered: ordered)
    }
}
