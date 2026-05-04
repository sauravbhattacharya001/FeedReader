//
//  ReadLaterExporter.swift
//  FeedReader
//
//  Exports articles to third-party read-later services (Pocket,
//  Instapaper, Wallabag) by generating compatible API payloads
//  and shareable formats. Supports batch export, URL-scheme
//  integration for mobile handoff, and export history tracking.
//
//  Features:
//  - Generate Pocket-compatible add URLs and API payloads
//  - Generate Instapaper-compatible bookmarks
//  - Generate Wallabag-compatible API entries
//  - Batch export multiple articles at once
//  - Export as Netscape bookmark HTML (universal import)
//  - Track export history to avoid duplicates
//  - Generate shareable article bundles as JSON
//
//  Persistence: UserDefaults via Codable.
//

import Foundation

// MARK: - Service Definitions

/// Supported read-later services.
enum ReadLaterService: String, Codable, CaseIterable {
    case pocket
    case instapaper
    case wallabag
    case pinboard
    
    var displayName: String {
        switch self {
        case .pocket:      return "Pocket"
        case .instapaper:  return "Instapaper"
        case .wallabag:    return "Wallabag"
        case .pinboard:    return "Pinboard"
        }
    }
    
    /// URL scheme for mobile deep-link integration.
    var urlScheme: String? {
        switch self {
        case .pocket:      return "pocket"
        case .instapaper:  return "x-callback-instapaper"
        case .wallabag:    return nil
        case .pinboard:    return nil
        }
    }
}

// MARK: - Export Models

/// An article prepared for export to a read-later service.
struct ReadLaterArticle: Codable, Equatable {
    let title: String
    let url: String
    let excerpt: String
    let tags: [String]
    let addedDate: Date
    let sourceFeed: String?
    
    init(title: String, url: String, excerpt: String = "", tags: [String] = [], sourceFeed: String? = nil) {
        self.title = title
        self.url = url
        self.excerpt = excerpt
        self.tags = tags
        self.addedDate = Date()
        self.sourceFeed = sourceFeed
    }
    
    /// Create from a Story object.
    init(story: Any, tags: [String] = []) {
        // Uses Any to avoid tight coupling; cast to Story at call site.
        let mirror = Mirror(reflecting: story)
        self.title = mirror.children.first(where: { $0.label == "title" })?.value as? String ?? "Untitled"
        self.url = mirror.children.first(where: { $0.label == "link" })?.value as? String ?? ""
        self.excerpt = {
            let body = mirror.children.first(where: { $0.label == "body" })?.value as? String ?? ""
            if body.count <= 300 { return body }
            return String(body.prefix(297)) + "..."
        }()
        self.tags = tags
        self.addedDate = Date()
        self.sourceFeed = mirror.children.first(where: { $0.label == "sourceFeedName" })?.value as? String
    }
}

/// Record of a completed export.
struct ExportRecord: Codable {
    let articleURL: String
    let service: ReadLaterService
    let exportDate: Date
    let success: Bool
}

/// Result of a batch export operation.
struct ExportResult {
    let service: ReadLaterService
    let exported: [ReadLaterArticle]
    let skippedDuplicates: [ReadLaterArticle]
    let payload: String
    let format: ExportFormat
}

enum ExportFormat: String {
    case json
    case html
    case urlScheme
    case csv
}

// MARK: - ReadLaterExporter

/// Generates export payloads for read-later services and tracks export history.
final class ReadLaterExporter {
    
    // MARK: - Singleton
    
    static let shared = ReadLaterExporter()
    
    // MARK: - Storage Keys
    
    private let historyKey = "ReadLaterExportHistory"
    private let prefsKey = "ReadLaterExportPrefs"
    
    // MARK: - Preferences
    
    struct ExportPreferences: Codable {
        var defaultService: ReadLaterService
        var autoTag: Bool              // Auto-tag with feed name
        var skipDuplicates: Bool       // Skip previously exported articles
        var includeExcerpt: Bool       // Include body excerpt
        var maxExcerptLength: Int
        
        static let defaults = ExportPreferences(
            defaultService: .pocket,
            autoTag: true,
            skipDuplicates: true,
            includeExcerpt: true,
            maxExcerptLength: 300
        )
    }
    
    private(set) var preferences: ExportPreferences
    
    // MARK: - History
    
    private(set) var exportHistory: [ExportRecord]
    
    // MARK: - Init
    
    private init() {
        if let data = UserDefaults.standard.data(forKey: prefsKey),
           let prefs = try? JSONDecoder().decode(ExportPreferences.self, from: data) {
            self.preferences = prefs
        } else {
            self.preferences = .defaults
        }
        
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let records = try? JSONDecoder().decode([ExportRecord].self, from: data) {
            self.exportHistory = records
        } else {
            self.exportHistory = []
        }
    }
    
    // MARK: - Persistence
    
    private func savePreferences() {
        if let data = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(data, forKey: prefsKey)
        }
    }
    
    private func saveHistory() {
        if let data = try? JSONEncoder().encode(exportHistory) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }
    
    // MARK: - Configuration
    
    func updatePreferences(_ prefs: ExportPreferences) {
        preferences = prefs
        savePreferences()
    }
    
    // MARK: - Duplicate Check
    
    func wasExported(_ articleURL: String, to service: ReadLaterService) -> Bool {
        return exportHistory.contains { $0.articleURL == articleURL && $0.service == service && $0.success }
    }
    
    // MARK: - Pocket Export
    
    /// Generate Pocket API-compatible JSON payload for batch add.
    func exportToPocket(_ articles: [ReadLaterArticle]) -> ExportResult {
        let (toExport, skipped) = filterDuplicates(articles, service: .pocket)
        
        let entries: [[String: Any]] = toExport.map { article in
            var entry: [String: Any] = [
                "url": article.url,
                "title": article.title
            ]
            if !article.tags.isEmpty {
                entry["tags"] = article.tags.joined(separator: ",")
            }
            return entry
        }
        
        let payload: [String: Any] = ["actions": entries.enumerated().map { idx, entry in
            var action: [String: Any] = ["action": "add"]
            action.merge(entry) { _, new in new }
            return action
        }]
        
        let jsonData = (try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted)) ?? Data()
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        
        recordExports(toExport, service: .pocket)
        
        return ExportResult(service: .pocket, exported: toExport, skippedDuplicates: skipped, payload: jsonString, format: .json)
    }
    
    /// Generate Pocket URL scheme for a single article (mobile deep-link).
    func pocketURLScheme(for article: ReadLaterArticle) -> String {
        let encoded = article.url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? article.url
        return "pocket://add?url=\(encoded)"
    }
    
    // MARK: - Instapaper Export
    
    /// Generate Instapaper-compatible CSV for bulk import.
    func exportToInstapaper(_ articles: [ReadLaterArticle]) -> ExportResult {
        let (toExport, skipped) = filterDuplicates(articles, service: .instapaper)
        
        var csv = "URL,Title,Selection,Folder\n"
        for article in toExport {
            let title = article.title.replacingOccurrences(of: "\"", with: "\"\"")
            let excerpt = preferences.includeExcerpt ? article.excerpt.replacingOccurrences(of: "\"", with: "\"\"") : ""
            let folder = article.sourceFeed?.replacingOccurrences(of: "\"", with: "\"\"") ?? ""
            csv += "\"\(article.url)\",\"\(title)\",\"\(excerpt)\",\"\(folder)\"\n"
        }
        
        recordExports(toExport, service: .instapaper)
        
        return ExportResult(service: .instapaper, exported: toExport, skippedDuplicates: skipped, payload: csv, format: .csv)
    }
    
    // MARK: - Wallabag Export
    
    /// Generate Wallabag API-compatible JSON entries.
    func exportToWallabag(_ articles: [ReadLaterArticle]) -> ExportResult {
        let (toExport, skipped) = filterDuplicates(articles, service: .wallabag)
        
        let entries: [[String: Any]] = toExport.map { article in
            var entry: [String: Any] = [
                "url": article.url,
                "title": article.title,
                "archive": 0,
                "starred": 0
            ]
            if !article.tags.isEmpty {
                entry["tags"] = article.tags
            }
            if preferences.includeExcerpt && !article.excerpt.isEmpty {
                entry["content"] = article.excerpt
            }
            return entry
        }
        
        let jsonData = (try? JSONSerialization.data(withJSONObject: entries, options: .prettyPrinted)) ?? Data()
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
        
        recordExports(toExport, service: .wallabag)
        
        return ExportResult(service: .wallabag, exported: toExport, skippedDuplicates: skipped, payload: jsonString, format: .json)
    }
    
    // MARK: - Pinboard Export
    
    /// Generate Pinboard API-compatible JSON.
    func exportToPinboard(_ articles: [ReadLaterArticle]) -> ExportResult {
        let (toExport, skipped) = filterDuplicates(articles, service: .pinboard)
        
        let dateFormatter = ISO8601DateFormatter()
        let entries: [[String: String]] = toExport.map { article in
            [
                "href": article.url,
                "description": article.title,
                "extended": preferences.includeExcerpt ? article.excerpt : "",
                "tags": article.tags.joined(separator: " "),
                "dt": dateFormatter.string(from: article.addedDate),
                "shared": "no",
                "toread": "yes"
            ]
        }
        
        let jsonData = (try? JSONSerialization.data(withJSONObject: entries, options: .prettyPrinted)) ?? Data()
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
        
        recordExports(toExport, service: .pinboard)
        
        return ExportResult(service: .pinboard, exported: toExport, skippedDuplicates: skipped, payload: jsonString, format: .json)
    }
    
    // MARK: - Universal Netscape Bookmark HTML
    
    /// Generate Netscape bookmark HTML format (importable by virtually all services).
    func exportAsBookmarkHTML(_ articles: [ReadLaterArticle]) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        var html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
            <DT><H3>FeedReader Export - \(dateFormatter.string(from: Date()))</H3>
            <DL><p>
        """
        
        // Group by feed source
        let grouped = Dictionary(grouping: articles, by: { $0.sourceFeed ?? "Uncategorized" })
        for (feed, feedArticles) in grouped.sorted(by: { $0.key < $1.key }) {
            html += "        <DT><H3>\(feed.htmlEscaped)</H3>\n"
            html += "        <DL><p>\n"
            for article in feedArticles {
                let timestamp = Int(article.addedDate.timeIntervalSince1970)
                html += "            <DT><A HREF=\"\(article.url.htmlEscaped)\" ADD_DATE=\"\(timestamp)\">\(article.title.htmlEscaped)</A>\n"
                if !article.excerpt.isEmpty {
                    html += "            <DD>\(article.excerpt.htmlEscaped)\n"
                }
            }
            html += "        </DL><p>\n"
        }
        
        html += """
            </DL><p>
        </DL><p>
        """
        
        return html
    }
    
    // MARK: - Generic Export
    
    /// Export to the user's default service.
    func export(_ articles: [ReadLaterArticle]) -> ExportResult {
        return export(articles, to: preferences.defaultService)
    }
    
    /// Export to a specific service.
    func export(_ articles: [ReadLaterArticle], to service: ReadLaterService) -> ExportResult {
        switch service {
        case .pocket:      return exportToPocket(articles)
        case .instapaper:  return exportToInstapaper(articles)
        case .wallabag:    return exportToWallabag(articles)
        case .pinboard:    return exportToPinboard(articles)
        }
    }
    
    // MARK: - History Management
    
    /// Get all exports for a given article URL.
    func exportHistory(for articleURL: String) -> [ExportRecord] {
        return exportHistory.filter { $0.articleURL == articleURL }
    }
    
    /// Get export count per service.
    func exportCounts() -> [ReadLaterService: Int] {
        var counts: [ReadLaterService: Int] = [:]
        for record in exportHistory where record.success {
            counts[record.service, default: 0] += 1
        }
        return counts
    }
    
    /// Clear export history (optionally for a specific service).
    func clearHistory(for service: ReadLaterService? = nil) {
        if let service = service {
            exportHistory.removeAll { $0.service == service }
        } else {
            exportHistory.removeAll()
        }
        saveHistory()
    }
    
    /// Total number of successful exports.
    var totalExports: Int {
        return exportHistory.filter(\.success).count
    }
    
    // MARK: - Summary
    
    /// Human-readable export summary.
    func summary() -> String {
        let counts = exportCounts()
        if counts.isEmpty { return "No articles exported yet." }
        
        var lines = ["📤 Read Later Export Summary"]
        lines.append("Total exports: \(totalExports)")
        lines.append("")
        for service in ReadLaterService.allCases {
            if let count = counts[service], count > 0 {
                lines.append("  \(service.displayName): \(count) articles")
            }
        }
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Helpers
    
    private func filterDuplicates(_ articles: [ReadLaterArticle], service: ReadLaterService) -> (export: [ReadLaterArticle], skipped: [ReadLaterArticle]) {
        guard preferences.skipDuplicates else { return (articles, []) }
        
        var toExport: [ReadLaterArticle] = []
        var skipped: [ReadLaterArticle] = []
        
        for article in articles {
            if wasExported(article.url, to: service) {
                skipped.append(article)
            } else {
                toExport.append(article)
            }
        }
        
        return (toExport, skipped)
    }
    
    private func recordExports(_ articles: [ReadLaterArticle], service: ReadLaterService) {
        let records = articles.map { ExportRecord(articleURL: $0.url, service: service, exportDate: Date(), success: true) }
        exportHistory.append(contentsOf: records)
        saveHistory()
    }
    
    private func _ string: String.htmlEscaped -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
