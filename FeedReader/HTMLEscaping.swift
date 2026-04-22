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
    /// Escape the four HTML-significant characters to their entity equivalents.
    ///
    /// The ampersand replacement comes first to avoid double-escaping.
    var htmlEscaped: String {
        self.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
