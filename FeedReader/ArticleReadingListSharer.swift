//
//  ArticleReadingListSharer.swift
//  FeedReader
//
//  Generate shareable reading lists as self-contained HTML pages.
//  Users curate collections of articles, add notes, and export
//  as a single HTML file they can share with friends. Recipients
//  see the curated list with article previews and one-click
//  feed subscribe links via feed:// URLs.
//

import Foundation

/// Notification posted when a reading list changes.
extension Notification.Name {
    static let readingListDidChange = Notification.Name("ReadingListDidChangeNotification")
}

// MARK: - Models

/// A curated reading list with articles and metadata.
struct ReadingList: Codable, Identifiable {
    let id: String
    var title: String
    var description: String
    var author: String
    var coverEmoji: String
    var items: [ReadingListItem]
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
    var shareCount: Int
    
    init(title: String, description: String = "", author: String = "Anonymous") {
        self.id = UUID().uuidString
        self.title = title
        self.description = description
        self.author = author
        self.coverEmoji = ReadingList.randomEmoji()
        self.items = []
        self.tags = []
        self.createdAt = Date()
        self.updatedAt = Date()
        self.shareCount = 0
    }
    
    static func randomEmoji() -> String {
        let emojis = ["📚", "📖", "🔖", "📰", "🗞️", "✨", "🌟", "💡", "🧠", "🎯",
                      "🔬", "🌍", "🚀", "💻", "🎨", "🎵", "⚡", "🔥", "🌊", "🏔️"]
        return emojis.randomElement() ?? "📚"
    }
}

/// A single item in a reading list with curator notes.
struct ReadingListItem: Codable, Identifiable {
    let id: String
    var articleLink: String
    var articleTitle: String
    var feedName: String
    var feedURL: String
    var curatorNote: String
    var addedAt: Date
    var sortOrder: Int
    
    init(articleLink: String, articleTitle: String, feedName: String = "", feedURL: String = "", curatorNote: String = "") {
        self.id = UUID().uuidString
        self.articleLink = articleLink
        self.articleTitle = articleTitle
        self.feedName = feedName
        self.feedURL = feedURL
        self.curatorNote = curatorNote
        self.addedAt = Date()
        self.sortOrder = 0
    }
}

/// Format options for exported reading lists.
enum ReadingListExportFormat: String, CaseIterable {
    case html = "HTML"
    case markdown = "Markdown"
    case json = "JSON"
    case opml = "OPML"
}

/// Statistics about a reading list.
struct ReadingListStats {
    let totalItems: Int
    let uniqueFeeds: Int
    let notesCount: Int
    let oldestArticle: Date?
    let newestArticle: Date?
    let topFeeds: [(name: String, count: Int)]
}

// MARK: - Manager

/// Manages curated reading lists and exports them as shareable formats.
class ArticleReadingListSharer {
    
    // MARK: - Singleton
    
    static let shared = ArticleReadingListSharer()
    
    // MARK: - Storage
    
    private let storageKey = "ArticleReadingLists"
    private var lists: [ReadingList] = []
    
    private init() {
        loadLists()
    }
    
    // MARK: - CRUD
    
    /// Create a new reading list.
    @discardableResult
    func createList(title: String, description: String = "", author: String = "Anonymous") -> ReadingList {
        var list = ReadingList(title: title, description: description, author: author)
        list.updatedAt = Date()
        lists.append(list)
        saveLists()
        NotificationCenter.default.post(name: .readingListDidChange, object: nil)
        return list
    }
    
    /// Get all reading lists.
    func allLists() -> [ReadingList] {
        return lists.sorted { $0.updatedAt > $1.updatedAt }
    }
    
    /// Get a specific list by ID.
    func list(withId id: String) -> ReadingList? {
        return lists.first { $0.id == id }
    }
    
    /// Update a reading list's metadata.
    func updateList(id: String, title: String? = nil, description: String? = nil,
                    author: String? = nil, coverEmoji: String? = nil, tags: [String]? = nil) {
        guard let index = lists.firstIndex(where: { $0.id == id }) else { return }
        if let title = title { lists[index].title = title }
        if let description = description { lists[index].description = description }
        if let author = author { lists[index].author = author }
        if let coverEmoji = coverEmoji { lists[index].coverEmoji = coverEmoji }
        if let tags = tags { lists[index].tags = tags }
        lists[index].updatedAt = Date()
        saveLists()
        NotificationCenter.default.post(name: .readingListDidChange, object: nil)
    }
    
    /// Delete a reading list.
    func deleteList(id: String) {
        lists.removeAll { $0.id == id }
        saveLists()
        NotificationCenter.default.post(name: .readingListDidChange, object: nil)
    }
    
    /// Duplicate a reading list.
    @discardableResult
    func duplicateList(id: String) -> ReadingList? {
        guard let original = list(withId: id) else { return nil }
        var copy = ReadingList(title: "\(original.title) (Copy)", description: original.description, author: original.author)
        copy.coverEmoji = original.coverEmoji
        copy.tags = original.tags
        copy.items = original.items.map { item in
            var newItem = ReadingListItem(
                articleLink: item.articleLink,
                articleTitle: item.articleTitle,
                feedName: item.feedName,
                feedURL: item.feedURL,
                curatorNote: item.curatorNote
            )
            newItem.sortOrder = item.sortOrder
            return newItem
        }
        lists.append(copy)
        saveLists()
        NotificationCenter.default.post(name: .readingListDidChange, object: nil)
        return copy
    }
    
    // MARK: - Items
    
    /// Add an article to a reading list.
    @discardableResult
    func addItem(to listId: String, articleLink: String, articleTitle: String,
                 feedName: String = "", feedURL: String = "", curatorNote: String = "") -> ReadingListItem? {
        guard let index = lists.firstIndex(where: { $0.id == listId }) else { return nil }
        // Prevent duplicates
        if lists[index].items.contains(where: { $0.articleLink == articleLink }) { return nil }
        var item = ReadingListItem(
            articleLink: articleLink,
            articleTitle: articleTitle,
            feedName: feedName,
            feedURL: feedURL,
            curatorNote: curatorNote
        )
        item.sortOrder = lists[index].items.count
        lists[index].items.append(item)
        lists[index].updatedAt = Date()
        saveLists()
        NotificationCenter.default.post(name: .readingListDidChange, object: nil)
        return item
    }
    
    /// Remove an item from a reading list.
    func removeItem(itemId: String, from listId: String) {
        guard let index = lists.firstIndex(where: { $0.id == listId }) else { return }
        lists[index].items.removeAll { $0.id == itemId }
        lists[index].updatedAt = Date()
        saveLists()
        NotificationCenter.default.post(name: .readingListDidChange, object: nil)
    }
    
    /// Update a curator note on an item.
    func updateNote(itemId: String, in listId: String, note: String) {
        guard let listIndex = lists.firstIndex(where: { $0.id == listId }),
              let itemIndex = lists[listIndex].items.firstIndex(where: { $0.id == itemId }) else { return }
        lists[listIndex].items[itemIndex].curatorNote = note
        lists[listIndex].updatedAt = Date()
        saveLists()
    }
    
    /// Reorder items in a list.
    func reorderItems(in listId: String, fromIndex: Int, toIndex: Int) {
        guard let listIndex = lists.firstIndex(where: { $0.id == listId }),
              fromIndex >= 0, fromIndex < lists[listIndex].items.count,
              toIndex >= 0, toIndex < lists[listIndex].items.count else { return }
        let item = lists[listIndex].items.remove(at: fromIndex)
        lists[listIndex].items.insert(item, at: toIndex)
        for i in 0..<lists[listIndex].items.count {
            lists[listIndex].items[i].sortOrder = i
        }
        lists[listIndex].updatedAt = Date()
        saveLists()
    }
    
    // MARK: - Statistics
    
    /// Compute stats for a reading list.
    func stats(for listId: String) -> ReadingListStats? {
        guard let readingList = list(withId: listId) else { return nil }
        let items = readingList.items
        let feedCounts = Dictionary(grouping: items, by: { $0.feedName })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { (name: $0.key, count: $0.value) }
        
        return ReadingListStats(
            totalItems: items.count,
            uniqueFeeds: Set(items.map { $0.feedName }).count,
            notesCount: items.filter { !$0.curatorNote.isEmpty }.count,
            oldestArticle: items.map { $0.addedAt }.min(),
            newestArticle: items.map { $0.addedAt }.max(),
            topFeeds: feedCounts
        )
    }
    
    // MARK: - Export
    
    /// Export a reading list in the specified format.
    func export(listId: String, format: ReadingListExportFormat) -> String? {
        guard let readingList = list(withId: listId) else { return nil }
        
        // Track share
        if let index = lists.firstIndex(where: { $0.id == listId }) {
            lists[index].shareCount += 1
            saveLists()
        }
        
        switch format {
        case .html: return exportHTML(readingList)
        case .markdown: return exportMarkdown(readingList)
        case .json: return exportJSON(readingList)
        case .opml: return exportOPML(readingList)
        }
    }
    
    // MARK: - Import
    
    /// Import a reading list from JSON data.
    @discardableResult
    func importFromJSON(_ jsonString: String) -> ReadingList? {
        guard let data = jsonString.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(ReadingList.self, from: data) else { return nil }
        var imported = decoded
        // Give it a new ID to avoid collisions
        let newList = ReadingList(title: imported.title, description: imported.description, author: imported.author)
        var result = newList
        result.coverEmoji = imported.coverEmoji
        result.tags = imported.tags
        result.items = imported.items
        lists.append(result)
        saveLists()
        NotificationCenter.default.post(name: .readingListDidChange, object: nil)
        return result
    }
    
    // MARK: - Search
    
    /// Search across all reading lists.
    func search(query: String) -> [(list: ReadingList, matchingItems: [ReadingListItem])] {
        let lowered = query.lowercased()
        var results: [(list: ReadingList, matchingItems: [ReadingListItem])] = []
        
        for readingList in lists {
            let matchingItems = readingList.items.filter {
                $0.articleTitle.lowercased().contains(lowered) ||
                $0.feedName.lowercased().contains(lowered) ||
                $0.curatorNote.lowercased().contains(lowered)
            }
            let listMatches = readingList.title.lowercased().contains(lowered) ||
                              readingList.description.lowercased().contains(lowered) ||
                              readingList.tags.contains(where: { $0.lowercased().contains(lowered) })
            
            if !matchingItems.isEmpty || listMatches {
                results.append((list: readingList, matchingItems: matchingItems))
            }
        }
        return results
    }
    
    // MARK: - Private: Export Formatters
    
    private func exportHTML(_ list: ReadingList) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        
        let itemsHTML = list.items.sorted(by: { $0.sortOrder < $1.sortOrder }).map { item -> String in
            let noteHTML = item.curatorNote.isEmpty ? "" : """
                <p class="note">💬 \(item.curatorNote.htmlEscaped)</p>
            """
            let feedLink = item.feedURL.isEmpty ? "" : """
                <a href="feed://\(item.feedURL.htmlEscaped)" class="subscribe" title="Subscribe to this feed">＋ Subscribe</a>
            """
            return """
            <div class="item">
                <h3><a href="\(item.articleLink.htmlEscaped)" target="_blank">\(item.articleTitle.htmlEscaped)</a></h3>
                <div class="meta">
                    <span class="feed">\(item.feedName.htmlEscaped)</span>
                    \(feedLink)
                </div>
                \(noteHTML)
            </div>
            """
        }.joined(separator: "\n")
        
        let tagsHTML = list.tags.isEmpty ? "" : """
            <div class="tags">\(list.tags.map { "<span class=\"tag\">\($0.htmlEscaped)</span>" }.joined())</div>
        """
        
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>\(list.title.htmlEscaped) — Reading List</title>
        <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif;
               max-width: 720px; margin: 0 auto; padding: 2rem 1rem;
               background: #fafafa; color: #1a1a1a; line-height: 1.6; }
        @media (prefers-color-scheme: dark) {
            body { background: #1a1a1a; color: #e0e0e0; }
            .item { background: #2a2a2a; border-color: #333; }
            a { color: #6cb4ee; }
            .note { background: #333; color: #ccc; }
            .tag { background: #333; color: #aaa; }
            .meta { color: #888; }
        }
        header { text-align: center; margin-bottom: 2rem; padding-bottom: 1.5rem; border-bottom: 2px solid #eee; }
        .emoji { font-size: 3rem; margin-bottom: 0.5rem; }
        h1 { font-size: 1.8rem; margin-bottom: 0.3rem; }
        .desc { color: #666; font-size: 1rem; margin-bottom: 0.5rem; }
        .author { color: #999; font-size: 0.85rem; }
        .tags { display: flex; gap: 0.4rem; justify-content: center; flex-wrap: wrap; margin-top: 0.7rem; }
        .tag { background: #f0f0f0; padding: 0.15rem 0.6rem; border-radius: 999px; font-size: 0.75rem; color: #666; }
        .count { color: #999; font-size: 0.85rem; margin-bottom: 1rem; }
        .item { background: #fff; border: 1px solid #eee; border-radius: 12px; padding: 1.2rem;
                margin-bottom: 0.8rem; transition: transform 0.15s; }
        .item:hover { transform: translateY(-1px); }
        .item h3 { font-size: 1.05rem; margin-bottom: 0.4rem; }
        .item a { color: #2563eb; text-decoration: none; }
        .item a:hover { text-decoration: underline; }
        .meta { font-size: 0.8rem; color: #999; display: flex; align-items: center; gap: 0.8rem; }
        .feed { font-weight: 500; }
        .subscribe { color: #16a34a; font-weight: 600; text-decoration: none; font-size: 0.75rem; }
        .subscribe:hover { text-decoration: underline; }
        .note { background: #f8f8f0; padding: 0.6rem 0.8rem; border-radius: 8px; margin-top: 0.5rem;
                font-size: 0.85rem; color: #555; font-style: italic; }
        footer { text-align: center; margin-top: 2rem; padding-top: 1rem; border-top: 1px solid #eee;
                 font-size: 0.75rem; color: #bbb; }
        </style>
        </head>
        <body>
        <header>
            <div class="emoji">\(list.coverEmoji)</div>
            <h1>\(list.title.htmlEscaped)</h1>
            <p class="desc">\(list.description.htmlEscaped)</p>
            <p class="author">Curated by \(list.author.htmlEscaped)</p>
            \(tagsHTML)
        </header>
        <p class="count">\(list.items.count) article\(list.items.count == 1 ? "" : "s") · Updated \(dateFormatter.string(from: list.updatedAt))</p>
        \(itemsHTML)
        <footer>
            Created with FeedReader · \(dateFormatter.string(from: list.createdAt))
        </footer>
        </body>
        </html>
        """
    }
    
    private func exportMarkdown(_ list: ReadingList) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        
        var lines: [String] = []
        lines.append("# \(list.coverEmoji) \(list.title)")
        lines.append("")
        if !list.description.isEmpty {
            lines.append("> \(list.description)")
            lines.append("")
        }
        lines.append("*Curated by \(list.author) · \(list.items.count) articles · Updated \(dateFormatter.string(from: list.updatedAt))*")
        if !list.tags.isEmpty {
            lines.append("")
            lines.append("Tags: " + list.tags.map { "`\($0)`" }.joined(separator: " "))
        }
        lines.append("")
        lines.append("---")
        lines.append("")
        
        for (i, item) in list.items.sorted(by: { $0.sortOrder < $1.sortOrder }).enumerated() {
            lines.append("\(i + 1). **[\(item.articleTitle)](\(item.articleLink))**")
            if !item.feedName.isEmpty {
                lines.append("   *from \(item.feedName)*")
            }
            if !item.curatorNote.isEmpty {
                lines.append("   > 💬 \(item.curatorNote)")
            }
            lines.append("")
        }
        
        lines.append("---")
        lines.append("*Created with FeedReader*")
        
        return lines.joined(separator: "\n")
    }
    
    private func exportJSON(_ list: ReadingList) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(list),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }
    
    private func exportOPML(_ list: ReadingList) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        
        let uniqueFeeds = Dictionary(grouping: list.items.filter { !$0.feedURL.isEmpty }, by: { $0.feedURL })
        
        let outlines = uniqueFeeds.map { (url, items) -> String in
            let feedName = items.first?.feedName ?? url
            return "      <outline type=\"rss\" text=\"\(escapeXML(feedName))\" xmlUrl=\"\(escapeXML(url))\" />"
        }.joined(separator: "\n")
        
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head>
            <title>\(escapeXML(list.title))</title>
            <dateCreated>\(dateFormatter.string(from: list.createdAt))</dateCreated>
          </head>
          <body>
            <outline text="\(escapeXML(list.title))">
        \(outlines)
            </outline>
          </body>
        </opml>
        """
    }
    
    // MARK: - Helpers
    
    private func _ string: String.htmlEscaped -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
    
    private func escapeXML(_ string: String) -> String {
        return string.htmlEscaped.replacingOccurrences(of: "'", with: "&apos;")
    }
    
    // MARK: - Persistence
    
    private func saveLists() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(lists) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    private func loadLists() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([ReadingList].self, from: data) {
            lists = decoded
        }
    }
}
