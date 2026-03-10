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

    // MARK: - Cached Date Formatters

    private static let rfc822Formatter = DateFormatting.rfc2822

    private static let iso8601DayFormatter = DateFormatting.isoDate
    
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
    ///
    /// Feeds that have a `category` are grouped inside folder `<outline>`
    /// elements so that categories survive an export → import round-trip.
    /// Uncategorised feeds are emitted at the top level.
    func generateOPML(feeds: [Feed]) -> String {
        let dateString = Self.rfc822Formatter.string(from: Date())
        
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<opml version=\"2.0\">\n"
        xml += "  <head>\n"
        xml += "    <title>FeedReader Subscriptions</title>\n"
        xml += "    <dateCreated>\(escapeXML(dateString))</dateCreated>\n"
        xml += "    <docs>http://opml.org/spec2.opml</docs>\n"
        xml += "  </head>\n"
        xml += "  <body>\n"

        // Group feeds by category, preserving original order within each group.
        var uncategorised: [Feed] = []
        var categoryOrder: [String] = []
        var grouped: [String: [Feed]] = [:]

        for feed in feeds {
            if let cat = feed.category, !cat.isEmpty {
                if grouped[cat] == nil {
                    categoryOrder.append(cat)
                    grouped[cat] = []
                }
                grouped[cat]!.append(feed)
            } else {
                uncategorised.append(feed)
            }
        }

        // Emit folder outlines for each category.
        for cat in categoryOrder {
            xml += "    <outline text=\"\(escapeXML(cat))\" title=\"\(escapeXML(cat))\">\n"
            for feed in grouped[cat]! {
                xml += "      <outline type=\"rss\" text=\"\(escapeXML(feed.name))\" "
                xml += "title=\"\(escapeXML(feed.name))\" "
                xml += "xmlUrl=\"\(escapeXML(feed.url))\"/>\n"
            }
            xml += "    </outline>\n"
        }

        // Emit uncategorised feeds at the top level.
        for feed in uncategorised {
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
        // Size guard: reject input larger than 10 MB to prevent OOM
        // on adversarial or accidentally huge payloads (CWE-400).
        guard opmlString.utf8.count <= 10_485_760 else { return OPMLImportResult(imported: [], duplicates: [], skipped: 0) }

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
            // Validate URL — delegate to URLValidator for scheme, host,
            // and SSRF checks (private/reserved/link-local addresses).
            // Previous check only verified scheme + host != nil, which
            // allowed empty hosts (http:///path) and private IPs
            // (http://169.254.169.254, http://10.0.0.1) through.
            guard URLValidator.validateFeedURL(outline.xmlUrl) != nil else {
                skipped += 1
                continue
            }
            
            let feed = Feed(name: outline.title, url: outline.xmlUrl, isEnabled: enableAll)
            feed.category = outline.category
            
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
        return Self.iso8601DayFormatter.string(from: Date())
    }
}

// MARK: - OPML XML Parser

/// Lightweight SAX-based parser for OPML files.
/// Extracts outline elements with xmlUrl attributes.
private class OPMLParser: NSObject, XMLParserDelegate {
    
    private let data: Data
    private var outlines: [OPMLOutline] = []
    /// Stack of folder names for nested category tracking.
    /// Feeds inherit the nearest enclosing folder as their category.
    private var categoryStack: [String] = []
    private var outlineDepth = 0
    
    init(data: Data) {
        self.data = data
        super.init()
    }
    
    func parse() -> [OPMLOutline] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldResolveExternalEntities = false  // Prevent XXE
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
        outlineDepth += 1
        
        // Check if this is a category/folder outline (has children, no xmlUrl)
        if attributeDict["xmlUrl"] == nil && attributeDict["xmlurl"] == nil {
            // This is a folder — push it onto the category stack
            let folderName = attributeDict["text"] ?? attributeDict["title"]
            categoryStack.append(folderName ?? "")
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
            category: categoryStack.last(where: { !$0.isEmpty })
        )
        
        outlines.append(outline)
    }
    
    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        guard elementName.lowercased() == "outline" else { return }
        // Pop category stack when leaving a folder outline.
        // Folder outlines pushed onto the stack in didStartElement;
        // feed outlines (with xmlUrl) did not push, so we only pop
        // when the depth matches the stack depth (i.e., this closing
        // tag corresponds to a folder, not a feed).
        if categoryStack.count >= outlineDepth {
            categoryStack.removeLast()
        }
        outlineDepth -= 1
    }
}
