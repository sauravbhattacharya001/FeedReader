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
    /// Input data exceeded the configured maximum size.
    /// Defends against unbounded-memory DoS from a maliciously
    /// large OPML payload.
    case payloadTooLarge(bytes: Int, max: Int)
    /// The OPML document declared an external entity. These are
    /// rejected outright to prevent XML External Entity (XXE) attacks
    /// (CWE-611) - e.g. exfiltrating local files via `file://` SYSTEM
    /// entities or hitting internal services via `http://` SYSTEM
    /// entities. Defence-in-depth on top of XMLParser's default of
    /// `shouldResolveExternalEntities = false`.
    case externalEntityRejected

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
        case .payloadTooLarge(let bytes, let max):
            return "OPML payload is \(bytes) bytes, exceeds maximum of \(max)."
        case .externalEntityRejected:
            return "OPML document declares an external entity, which is not permitted."
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

    // MARK: - Limits

    /// Default maximum accepted OPML payload size, in bytes.
    ///
    /// 16 MiB is comfortably above the size of even the largest real-world
    /// OPML exports (a 5,000-feed subscription list is typically < 2 MiB)
    /// while preventing pathological inputs from forcing the XML parser to
    /// allocate unbounded memory. Override via `importOPML(from:maxBytes:)`.
    public static let defaultMaxOPMLBytes = 16 * 1024 * 1024

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
        return try importOPML(from: data, maxBytes: defaultMaxOPMLBytes)
    }

    /// Import feed subscriptions from OPML data with an explicit size cap.
    ///
    /// Use this overload when you need a tighter (or, with care, looser)
    /// limit than the default. The cap exists to prevent a malicious or
    /// corrupted OPML file from forcing unbounded memory allocation in
    /// the XML parser.
    ///
    /// - Parameters:
    ///   - data: UTF-8 encoded OPML XML data.
    ///   - maxBytes: Maximum accepted payload size in bytes. Inputs larger
    ///     than this are rejected before any parsing begins.
    /// - Returns: Array of `FeedItem` objects (all enabled by default).
    /// - Throws:
    ///   - `OPMLError.invalidData` when the buffer is empty.
    ///   - `OPMLError.payloadTooLarge` when `data.count > maxBytes`.
    ///   - `OPMLError.externalEntityRejected` when the OPML declares an
    ///     external entity (XXE defense - CWE-611).
    ///   - `OPMLError.parsingFailed` when the XML parser reports an error.
    ///   - `OPMLError.noFeedsFound` when no valid feed outlines are present.
    public static func importOPML(from data: Data, maxBytes: Int) throws -> [FeedItem] {
        guard !data.isEmpty else { throw OPMLError.invalidData }
        guard data.count <= maxBytes else {
            throw OPMLError.payloadTooLarge(bytes: data.count, max: maxBytes)
        }

        let parser = OPMLParseDelegate()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        // Defense-in-depth: XMLParser defaults to not resolving external
        // entities, but we set both flags explicitly so a future SDK
        // change or accidental override can't quietly re-enable XXE.
        xmlParser.shouldResolveExternalEntities = false
        xmlParser.shouldProcessNamespaces = false

        let success = xmlParser.parse()

        if parser.didSeeExternalEntity {
            throw OPMLError.externalEntityRejected
        }

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

    // MARK: - URL Validation (SSRF Protection)

    /// Allowed URL schemes for imported feeds.
    private static let allowedSchemes: Set<String> = ["https", "http"]

    /// Validate that an imported feed URL is safe for network access.
    /// Checks scheme (http/https only), host presence, and rejects
    /// private/reserved/loopback addresses to prevent SSRF (CWE-918).
    ///
    /// Mirrors URLValidator logic from the iOS target for use in the
    /// platform-independent FeedReaderCore SPM library.
    static func isSafeFeedURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              allowedSchemes.contains(scheme),
              let host = url.host, !host.isEmpty else {
            return false
        }
        return !isPrivateOrReserved(host: host)
    }

    /// Check if a hostname is private, loopback, link-local, or reserved.
    private static func isPrivateOrReserved(host: String) -> Bool {
        let lower = host.lowercased()

        // Special hostnames
        if lower == "localhost"
            || lower.hasSuffix(".localhost")
            || lower.hasSuffix(".local")
            || lower.hasSuffix(".internal")
            || lower == "metadata.google.internal" {
            return true
        }

        // Bracket-stripped IPv6
        let cleaned: String
        if lower.hasPrefix("[") && lower.hasSuffix("]") {
            cleaned = String(lower.dropFirst().dropLast())
        } else {
            cleaned = lower
        }

        // IPv6 loopback
        if cleaned == "::1" || cleaned == "0:0:0:0:0:0:0:1" { return true }
        // fe80::/10 link-local
        if cleaned.hasPrefix("fe8") || cleaned.hasPrefix("fe9")
            || cleaned.hasPrefix("fea") || cleaned.hasPrefix("feb") { return true }
        // fc00::/7 unique-local
        if cleaned.hasPrefix("fd") || cleaned.hasPrefix("fc") { return true }
        // IPv4-mapped IPv6
        if cleaned.hasPrefix("::ffff:") {
            return isPrivateIPv4(String(cleaned.dropFirst(7)))
        }

        return isPrivateIPv4(cleaned)
    }

    /// Parse and check an IPv4 address against private/reserved ranges.
    private static func isPrivateIPv4(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4 else { return false }
        let (a, b, _, _) = (parts[0], parts[1], parts[2], parts[3])

        if a == 127 { return true }            // loopback
        if a == 10 { return true }             // 10.0.0.0/8
        if a == 172 && (b >= 16 && b <= 31) { return true } // 172.16.0.0/12
        if a == 192 && b == 168 { return true } // 192.168.0.0/16
        if a == 169 && b == 254 { return true } // link-local + cloud metadata
        if a == 100 && (b >= 64 && b <= 127) { return true } // CGN
        if a == 0 { return true }              // "this" network
        if a == 255 { return true }            // broadcast
        return false
    }

    // MARK: - Helpers

    /// Delegates to `TextUtilities.escapeXML` for single-pass XML escaping.
    private static func escapeXML(_ string: String) -> String {
        return TextUtilities.escapeXML(string)
    }
}

// MARK: - OPMLParseDelegate

/// Internal XML parser delegate for OPML documents.
private class OPMLParseDelegate: NSObject, XMLParserDelegate {

    var feeds: [FeedItem] = []

    /// Set to `true` if the document declared any external entity, so the
    /// caller can convert this into a hard `externalEntityRejected` error
    /// rather than silently returning whatever feeds happened to parse
    /// before the offending DTD. We do not call `parser.abortParsing()`
    /// here because doing so triggers a generic XML error that's harder
    /// for callers to distinguish from real parse failures.
    var didSeeExternalEntity = false

    /// Track seen URLs for deduplication (case-insensitive).
    private var seenURLs = Set<String>()

    // MARK: - XXE Defense

    func parser(_ parser: XMLParser,
                foundExternalEntityDeclarationWithName name: String,
                publicID: String?, systemID: String?) {
        didSeeExternalEntity = true
        parser.abortParsing()
    }

    func parser(_ parser: XMLParser,
                foundUnparsedEntityDeclarationWithName name: String,
                publicID: String?, systemID: String?,
                notationName: String?) {
        didSeeExternalEntity = true
        parser.abortParsing()
    }

    func parser(_ parser: XMLParser,
                foundNotationDeclarationWithName name: String,
                publicID: String?, systemID: String?) {
        // Notation declarations only appear in DTDs; treat as suspicious.
        didSeeExternalEntity = true
        parser.abortParsing()
    }

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

        // Validate imported feed URLs to prevent SSRF via malicious OPML
        // files containing file://, javascript://, or private-network URLs
        // (e.g. 169.254.169.254, 10.x.x.x). Without this check, a crafted
        // OPML could inject internal-network feeds that the app would then
        // fetch, leaking data or hitting cloud metadata endpoints (CWE-918).
        guard OPMLManager.isSafeFeedURL(trimmedURL) else { return }

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
