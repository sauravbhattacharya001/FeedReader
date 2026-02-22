//
//  OPMLManager.swift
//  FeedReader
//
//  OPML (Outline Processor Markup Language) import/export for RSS feeds.
//  Enables feed migration between RSS reader apps using the industry-standard
//  OPML 2.0 format. Supports both file-based and string-based operations.
//

import Foundation

/// Result of an OPML import operation.
struct OPMLImportResult {
    /// Feeds successfully imported (added to FeedManager).
    let imported: [Feed]
    /// Feeds skipped because they already exist.
    let duplicates: [Feed]
    /// Outlines skipped because they had no valid xmlUrl.
    let skipped: Int
    /// Total outline elements found in the OPML file.
    let totalOutlines: Int
    
    var summary: String {
        var parts: [String] = []
        parts.append("\(imported.count) feed\(imported.count == 1 ? "" : "s") imported")
        if !duplicates.isEmpty {
            parts.append("\(duplicates.count) duplicate\(duplicates.count == 1 ? "" : "s") skipped")
        }
        if skipped > 0 {
            parts.append("\(skipped) invalid outline\(skipped == 1 ? "" : "s") skipped")
        }
        return parts.joined(separator: ", ")
    }
}

/// Parsed outline from an OPML file (before import).
struct OPMLOutline {
    let title: String
    let xmlUrl: String
    let htmlUrl: String?
    let category: String?
}

class OPMLManager {
    
    // MARK: - Singleton
    
    static let shared = OPMLManager()
    
    private init() {}
    
    // MARK: - Export
    
    /// Generate OPML 2.0 XML string from the current feeds.
    /// - Parameter includeDisabled: Whether to include disabled feeds (default: true).
    /// - Returns: OPML XML string.
    func exportToString(includeDisabled: Bool = true) -> String {
        let feeds = includeDisabled
            ? FeedManager.shared.feeds
            : FeedManager.shared.enabledFeeds
        return generateOPML(feeds: feeds)
    }
    
    /// Generate OPML from an arbitrary list of feeds (for testing).
    func generateOPML(feeds: [Feed]) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        let dateString = dateFormatter.string(from: Date())
        
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<opml version=\"2.0\">\n"
        xml += "  <head>\n"
        xml += "    <title>FeedReader Subscriptions</title>\n"
        xml += "    <dateCreated>\(escapeXML(dateString))</dateCreated>\n"
        xml += "    <docs>http://opml.org/spec2.opml</docs>\n"
        xml += "  </head>\n"
        xml += "  <body>\n"
        
        for feed in feeds {
            xml += "    <outline type=\"rss\" text=\"\(escapeXML(feed.name))\" "
            xml += "title=\"\(escapeXML(feed.name))\" "
            xml += "xmlUrl=\"\(escapeXML(feed.url))\"/>\n"
        }
        
        xml += "  </body>\n"
        xml += "</opml>\n"
        
        return xml
    }
    
    /// Export feeds to a file URL.
    /// - Parameters:
    ///   - url: Destination file URL.
    ///   - includeDisabled: Whether to include disabled feeds.
    /// - Throws: File write errors.
    func exportToFile(_ url: URL, includeDisabled: Bool = true) throws {
        let opml = exportToString(includeDisabled: includeDisabled)
        try opml.write(to: url, atomically: true, encoding: .utf8)
    }
    
    /// Get a temporary file URL for sharing via UIActivityViewController.
    /// - Parameter includeDisabled: Whether to include disabled feeds.
    /// - Returns: URL to a temporary .opml file.
    func exportToTemporaryFile(includeDisabled: Bool = true) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "FeedReader-\(dateStamp()).opml"
        let fileURL = tempDir.appendingPathComponent(fileName)
        try exportToFile(fileURL, includeDisabled: includeDisabled)
        return fileURL
    }
    
    // MARK: - Import
    
    /// Parse OPML from a string.
    /// - Parameter opmlString: The OPML XML content.
    /// - Returns: Array of parsed outlines.
    func parseOPML(_ opmlString: String) -> [OPMLOutline] {
        guard let data = opmlString.data(using: .utf8) else { return [] }
        return parseOPMLData(data)
    }
    
    /// Parse OPML from raw data.
    /// - Parameter data: The OPML XML data.
    /// - Returns: Array of parsed outlines.
    func parseOPMLData(_ data: Data) -> [OPMLOutline] {
        let parser = OPMLParser(data: data)
        return parser.parse()
    }
    
    /// Parse OPML from a file URL.
    /// - Parameter url: The OPML file URL.
    /// - Returns: Array of parsed outlines.
    func parseOPMLFile(_ url: URL) throws -> [OPMLOutline] {
        let data = try Data(contentsOf: url)
        return parseOPMLData(data)
    }
    
    /// Import feeds from an OPML string into FeedManager.
    /// - Parameters:
    ///   - opmlString: The OPML XML content.
    ///   - enableAll: Whether to enable all imported feeds (default: true).
    /// - Returns: Import result with counts.
    func importFromString(_ opmlString: String, enableAll: Bool = true) -> OPMLImportResult {
        let outlines = parseOPML(opmlString)
        return importOutlines(outlines, enableAll: enableAll)
    }
    
    /// Import feeds from an OPML file URL into FeedManager.
    /// - Parameters:
    ///   - url: The OPML file URL.
    ///   - enableAll: Whether to enable all imported feeds.
    /// - Returns: Import result with counts.
    func importFromFile(_ url: URL, enableAll: Bool = true) throws -> OPMLImportResult {
        let outlines = try parseOPMLFile(url)
        return importOutlines(outlines, enableAll: enableAll)
    }
    
    /// Import parsed outlines into FeedManager.
    func importOutlines(_ outlines: [OPMLOutline], enableAll: Bool = true) -> OPMLImportResult {
        var imported: [Feed] = []
        var duplicates: [Feed] = []
        var skipped = 0
        
        for outline in outlines {
            // Validate URL
            guard let url = URL(string: outline.xmlUrl),
                  let scheme = url.scheme?.lowercased(),
                  (scheme == "https" || scheme == "http"),
                  url.host != nil else {
                skipped += 1
                continue
            }
            
            let feed = Feed(name: outline.title, url: outline.xmlUrl, isEnabled: enableAll)
            
            if FeedManager.shared.feedExists(url: outline.xmlUrl) {
                duplicates.append(feed)
            } else {
                FeedManager.shared.addFeed(feed)
                imported.append(feed)
            }
        }
        
        return OPMLImportResult(
            imported: imported,
            duplicates: duplicates,
            skipped: skipped,
            totalOutlines: outlines.count
        )
    }
    
    // MARK: - Helpers
    
    /// Escape special XML characters.
    func escapeXML(_ string: String) -> String {
        var result = string
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&#39;")
        return result
    }
    
    private func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }
}

// MARK: - OPML XML Parser

/// Lightweight SAX-based parser for OPML files.
/// Extracts outline elements with xmlUrl attributes.
private class OPMLParser: NSObject, XMLParserDelegate {
    
    private let data: Data
    private var outlines: [OPMLOutline] = []
    private var currentCategory: String?
    
    init(data: Data) {
        self.data = data
        super.init()
    }
    
    func parse() -> [OPMLOutline] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return outlines
    }
    
    // MARK: - XMLParserDelegate
    
    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        
        guard elementName.lowercased() == "outline" else { return }
        
        // Check if this is a category/folder outline (has children, no xmlUrl)
        if attributeDict["xmlUrl"] == nil && attributeDict["xmlurl"] == nil {
            // This is a folder — remember it as category context
            currentCategory = attributeDict["text"] ?? attributeDict["title"]
            return
        }
        
        // Extract feed URL (case-insensitive attribute lookup)
        let xmlUrl = attributeDict["xmlUrl"] ?? attributeDict["xmlurl"] ?? attributeDict["XMLURL"]
        guard let feedUrl = xmlUrl, !feedUrl.isEmpty else { return }
        
        // Extract title (prefer text, fallback to title, then URL)
        let title = attributeDict["text"]
            ?? attributeDict["title"]
            ?? feedUrl
        
        let htmlUrl = attributeDict["htmlUrl"] ?? attributeDict["htmlurl"]
        
        let outline = OPMLOutline(
            title: title,
            xmlUrl: feedUrl,
            htmlUrl: htmlUrl,
            category: currentCategory
        )
        
        outlines.append(outline)
    }
    
    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        // When leaving an outline that was a category, clear the category
        // Note: this is simplified — doesn't handle deeply nested categories
        if elementName.lowercased() == "outline" {
            // We can't easily distinguish category end from feed end in SAX,
            // so we keep the last category until a new one is set.
            // This is sufficient for most OPML files (1-level deep folders).
        }
    }
}
