//
//  FeedDiscoveryManager.swift
//  FeedReader
//
//  Auto-discovers RSS/Atom feeds from a website URL. Looks for
//  <link rel="alternate"> tags in HTML, then probes common feed paths
//  as a fallback. Returns discovered feeds with titles and URLs.
//

import Foundation

// MARK: - DiscoveredFeed

/// A feed found via auto-discovery.
struct DiscoveredFeed: Equatable {
    /// The feed URL.
    let url: String
    /// The feed title (from HTML link tag or parsed feed).
    let title: String
    /// How the feed was found.
    let source: DiscoverySource
    
    enum DiscoverySource: String, Equatable {
        case linkTag = "link-tag"
        case commonPath = "common-path"
        case directURL = "direct-url"
    }
}

// MARK: - FeedDiscoveryManager

/// Discovers RSS/Atom feeds from website URLs.
///
/// Two-phase discovery:
/// 1. Parse HTML for `<link rel="alternate" type="application/rss+xml">`
///    and `type="application/atom+xml"` tags.
/// 2. If no feeds found, probe common feed paths (`/feed`, `/rss`,
///    `/atom.xml`, `/feed.xml`, etc.).
///
/// Usage:
///
///     let manager = FeedDiscoveryManager()
///     let feeds = manager.discoverFromHTML(htmlString, baseURL: siteURL)
///     // Or parse raw link tags:
///     let feeds = FeedDiscoveryManager.extractFeedLinks(from: htmlString, baseURL: siteURL)
///
class FeedDiscoveryManager {
    
    // MARK: - Constants
    
    /// Common RSS/Atom feed paths to probe when link-tag discovery finds nothing.
    static let commonFeedPaths: [String] = [
        "/feed",
        "/feed/",
        "/rss",
        "/rss/",
        "/rss.xml",
        "/atom.xml",
        "/feed.xml",
        "/index.xml",
        "/feed/rss",
        "/feed/atom",
        "/feeds/posts/default",   // Blogger
        "/?feed=rss2",            // WordPress
        "/blog/feed",
        "/blog/rss",
        "/blog/feed.xml",
        "/news/rss",
        "/news/feed",
    ]
    
    /// Content types that indicate an RSS or Atom feed.
    static let feedContentTypes: Set<String> = [
        "application/rss+xml",
        "application/atom+xml",
        "application/xml",
        "text/xml",
        "application/rdf+xml",
    ]
    
    /// Maximum number of feeds to return from discovery.
    static let maxResults = 20
    
    /// Maximum HTML size to parse (5 MB).
    static let maxHTMLSize = 5 * 1024 * 1024
    
    // MARK: - Singleton
    
    static let shared = FeedDiscoveryManager()
    
    // MARK: - HTML Link Tag Discovery
    
    /// Extract feed URLs from HTML `<link>` tags.
    ///
    /// Looks for tags like:
    /// ```html
    /// <link rel="alternate" type="application/rss+xml" title="Feed" href="/feed" />
    /// ```
    ///
    /// - Parameters:
    ///   - html: Raw HTML string to parse.
    ///   - baseURL: The page URL, used to resolve relative href values.
    /// - Returns: Array of discovered feeds (deduped by URL).
    static func extractFeedLinks(from html: String, baseURL: String) -> [DiscoveredFeed] {
        guard !html.isEmpty, html.count <= maxHTMLSize else { return [] }
        
        var feeds: [DiscoveredFeed] = []
        var seenURLs = Set<String>()
        
        // Find <link> tags with type="application/rss+xml" or "application/atom+xml"
        let linkPattern = "<link\\b[^>]*>"
        guard let linkRegex = try? NSRegularExpression(
            pattern: linkPattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        
        let range = NSRange(html.startIndex..., in: html)
        let matches = linkRegex.matches(in: html, options: [], range: range)
        
        for match in matches.prefix(100) { // Cap iterations for safety
            guard let matchRange = Range(match.range, in: html) else { continue }
            let tag = String(html[matchRange])
            
            // Must have rel="alternate"
            guard containsAttribute(tag, name: "rel", value: "alternate") else { continue }
            
            // Must have a feed content type
            guard let typeValue = extractAttribute(tag, name: "type"),
                  feedContentTypes.contains(typeValue.lowercased()) else { continue }
            
            // Extract href
            guard let href = extractAttribute(tag, name: "href"),
                  !href.isEmpty else { continue }
            
            // Resolve relative URL
            let resolvedURL = resolveURL(href, base: baseURL)
            guard !resolvedURL.isEmpty else { continue }
            
            let normalized = normalizeURL(resolvedURL)
            guard !seenURLs.contains(normalized) else { continue }
            seenURLs.insert(normalized)
            
            // Extract title (optional)
            let title = extractAttribute(tag, name: "title") ?? feedTitleFromURL(resolvedURL)
            
            feeds.append(DiscoveredFeed(
                url: resolvedURL,
                title: title,
                source: .linkTag
            ))
            
            if feeds.count >= maxResults { break }
        }
        
        return feeds
    }
    
    /// Discover feeds from raw HTML with optional fallback to common paths.
    ///
    /// - Parameters:
    ///   - html: Raw HTML of the webpage.
    ///   - baseURL: The page URL.
    ///   - includeCommonPaths: If true, appends common feed path candidates
    ///     when no link tags are found.
    /// - Returns: Array of discovered feeds.
    func discoverFromHTML(_ html: String, baseURL: String,
                          includeCommonPaths: Bool = true) -> [DiscoveredFeed] {
        var feeds = FeedDiscoveryManager.extractFeedLinks(from: html, baseURL: baseURL)
        
        // If no link-tag feeds found, try common paths
        if feeds.isEmpty && includeCommonPaths {
            feeds = generateCommonPathCandidates(baseURL: baseURL)
        }
        
        return feeds
    }
    
    /// Generate candidate feed URLs from common paths.
    ///
    /// These are not verified — they're URLs to try fetching.
    ///
    /// - Parameter baseURL: The website URL to derive paths from.
    /// - Returns: Array of candidate feeds from common paths.
    func generateCommonPathCandidates(baseURL: String) -> [DiscoveredFeed] {
        guard let baseOrigin = extractOrigin(from: baseURL) else { return [] }
        
        var candidates: [DiscoveredFeed] = []
        var seenURLs = Set<String>()
        
        for path in FeedDiscoveryManager.commonFeedPaths {
            let candidateURL = baseOrigin + path
            let normalized = FeedDiscoveryManager.normalizeURL(candidateURL)
            guard !seenURLs.contains(normalized) else { continue }
            seenURLs.insert(normalized)
            
            candidates.append(DiscoveredFeed(
                url: candidateURL,
                title: FeedDiscoveryManager.feedTitleFromURL(candidateURL),
                source: .commonPath
            ))
        }
        
        return candidates
    }
    
    /// Check if a string looks like valid RSS/Atom XML content.
    ///
    /// Performs a quick heuristic check — not a full parse.
    ///
    /// - Parameter content: The response body to check.
    /// - Returns: True if the content appears to be a feed.
    static func looksLikeFeed(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        
        // Check for XML declaration or feed root elements
        let lower = trimmed.lowercased().prefix(1000)
        let feedIndicators = [
            "<rss",
            "<feed",
            "<rdf:rdf",
            "<channel>",
            "<atom:feed",
        ]
        return feedIndicators.contains { lower.contains($0) }
    }
    
    /// Validate that a URL looks like a plausible feed URL.
    ///
    /// - Parameter url: The URL to validate.
    /// - Returns: True if the URL has a valid scheme and host.
    static func isValidFeedURL(_ url: String) -> Bool {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        
        // Must be http or https
        let lower = trimmed.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else {
            return false
        }
        
        // Block dangerous schemes that might be disguised
        let blocked = ["javascript:", "data:", "file:", "ftp:"]
        for scheme in blocked {
            if lower.hasPrefix(scheme) { return false }
        }
        
        // Must have a host (at least one dot)
        let afterScheme = lower.hasPrefix("https://")
            ? String(lower.dropFirst(8))
            : String(lower.dropFirst(7))
        guard afterScheme.contains(".") else { return false }
        
        // Host part must not be empty
        let host = afterScheme.components(separatedBy: "/").first ?? ""
        guard !host.isEmpty, host != "." else { return false }
        
        return true
    }
    
    // MARK: - URL Helpers
    
    /// Extract an HTML attribute value from a tag string.
    ///
    /// Handles both single and double quotes.
    ///
    /// - Parameters:
    ///   - tag: The HTML tag string (e.g. `<link rel="alternate" ...>`).
    ///   - name: The attribute name to extract.
    /// - Returns: The attribute value, or nil if not found.
    static func extractAttribute(_ tag: String, name: String) -> String? {
        // Try double quotes: name="value"
        let dqPattern = name + "\\s*=\\s*\"([^\"]*)\""
        if let regex = try? NSRegularExpression(pattern: dqPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
           let valueRange = Range(match.range(at: 1), in: tag) {
            return String(tag[valueRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Try single quotes: name='value'
        let sqPattern = name + "\\s*=\\s*'([^']*)'"
        if let regex = try? NSRegularExpression(pattern: sqPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
           let valueRange = Range(match.range(at: 1), in: tag) {
            return String(tag[valueRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return nil
    }
    
    /// Check if a tag contains an attribute with a specific value.
    static func containsAttribute(_ tag: String, name: String, value: String) -> Bool {
        guard let attrValue = extractAttribute(tag, name: name) else { return false }
        return attrValue.lowercased() == value.lowercased()
    }
    
    /// Resolve a potentially relative URL against a base URL.
    ///
    /// Handles:
    /// - Absolute URLs (returned as-is)
    /// - Protocol-relative (`//example.com/...`)
    /// - Root-relative (`/feed`)
    /// - Relative paths (`feed.xml`)
    ///
    /// - Parameters:
    ///   - href: The URL to resolve (may be relative).
    ///   - base: The base URL to resolve against.
    /// - Returns: The resolved absolute URL, or empty string on failure.
    static func resolveURL(_ href: String, base: String) -> String {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        
        // Already absolute
        if trimmed.lowercased().hasPrefix("http://") ||
           trimmed.lowercased().hasPrefix("https://") {
            return trimmed
        }
        
        // Protocol-relative
        if trimmed.hasPrefix("//") {
            let scheme = base.lowercased().hasPrefix("https") ? "https:" : "http:"
            return scheme + trimmed
        }
        
        // Root-relative
        if trimmed.hasPrefix("/") {
            guard let origin = extractOrigin(from: base) else { return "" }
            return origin + trimmed
        }
        
        // Relative path
        guard let origin = extractOrigin(from: base) else { return "" }
        let basePath = extractPath(from: base)
        let parentPath = basePath.isEmpty ? "/"
            : (basePath as NSString).deletingLastPathComponent
        let separator = parentPath.hasSuffix("/") ? "" : "/"
        return origin + parentPath + separator + trimmed
    }
    
    /// Extract the origin (scheme + host + port) from a URL.
    static func extractOrigin(from url: String) -> String? {
        let lower = url.lowercased()
        let schemeEnd: String.Index
        if lower.hasPrefix("https://") {
            schemeEnd = url.index(url.startIndex, offsetBy: 8)
        } else if lower.hasPrefix("http://") {
            schemeEnd = url.index(url.startIndex, offsetBy: 7)
        } else {
            return nil
        }
        
        let afterScheme = url[schemeEnd...]
        let hostEnd = afterScheme.firstIndex(of: "/") ?? afterScheme.endIndex
        let host = String(afterScheme[..<hostEnd])
        guard !host.isEmpty else { return nil }
        
        let scheme = String(url[..<schemeEnd])
        return scheme + host
    }
    
    /// Extract the path component from a URL.
    static func extractPath(from url: String) -> String {
        let lower = url.lowercased()
        let offset: Int
        if lower.hasPrefix("https://") { offset = 8 }
        else if lower.hasPrefix("http://") { offset = 7 }
        else { return "" }
        
        let afterScheme = String(url.dropFirst(offset))
        guard let slashIndex = afterScheme.firstIndex(of: "/") else { return "/" }
        return String(afterScheme[slashIndex...])
    }
    
    /// Normalize a URL for deduplication (lowercase scheme+host, strip trailing slash).
    static func normalizeURL(_ url: String) -> String {
        var normalized = url.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Lowercase scheme and host
        if let origin = extractOrigin(from: normalized) {
            let path = extractPath(from: normalized)
            normalized = origin.lowercased() + path
        }
        
        // Strip trailing slash for dedup (but not for root "/")
        if normalized.hasSuffix("/") && !normalized.hasSuffix("://") {
            let withoutSlash = String(normalized.dropLast())
            if !withoutSlash.hasSuffix(":/") {
                normalized = withoutSlash
            }
        }
        
        return normalized
    }
    
    /// Generate a human-readable title from a feed URL path.
    static func feedTitleFromURL(_ url: String) -> String {
        let path = extractPath(from: url)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        if path.isEmpty {
            // Use hostname
            if let origin = extractOrigin(from: url) {
                let host = origin.components(separatedBy: "://").last ?? origin
                return "Feed from " + host
            }
            return "Unknown Feed"
        }
        
        // Use last path component, cleaned up
        let lastComponent = (path as NSString).lastPathComponent
            .replacingOccurrences(of: ".xml", with: "")
            .replacingOccurrences(of: ".rss", with: "")
            .replacingOccurrences(of: ".atom", with: "")
        
        let words = lastComponent
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        
        return words.isEmpty ? "Feed" : words.joined(separator: " ")
    }
}
