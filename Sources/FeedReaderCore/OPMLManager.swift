//
//  OPMLManager.swift
//  FeedReaderCore
//
//  Import and export feed subscriptions in OPML (Outline Processor Markup
//  Language) format — the standard interchange format for RSS readers.
//
//  Supports OPML 2.0 with <outline> elements. Handles nested category
//  outlines and flat feed lists. Export produces a well-formed OPML 2.0
//  document; import parses any valid OPML 1.0/2.0 file.
//

import Foundation

// MARK: - OPMLError

/// Errors that can occur during OPML import/export.
public enum OPMLError: Error, LocalizedError {
    case invalidData
    case parsingFailed(String)
    case noFeedsFound
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .invalidData:
            return "The OPML data is invalid or empty."
        case .parsingFailed(let detail):
            return "OPML parsing failed: \(detail)"
        case .noFeedsFound:
            return "No feed subscriptions found in the OPML file."
        case .encodingFailed:
            return "Failed to encode OPML document as UTF-8."
        }
    }
}

// MARK: - OPMLManager

/// Handles import and export of feed subscriptions in OPML format.
///
/// ## Export
/// ```swift
/// let feeds = [FeedItem(name: "BBC", url: "https://...", isEnabled: true)]
/// let opmlData = try OPMLManager.export(feeds: feeds, title: "My Feeds")
/// ```
///
/// ## Import
/// ```swift
/// let feeds = try OPMLManager.importOPML(from: opmlData)
/// // feeds: [FeedItem] — all discovered feeds, enabled by default
/// ```
public final class OPMLManager {

    // MARK: - Export

    /// Export an array of `FeedItem` objects to OPML 2.0 XML data.
    ///
    /// - Parameters:
    ///   - feeds: Feed items to export.
    ///   - title: Document title (shown in OPML `<head><title>`).
    /// - Returns: UTF-8 encoded OPML XML data.
    /// - Throws: `OPMLError.encodingFailed` if UTF-8 encoding fails.
    public static func export(feeds: [FeedItem], title: String = "FeedReader Subscriptions") throws -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<opml version=\"2.0\">\n"
        xml += "  <head>\n"
        xml += "    <title>\(escapeXML(title))</title>\n"

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        xml += "    <dateCreated>\(formatter.string(from: Date()))</dateCreated>\n"

        xml += "  </head>\n"
        xml += "  <body>\n"

        for feed in feeds {
            xml += "    <outline"
            xml += " text=\"\(escapeXML(feed.name))\""
            xml += " title=\"\(escapeXML(feed.name))\""
            xml += " type=\"rss\""
            xml += " xmlUrl=\"\(escapeXML(feed.url))\""
            xml += " />\n"
        }

        xml += "  </body>\n"
        xml += "</opml>\n"

        guard let data = xml.data(using: .utf8) else {
            throw OPMLError.encodingFailed
        }
        return data
    }

    /// Export feeds to an OPML string.
    public static func exportString(feeds: [FeedItem], title: String = "FeedReader Subscriptions") throws -> String {
        let data = try export(feeds: feeds, title: title)
        guard let string = String(data: data, encoding: .utf8) else {
            throw OPMLError.encodingFailed
        }
        return string
    }

    // MARK: - Import

    /// Import feed subscriptions from OPML data.
    ///
    /// Walks all `<outline>` elements recursively. Any outline with an
    /// `xmlUrl` attribute is treated as a feed subscription.
    ///
    /// - Parameter data: UTF-8 encoded OPML XML data.
    /// - Returns: Array of `FeedItem` objects (all enabled by default).
    /// - Throws: `OPMLError` on invalid data or if no feeds are found.
    public static func importOPML(from data: Data) throws -> [FeedItem] {
        guard !data.isEmpty else { throw OPMLError.invalidData }

        let parser = OPMLParseDelegate()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        let success = xmlParser.parse()

        if !success, let error = xmlParser.parserError {
            throw OPMLError.parsingFailed(error.localizedDescription)
        }

        guard !parser.feeds.isEmpty else {
            throw OPMLError.noFeedsFound
        }

        return parser.feeds
    }

    /// Import feeds from an OPML string.
    public static func importOPML(from string: String) throws -> [FeedItem] {
        guard let data = string.data(using: .utf8) else {
            throw OPMLError.invalidData
        }
        return try importOPML(from: data)
    }

    // MARK: - Helpers

    /// Escape special XML characters in attribute values and text content.
    private static func escapeXML(_ string: String) -> String {
        var result = string
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&apos;")
        return result
    }
}

// MARK: - OPMLParseDelegate

/// Internal XML parser delegate for OPML documents.
private class OPMLParseDelegate: NSObject, XMLParserDelegate {

    var feeds: [FeedItem] = []

    /// Track seen URLs for deduplication (case-insensitive).
    private var seenURLs = Set<String>()

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {

        guard elementName.lowercased() == "outline" else { return }

        // An outline with xmlUrl is a feed subscription.
        guard let xmlUrl = attributeDict["xmlUrl"] ?? attributeDict["xmlurl"],
              !xmlUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let trimmedURL = xmlUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = trimmedURL.lowercased()
        guard !seenURLs.contains(key) else { return }
        seenURLs.insert(key)

        // Prefer "title" over "text" for the display name; fall back to URL.
        let name = (attributeDict["title"] ?? attributeDict["text"])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? trimmedURL

        let feed = FeedItem(name: name, url: trimmedURL, isEnabled: true)
        feeds.append(feed)
    }
}
