//
//  ArticleArchiveExporter.swift
//  FeedReaderCore
//
//  Exports RSSStory objects as self-contained HTML archive files for
//  offline reading, sharing, or long-term preservation.
//  Supports single and batch export with 4 visual themes.
//

import Foundation

/// Exports RSSStory objects as standalone HTML archive files.
public class ArticleArchiveExporter {
    
    // MARK: - Types
    
    /// Visual theme for the exported HTML archive.
    ///
    /// Each theme bundles a coordinated background / text / accent colour
    /// triple plus a font family appropriate for the look (sans-serif for
    /// `light`/`dark`, serif for `sepia`/`newspaper`).
    public enum Theme: String, CaseIterable {
        /// Bright background, dark text — best for daytime reading.
        case light
        /// Dark background, light text — best for low-light reading and OLED screens.
        case dark
        /// Warm parchment-style palette inspired by e-ink readers.
        case sepia
        /// High-contrast classic-newsprint palette with serif typography.
        case newspaper
        
        /// CSS background colour for the document body in this theme.
        public var backgroundColor: String {
            switch self {
            case .light:     return "#ffffff"
            case .dark:      return "#1a1a2e"
            case .sepia:     return "#f4ecd8"
            case .newspaper: return "#fafaf0"
            }
        }
        
        /// CSS foreground/text colour for body copy in this theme.
        public var textColor: String {
            switch self {
            case .light:     return "#333333"
            case .dark:      return "#e0e0e0"
            case .sepia:     return "#5b4636"
            case .newspaper: return "#2c2c2c"
            }
        }
        
        /// CSS accent colour used for links, dividers, and emphasis.
        public var accentColor: String {
            switch self {
            case .light:     return "#2563eb"
            case .dark:      return "#60a5fa"
            case .sepia:     return "#8b6914"
            case .newspaper: return "#444444"
            }
        }
        
        /// CSS `font-family` stack used for body copy in this theme.
        public var fontFamily: String {
            switch self {
            case .light:     return "-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif"
            case .dark:      return "-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif"
            case .sepia:     return "Georgia, 'Times New Roman', serif"
            case .newspaper: return "'Palatino Linotype', Palatino, Georgia, serif"
            }
        }
    }
    
    /// Options controlling the export output (theme, metadata, custom CSS).
    public struct ExportOptions {
        /// Visual theme applied to the rendered HTML.
        public var theme: Theme
        /// When `true`, includes a `<div class="meta">` block with word count
        /// and estimated reading time. Disable for a minimal layout.
        public var includeMetadata: Bool
        /// When `true` (batch export only), renders an anchor-linked table
        /// of contents at the top of the archive.
        public var includeTableOfContents: Bool
        /// When `true` (and metadata is enabled), shows the article word count.
        public var includeWordCount: Bool
        /// When `true` (and metadata is enabled), shows the estimated read time.
        public var includeEstimatedReadTime: Bool
        /// Additional CSS appended after the built-in stylesheet. Use this
        /// to override colours, fonts, or layout without forking the exporter.
        public var customCSS: String?

        /// Creates an `ExportOptions` value with sensible defaults.
        ///
        /// - Parameters:
        ///   - theme: Visual theme; defaults to `.light`.
        ///   - includeMetadata: Whether to render the metadata block.
        ///   - includeTableOfContents: Whether batch exports get a TOC.
        ///   - includeWordCount: Whether the metadata block shows word counts.
        ///   - includeEstimatedReadTime: Whether the metadata block shows read times.
        ///   - customCSS: Optional extra CSS appended to the stylesheet.
        public init(
            theme: Theme = .light,
            includeMetadata: Bool = true,
            includeTableOfContents: Bool = false,
            includeWordCount: Bool = true,
            includeEstimatedReadTime: Bool = true,
            customCSS: String? = nil
        ) {
            self.theme = theme
            self.includeMetadata = includeMetadata
            self.includeTableOfContents = includeTableOfContents
            self.includeWordCount = includeWordCount
            self.includeEstimatedReadTime = includeEstimatedReadTime
            self.customCSS = customCSS
        }
        
        /// The default options: light theme, metadata + word count + read time on, no TOC.
        public static let `default` = ExportOptions()
    }
    
    /// Result of an export operation. Holds the rendered HTML in memory;
    /// pair with ``ArticleArchiveExporter/save(_:to:)`` to write to disk.
    public struct ExportResult {
        /// Suggested filename (with `.html` extension) for the rendered archive.
        public let filename: String
        /// The full, self-contained HTML document for this archive.
        public let htmlContent: String
        /// Number of articles included in this export.
        public let articleCount: Int
        /// Sum of word counts across all included articles.
        public let totalWordCount: Int
        /// Wall-clock time at which the export was produced.
        public let exportDate: Date
    }
    
    // MARK: - Properties
    
    private let options: ExportOptions
    
    // MARK: - Initialization

    /// Creates an exporter configured with the given options.
    ///
    /// - Parameter options: Export configuration; defaults to `.default`.
    public init(options: ExportOptions = .default) {
        self.options = options
    }
    
    // MARK: - Single Article Export
    
    /// Exports a single article as a standalone, self-contained HTML file.
    ///
    /// The returned `ExportResult` carries the rendered HTML in memory.
    /// Use ``save(_:to:)`` to persist it to disk.
    ///
    /// - Parameter story: The article to export.
    /// - Returns: An `ExportResult` describing the rendered document.
    public func exportArticle(_ story: RSSStory) -> ExportResult {
        let wordCount = countWords(story.body)
        let readTime = estimateReadTime(wordCount: wordCount)
        let html = buildSingleArticleHTML(story, wordCount: wordCount, readTime: readTime)
        let filename = sanitizeFilename(story.title) + ".html"
        
        return ExportResult(
            filename: filename,
            htmlContent: html,
            articleCount: 1,
            totalWordCount: wordCount,
            exportDate: Date()
        )
    }
    
    // MARK: - Batch Export
    
    /// Exports multiple articles into a single HTML archive with navigation.
    ///
    /// When ``ExportOptions/includeTableOfContents`` is enabled, the archive
    /// includes an anchor-linked TOC and back-to-top links between articles.
    ///
    /// - Parameter stories: The articles to include. Order is preserved.
    /// - Returns: An `ExportResult`, or `nil` if `stories` is empty.
    public func exportArticles(_ stories: [RSSStory]) -> ExportResult? {
        guard !stories.isEmpty else { return nil }
        
        let totalWords = stories.reduce(0) { $0 + countWords($1.body) }
        let html = buildBatchHTML(stories, totalWordCount: totalWords)
        let filename = "FeedReader_Archive_\(stories.count)_articles.html"
        
        return ExportResult(
            filename: filename,
            htmlContent: html,
            articleCount: stories.count,
            totalWordCount: totalWords,
            exportDate: Date()
        )
    }
    
    // MARK: - Save to Disk
    
    /// Saves an export result to disk under an `Archives/` subdirectory of
    /// the given base directory.
    ///
    /// The `Archives/` directory is created automatically if it does not
    /// already exist. The file is written atomically as UTF-8.
    ///
    /// - Parameters:
    ///   - result: The rendered export to persist.
    ///   - directory: Base directory; the archive lands in `directory/Archives/`.
    /// - Returns: The URL of the written file, or `nil` if the write failed.
    @discardableResult
    public func save(_ result: ExportResult, to directory: URL) -> URL? {
        let archiveDir = directory.appendingPathComponent("Archives")
        
        do {
            try FileManager.default.createDirectory(at: archiveDir, withIntermediateDirectories: true)
            let fileURL = archiveDir.appendingPathComponent(result.filename)
            try result.htmlContent.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }
    
    // MARK: - List Archives
    
    /// Lists previously exported archive files in the given directory.
    ///
    /// Only `*.html` files inside `directory/Archives/` are returned.
    /// Results are sorted newest-first by creation date.
    ///
    /// - Parameter directory: Base directory that contains an `Archives/`
    ///   subdirectory created by a prior call to ``save(_:to:)``.
    /// - Returns: Tuples of `(filename, creationDate, sizeInBytes)`.
    ///   Empty if the directory is missing or unreadable.
    public func listArchives(in directory: URL) -> [(filename: String, date: Date, size: Int)] {
        let archiveDir = directory.appendingPathComponent("Archives")
        
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: archiveDir,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }
        
        return files
            .filter { $0.pathExtension == "html" }
            .compactMap { url -> (String, Date, Int)? in
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                      let date = attrs[.creationDate] as? Date,
                      let size = attrs[.size] as? Int else {
                    return nil
                }
                return (url.lastPathComponent, date, size)
            }
            .sorted { $0.1 > $1.1 }
    }
    
    // MARK: - Delete Archive
    
    /// Deletes a previously exported archive file by filename.
    ///
    /// - Parameters:
    ///   - filename: Filename (including `.html` extension) as returned by
    ///     ``listArchives(in:)``.
    ///   - directory: Base directory that contains the `Archives/` folder.
    /// - Returns: `true` on success, `false` if the file did not exist or
    ///   could not be removed.
    public func deleteArchive(named filename: String, in directory: URL) -> Bool {
        let fileURL = directory.appendingPathComponent("Archives").appendingPathComponent(filename)
        do {
            try FileManager.default.removeItem(at: fileURL)
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Utility
    
    /// Counts whitespace-separated words in `text`. Thin wrapper over
    /// ``TextUtilities/countWords(_:)`` so callers don't need to reach into
    /// the utility namespace.
    ///
    /// - Parameter text: The body text to measure.
    /// - Returns: Number of words detected (always `>= 0`).
    public func countWords(_ text: String) -> Int {
        return TextUtilities.countWords(text)
    }

    /// Estimates reading time in minutes assuming 200 words-per-minute.
    /// Thin wrapper over ``TextUtilities/estimateReadTime(wordCount:)``.
    ///
    /// - Parameter wordCount: The word count produced by ``countWords(_:)``.
    /// - Returns: Estimated minutes, rounded up; always `>= 1` for non-empty input.
    public func estimateReadTime(wordCount: Int) -> Int {
        return TextUtilities.estimateReadTime(wordCount: wordCount)
    }
    
    // MARK: - Private: HTML Building
    
    private func buildSingleArticleHTML(_ story: RSSStory, wordCount: Int, readTime: Int) -> String {
        let theme = options.theme
        
        var metaSection = ""
        if options.includeMetadata {
            var parts: [String] = []
            if options.includeWordCount { parts.append("📝 \(wordCount) words") }
            if options.includeEstimatedReadTime { parts.append("⏱ \(readTime) min read") }
            metaSection = "<div class=\"meta\">\(parts.joined(separator: " · "))</div>"
        }
        
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <meta name="generator" content="FeedReader Archive Exporter">
            <title>\(escapeHTML(story.title))</title>
            <style>\(buildCSS(theme: theme))</style>
        </head>
        <body>
            <article class="archive-article">
                <header>
                    <h1>\(escapeHTML(story.title))</h1>
                    \(metaSection)
                </header>
                <div class="article-body">
                    \(formatBody(story.body))
                </div>
                <footer>
                    <a href="\(escapeHTML(story.link))" class="source-link">🔗 Original Article</a>
                    <p class="archive-note">Archived with FeedReader</p>
                </footer>
            </article>
        </body>
        </html>
        """
    }
    
    private func buildBatchHTML(_ stories: [RSSStory], totalWordCount: Int) -> String {
        let theme = options.theme
        
        var toc = ""
        if options.includeTableOfContents {
            let items = stories.enumerated().map { (i, s) in
                "<li><a href=\"#article-\(i)\">\(escapeHTML(s.title))</a></li>"
            }.joined(separator: "\n")
            toc = "<nav class=\"toc\"><h2>Table of Contents</h2><ol>\(items)</ol></nav>"
        }
        
        let articles = stories.enumerated().map { (i, story) in
            let wc = countWords(story.body)
            let rt = estimateReadTime(wordCount: wc)
            var meta = ""
            if options.includeMetadata {
                var parts: [String] = []
                if options.includeWordCount { parts.append("📝 \(wc) words") }
                if options.includeEstimatedReadTime { parts.append("⏱ \(rt) min") }
                meta = "<div class=\"meta\">\(parts.joined(separator: " · "))</div>"
            }
            return """
            <article id="article-\(i)" class="archive-article">
                <header><h2>\(escapeHTML(story.title))</h2>\(meta)</header>
                <div class="article-body">\(formatBody(story.body))</div>
                <footer>
                    <a href="\(escapeHTML(story.link))" class="source-link">🔗 Original</a>
                    <a href="#top" class="back-to-top">↑ Top</a>
                </footer>
            </article>
            """
        }.joined(separator: "\n<hr class=\"article-divider\">\n")
        
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>FeedReader Archive — \(stories.count) Articles</title>
            <style>\(buildCSS(theme: theme))</style>
        </head>
        <body id="top">
            <header class="archive-header">
                <h1>📚 FeedReader Archive</h1>
                <p>\(stories.count) articles · \(totalWordCount) words</p>
            </header>
            \(toc)
            \(articles)
            <footer class="archive-footer"><p>Archived with FeedReader</p></footer>
        </body>
        </html>
        """
    }
    
    private func buildCSS(theme: Theme) -> String {
        let custom = options.customCSS ?? ""
        return """
        *{margin:0;padding:0;box-sizing:border-box}
        body{background:\(theme.backgroundColor);color:\(theme.textColor);font-family:\(theme.fontFamily);line-height:1.7;max-width:720px;margin:0 auto;padding:2rem 1.5rem}
        .archive-header{text-align:center;margin-bottom:2rem;padding-bottom:1rem;border-bottom:2px solid \(theme.accentColor)}
        .archive-header h1{font-size:1.8rem;margin-bottom:.5rem}
        .archive-header p{opacity:.7;font-size:.9rem}
        .toc{margin-bottom:2rem;padding:1rem;border:1px solid \(theme.accentColor)33;border-radius:8px}
        .toc h2{font-size:1.1rem;margin-bottom:.5rem}
        .toc ol{padding-left:1.5rem}
        .toc li{margin:.3rem 0}
        .toc a{color:\(theme.accentColor);text-decoration:none}
        .archive-article{margin:2rem 0}
        .archive-article h1,.archive-article h2{font-size:1.5rem;margin-bottom:.5rem}
        .meta{font-size:.85rem;opacity:.7;margin-bottom:1.5rem}
        .article-body{margin-bottom:1.5rem}
        .article-body p{margin-bottom:1rem}
        footer{font-size:.85rem;opacity:.6;margin-top:1rem}
        .source-link{color:\(theme.accentColor);text-decoration:none;margin-right:1rem}
        .back-to-top{color:\(theme.accentColor);text-decoration:none}
        .article-divider{border:none;border-top:1px solid \(theme.accentColor)33;margin:2rem 0}
        .archive-footer{text-align:center;margin-top:3rem;padding-top:1rem;border-top:1px solid \(theme.accentColor)33;font-size:.8rem;opacity:.5}
        @media print{body{max-width:100%;padding:1rem}.back-to-top,.toc{display:none}.archive-article{page-break-inside:avoid}}
        \(custom)
        """
    }
    
    private func formatBody(_ body: String) -> String {
        let paragraphs = body.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "<p>\(escapeHTML($0))</p>" }
        return paragraphs.isEmpty ? "<p>\(escapeHTML(body))</p>" : paragraphs.joined(separator: "\n")
    }
    
    private func sanitizeFilename(_ title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let sanitized = title.unicodeScalars.filter { allowed.contains($0) }.map { Character($0) }
        let result = String(sanitized).trimmingCharacters(in: .whitespaces)
        let truncated = String(result.prefix(80))
        return truncated.isEmpty ? "article" : truncated.replacingOccurrences(of: " ", with: "_")
    }
    
    /// Delegates to `TextUtilities.escapeHTML` for single-pass HTML escaping.
    private func escapeHTML(_ text: String) -> String {
        return TextUtilities.escapeHTML(text)
    }
}
