//
//  HTMLEscaping.swift
//  FeedReader
//
//  Shared HTML/XML entity escaping for strings.
//  Consolidates the identical `escapeHTML` implementations previously
//  inlined in ArticleArchiveExporter, ArticleDigestComposer,
//  ArticleReadingListSharer, DigestGenerator, ReadLaterExporter,
//  and ShareManager.
//

import Foundation

extension String {
    /// Escape the five HTML-significant characters to their entity equivalents.
    ///
    /// The ampersand replacement comes first to avoid double-escaping.
    /// Single quotes use the numeric entity `&#39;` (universally supported)
    /// rather than `&apos;` (XML-only, not in HTML4 spec).
    var htmlEscaped: String {
        self.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
