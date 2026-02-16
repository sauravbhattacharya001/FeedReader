//
//  RSSStory.swift
//  FeedReaderCore
//
//  Public model representing a parsed RSS story/article.
//  Provides URL validation and HTML sanitization utilities.
//

import Foundation

/// Represents a single parsed RSS story with title, body, link, and optional image URL.
public class RSSStory: NSObject, @unchecked Sendable {

    // MARK: - Properties

    /// The story title.
    public let title: String

    /// The story body (HTML-stripped description).
    public let body: String

    /// The story's unique link URL.
    public let link: String

    /// Optional image URL for the story thumbnail.
    public let imagePath: String?

    /// Allowed URL schemes for links and images.
    private static let allowedSchemes: Set<String> = ["https", "http"]

    // MARK: - Initialization

    /// Creates a new RSS story.
    /// - Parameters:
    ///   - title: Story title (must not be empty).
    ///   - body: Story description/body text (must not be empty, HTML will be stripped).
    ///   - link: Story URL (must be a valid http/https URL).
    ///   - imagePath: Optional image URL (only accepted if http/https).
    /// - Returns: `nil` if title is empty, body is empty, or link is not a safe URL.
    public init?(title: String, body: String, link: String, imagePath: String? = nil) {
        let sanitized = RSSStory.stripHTML(body)

        self.title = title
        self.body = sanitized
        self.link = link

        if let path = imagePath, RSSStory.isSafeURL(path) {
            self.imagePath = path
        } else {
            self.imagePath = nil
        }

        super.init()

        if title.isEmpty || self.body.isEmpty || !RSSStory.isSafeURL(link) {
            return nil
        }
    }

    // MARK: - URL Validation

    /// Validates that a URL string uses only allowed schemes (https/http).
    /// Rejects `javascript:`, `file:`, `data:`, and other unsafe schemes.
    public static func isSafeURL(_ urlString: String?) -> Bool {
        guard let urlString = urlString,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased() else {
            return false
        }
        return allowedSchemes.contains(scheme)
    }

    // MARK: - HTML Sanitization

    /// Strips HTML tags and decodes common entities from a string.
    public static func stripHTML(_ html: String) -> String {
        let stripped = html.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        return decodeHTMLEntities(stripped).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private

    private static let entityMap: [(entity: String, replacement: Character)] = [
        ("&amp;", "&"),
        ("&lt;", "<"),
        ("&gt;", ">"),
        ("&quot;", "\""),
        ("&#39;", "'"),
        ("&nbsp;", " "),
    ]

    private static func decodeHTMLEntities(_ input: String) -> String {
        guard input.contains("&") else { return input }

        var result = ""
        result.reserveCapacity(input.count)
        var i = input.startIndex

        while i < input.endIndex {
            if input[i] == "&" {
                var matched = false
                let remaining = input[i...]
                for (entity, replacement) in entityMap {
                    if remaining.hasPrefix(entity) {
                        result.append(replacement)
                        i = input.index(i, offsetBy: entity.count)
                        matched = true
                        break
                    }
                }
                if !matched {
                    result.append(input[i])
                    i = input.index(after: i)
                }
            } else {
                result.append(input[i])
                i = input.index(after: i)
            }
        }

        return result
    }

    // MARK: - Equality

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? RSSStory else { return false }
        return self.link == other.link
    }

    public override var hash: Int {
        return link.hashValue
    }
}
