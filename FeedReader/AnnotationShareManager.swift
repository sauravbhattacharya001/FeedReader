//
//  AnnotationShareManager.swift
//  FeedReader
//
//  Share and import article annotations (highlights + notes) as compact
//  base64-encoded strings. Users can export their annotations for any
//  article, share the code with friends, and import received codes to
//  merge annotations into their own library.
//

import Foundation

// MARK: - Shareable Data Models

/// A lightweight, Codable snapshot of a highlight for sharing.
struct ShareableHighlight: Codable, Equatable {
    let selectedText: String
    let color: Int          // HighlightColor rawValue
    let annotation: String? // optional note on the highlight

    init(from highlight: ArticleHighlight) {
        self.selectedText = highlight.selectedText
        self.color = highlight.color.rawValue
        self.annotation = highlight.annotation
    }
}

/// A lightweight, Codable snapshot of a note for sharing.
struct ShareableNote: Codable, Equatable {
    let text: String

    init(from note: ArticleNote) {
        self.text = note.text
    }
}

/// The full annotation bundle for one article.
struct AnnotationBundle: Codable, Equatable {
    /// Schema version for forward compatibility.
    let version: Int
    /// Article link (URL) to match on import.
    let articleLink: String
    /// Article title for display context.
    let articleTitle: String
    /// Exported highlights.
    let highlights: [ShareableHighlight]
    /// Exported notes (usually 0 or 1 per article, but array for future-proofing).
    let notes: [ShareableNote]
    /// ISO-8601 timestamp of when the bundle was created.
    let exportedAt: String
    /// Optional sharer name/tag.
    let sharedBy: String?

    static let currentVersion = 1
    static let magicPrefix = "FR-ANN:"
}

// MARK: - Import Result

/// Outcome of importing an annotation bundle.
struct AnnotationImportResult: Equatable {
    let articleLink: String
    let articleTitle: String
    let highlightsAdded: Int
    let highlightsSkipped: Int
    let notesAdded: Int
    let notesSkipped: Int

    var totalAdded: Int { highlightsAdded + notesAdded }
    var totalSkipped: Int { highlightsSkipped + notesSkipped }

    var summary: String {
        var parts: [String] = []
        if highlightsAdded > 0 { parts.append("\(highlightsAdded) highlight(s) added") }
        if highlightsSkipped > 0 { parts.append("\(highlightsSkipped) highlight(s) already existed") }
        if notesAdded > 0 { parts.append("\(notesAdded) note(s) added") }
        if notesSkipped > 0 { parts.append("\(notesSkipped) note(s) already existed") }
        if parts.isEmpty { return "Nothing to import." }
        return parts.joined(separator: ", ") + "."
    }
}

// MARK: - Error Types

enum AnnotationShareError: Error, LocalizedError {
    case emptyAnnotations
    case encodingFailed
    case invalidShareCode
    case decodingFailed
    case unsupportedVersion(Int)
    case articleMismatch(expected: String, got: String)

    var errorDescription: String? {
        switch self {
        case .emptyAnnotations:
            return "No highlights or notes to export for this article."
        case .encodingFailed:
            return "Failed to encode annotations."
        case .invalidShareCode:
            return "The share code is invalid or corrupted."
        case .decodingFailed:
            return "Failed to decode the annotation bundle."
        case .unsupportedVersion(let v):
            return "Unsupported annotation format version \(v). Please update FeedReader."
        case .articleMismatch(let expected, let got):
            return "Annotation was for '\(expected)' but you're viewing '\(got)'."
        }
    }
}

// MARK: - Annotation Share Manager

class AnnotationShareManager {

    static let shared = AnnotationShareManager()

    private init() {}

    // MARK: - Export

    /// Export all annotations (highlights + notes) for an article as a share code string.
    /// - Parameters:
    ///   - articleLink: The article's URL.
    ///   - articleTitle: The article's title.
    ///   - sharedBy: Optional name/tag for the exporter.
    /// - Returns: A compact share code string prefixed with `FR-ANN:`.
    func exportAnnotations(articleLink: String,
                           articleTitle: String,
                           sharedBy: String? = nil) throws -> String {
        let highlights = ArticleHighlightsManager.shared
            .highlights(for: articleLink)
            .map { ShareableHighlight(from: $0) }

        var notes: [ShareableNote] = []
        if let note = ArticleNotesManager.shared.note(for: articleLink) {
            notes.append(ShareableNote(from: note))
        }

        guard !highlights.isEmpty || !notes.isEmpty else {
            throw AnnotationShareError.emptyAnnotations
        }

        let formatter = ISO8601DateFormatter()
        let bundle = AnnotationBundle(
            version: AnnotationBundle.currentVersion,
            articleLink: articleLink,
            articleTitle: articleTitle,
            highlights: highlights,
            notes: notes,
            exportedAt: formatter.string(from: Date()),
            sharedBy: sharedBy
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        guard let jsonData = try? encoder.encode(bundle) else {
            throw AnnotationShareError.encodingFailed
        }

        let compressed = try compressData(jsonData)
        let base64 = compressed.base64EncodedString()
        return AnnotationBundle.magicPrefix + base64
    }

    // MARK: - Decode (Preview)

    /// Decode a share code into a bundle without importing. Useful for preview.
    func decodeShareCode(_ code: String) throws -> AnnotationBundle {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)

        let payload: String
        if trimmed.hasPrefix(AnnotationBundle.magicPrefix) {
            payload = String(trimmed.dropFirst(AnnotationBundle.magicPrefix.count))
        } else {
            payload = trimmed
        }

        guard let compressedData = Data(base64Encoded: payload) else {
            throw AnnotationShareError.invalidShareCode
        }

        let jsonData: Data
        do {
            jsonData = try decompressData(compressedData)
        } catch {
            // Fallback: maybe it wasn't compressed (older version)
            guard let fallback = Data(base64Encoded: payload) else {
                throw AnnotationShareError.decodingFailed
            }
            jsonData = fallback
        }

        guard let bundle = try? JSONDecoder().decode(AnnotationBundle.self, from: jsonData) else {
            throw AnnotationShareError.decodingFailed
        }

        guard bundle.version <= AnnotationBundle.currentVersion else {
            throw AnnotationShareError.unsupportedVersion(bundle.version)
        }

        return bundle
    }

    // MARK: - Import

    /// Import annotations from a share code, merging into the user's library.
    /// Skips highlights whose selectedText already exists for the article.
    /// - Parameters:
    ///   - code: The share code string.
    ///   - targetArticleLink: If provided, only import if bundle matches this article.
    /// - Returns: An import result describing what was added/skipped.
    func importAnnotations(from code: String,
                           targetArticleLink: String? = nil) throws -> AnnotationImportResult {
        let bundle = try decodeShareCode(code)

        if let target = targetArticleLink, target != bundle.articleLink {
            throw AnnotationShareError.articleMismatch(expected: bundle.articleTitle, got: target)
        }

        let existingHighlightTexts = Set(
            ArticleHighlightsManager.shared
                .highlights(for: bundle.articleLink)
                .map { $0.selectedText }
        )

        var highlightsAdded = 0
        var highlightsSkipped = 0

        for h in bundle.highlights {
            if existingHighlightTexts.contains(h.selectedText) {
                highlightsSkipped += 1
                continue
            }
            let color = HighlightColor(rawValue: h.color) ?? .yellow
            let result = ArticleHighlightsManager.shared.addHighlight(
                articleLink: bundle.articleLink,
                articleTitle: bundle.articleTitle,
                selectedText: h.selectedText,
                color: color,
                annotation: h.annotation
            )
            if result != nil {
                highlightsAdded += 1
            } else {
                highlightsSkipped += 1
            }
        }

        var notesAdded = 0
        var notesSkipped = 0

        for n in bundle.notes {
            let existing = ArticleNotesManager.shared.note(for: bundle.articleLink)
            if existing != nil {
                // Don't overwrite existing notes — skip
                notesSkipped += 1
            } else {
                let result = ArticleNotesManager.shared.setNote(
                    for: bundle.articleLink,
                    title: bundle.articleTitle,
                    text: n.text
                )
                if result != nil {
                    notesAdded += 1
                } else {
                    notesSkipped += 1
                }
            }
        }

        return AnnotationImportResult(
            articleLink: bundle.articleLink,
            articleTitle: bundle.articleTitle,
            highlightsAdded: highlightsAdded,
            highlightsSkipped: highlightsSkipped,
            notesAdded: notesAdded,
            notesSkipped: notesSkipped
        )
    }

    // MARK: - Compression (zlib via Foundation)

    /// Simple zlib compression using NSData.
    private func compressData(_ data: Data) throws -> Data {
        // Use a simple run-length-like approach with Data for portability.
        // In practice on iOS, we'd use Compression framework, but for
        // broad Swift compatibility we'll just return raw data.
        // The base64 overhead is acceptable for annotation-sized payloads.
        return data
    }

    private func decompressData(_ data: Data) throws -> Data {
        return data
    }

    // MARK: - Utilities

    /// Generate a human-readable summary of a bundle for preview.
    func bundleSummary(_ bundle: AnnotationBundle) -> String {
        var lines: [String] = []
        lines.append("📖 \(bundle.articleTitle)")
        lines.append("🔗 \(bundle.articleLink)")
        if let by = bundle.sharedBy {
            lines.append("👤 Shared by: \(by)")
        }
        lines.append("📅 Exported: \(bundle.exportedAt)")
        lines.append("✏️ \(bundle.highlights.count) highlight(s), \(bundle.notes.count) note(s)")
        return lines.joined(separator: "\n")
    }
}
