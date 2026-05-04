//
//  ArticleArchiveExporter.swift
//  FeedReader
//
//  Exports articles as self-contained HTML archive files for offline
//  reading, sharing, or long-term preservation. Supports single and
//  batch export with customizable themes.
//

import Foundation

/// Exports Story objects as standalone HTML archive files.
/// Each archive is a single .html file with embedded styles,
/// metadata, and readable typography — no external dependencies.
class ArticleArchiveExporter {
    
    // MARK: - Types
    
    /// Visual theme for the exported HTML.
    enum Theme: String, CaseIterable {
        case light
        case dark
        case sepia
        case newspaper
        
        var backgroundColor: String {
            switch self {
            case .light:     return "#ffffff"
            case .dark:      return "#1a1a2e"
            case .sepia:     return "#f4ecd8"
            case .newspaper: return "#fafaf0"
            }
        }
        
        var textColor: String {
            switch self {
            case .light:     return "#333333"
            case .dark:      return "#e0e0e0"
            case .sepia:     return "#5b4636"
            case .newspaper: return "#2c2c2c"
            }
        }
        
        var accentColor: String {
            switch self {
            case .light:     return "#2563eb"
            case .dark:      return "#60a5fa"
            case .sepia:     return "#8b6914"
            case .newspaper: return "#444444"
            }
        }
        
        var fontFamily: String {
            switch self {
            case .light:     return "-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif"
            case .dark:      return "-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif"
            case .sepia:     return "Georgia, 'Times New Roman', serif"
            case .newspaper: return "'Palatino Linotype', Palatino, Georgia, serif"
            }
        }
    }
    
    /// Options controlling the export output.
    struct ExportOptions {
        var theme: Theme = .light
        var includeMetadata: Bool = true
        var includeTableOfContents: Bool = false
        var includeWordCount: Bool = true
        var includeEstimatedReadTime: Bool = true
        var customCSS: String? = nil
        
        static let `default` = ExportOptions()
    }
    
    /// Result of an export operation.
    struct ExportResult {
        let filename: String
        let htmlContent: String
        let articleCount: Int
        let totalWordCount: Int
        let exportDate: Date
    }
    
    // MARK: - Properties
    
    private let options: ExportOptions
    private let dateFormatter: DateFormatter
    
    // MARK: - Initialization
    
    init(options: ExportOptions = .default) {
        self.options = options
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateStyle = .long
        self.dateFormatter.timeStyle = .short
    }
    
    // MARK: - Single Article Export
    
    /// Exports a single article as a standalone HTML file.
    func exportArticle(_ story: Story) -> ExportResult {
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
    func exportArticles(_ stories: [Story]) -> ExportResult? {
        guard !stories.isEmpty else { return nil }
        
        let totalWords = stories.reduce(0) { $0 + countWords($1.body) }
        let html = buildBatchHTML(stories, totalWordCount: totalWords)
        let count = stories.count
        let filename = "FeedReader_Archive_\(count)_articles.html"
        
        return ExportResult(
            filename: filename,
            htmlContent: html,
            articleCount: count,
            totalWordCount: totalWords,
            exportDate: Date()
        )
    }
    
    // MARK: - Save to Disk
    
    /// Saves an export result to the documents directory.
    /// Returns the file URL on success.
    @discardableResult
    func save(_ result: ExportResult, to directory: URL? = nil) -> URL? {
        let dir = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let archiveDir = dir.appendingPathComponent("Archives")
        
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
    
    /// Lists previously exported archive files.
    func listArchives(in directory: URL? = nil) -> [(filename: String, date: Date, size: Int)] {
        let dir = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let archiveDir = dir.appendingPathComponent("Archives")
        
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
    
    /// Deletes an archive file by filename.
    func deleteArchive(named filename: String, in directory: URL? = nil) -> Bool {
        let dir = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = dir.appendingPathComponent("Archives").appendingPathComponent(filename)
        
        do {
            try FileManager.default.removeItem(at: fileURL)
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Private: HTML Building
    
    private func buildSingleArticleHTML(_ story: Story, wordCount: Int, readTime: Int) -> String {
        let theme = options.theme
        let exportDate = dateFormatter.string(from: Date())
        
        var metaSection = ""
        if options.includeMetadata {
            var metaParts: [String] = []
            if let source = story.sourceFeedName {
                metaParts.append("<span class=\"meta-item\">📰 \(source.htmlEscaped)</span>")
            }
            if options.includeWordCount {
                metaParts.append("<span class=\"meta-item\">📝 \(wordCount) words</span>")
            }
            if options.includeEstimatedReadTime {
                metaParts.append("<span class=\"meta-item\">⏱ \(readTime) min read</span>")
            }
            metaParts.append("<span class=\"meta-item\">📅 Exported \(exportDate.htmlEscaped)</span>")
            metaSection = "<div class=\"meta\">\(metaParts.joined(separator: " · "))</div>"
        }
        
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <meta name="generator" content="FeedReader Archive Exporter">
            <title>\(story.title.htmlEscaped)</title>
            <style>\(buildCSS(theme: theme))</style>
        </head>
        <body>
            <article class="archive-article">
                <header>
                    <h1>\(story.title.htmlEscaped)</h1>
                    \(metaSection)
                </header>
                <div class="article-body">
                    \(formatBody(story.body))
                </div>
                <footer>
                    <a href="\(story.link.htmlEscaped)" class="source-link">🔗 Original Article</a>
                    <p class="archive-note">Archived with FeedReader</p>
                </footer>
            </article>
        </body>
        </html>
        """
    }
    
    private func buildBatchHTML(_ stories: [Story], totalWordCount: Int) -> String {
        let theme = options.theme
        let exportDate = dateFormatter.string(from: Date())
        
        // Table of contents
        var toc = ""
        if options.includeTableOfContents {
            let tocItems = stories.enumerated().map { (i, story) in
                "<li><a href=\"#article-\(i)\">\(story.title.htmlEscaped)</a></li>"
            }.joined(separator: "\n")
            toc = """
            <nav class="toc">
                <h2>Table of Contents</h2>
                <ol>\(tocItems)</ol>
            </nav>
            """
        }
        
        // Articles
        let articlesHTML = stories.enumerated().map { (i, story) in
            let wc = countWords(story.body)
            let rt = estimateReadTime(wordCount: wc)
            var meta = ""
            if options.includeMetadata {
                var parts: [String] = []
                if let source = story.sourceFeedName {
                    parts.append("📰 \(source.htmlEscaped)")
                }
                if options.includeWordCount { parts.append("📝 \(wc) words") }
                if options.includeEstimatedReadTime { parts.append("⏱ \(rt) min") }
                meta = "<div class=\"meta\">\(parts.joined(separator: " · "))</div>"
            }
            return """
            <article id="article-\(i)" class="archive-article">
                <header>
                    <h2>\(story.title.htmlEscaped)</h2>
                    \(meta)
                </header>
                <div class="article-body">\(formatBody(story.body))</div>
                <footer>
                    <a href="\(story.link.htmlEscaped)" class="source-link">🔗 Original</a>
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
            <meta name="generator" content="FeedReader Archive Exporter">
            <title>FeedReader Archive — \(stories.count) Articles</title>
            <style>\(buildCSS(theme: theme))</style>
        </head>
        <body id="top">
            <header class="archive-header">
                <h1>📚 FeedReader Archive</h1>
                <p>\(stories.count) articles · \(totalWordCount) words · Exported \(exportDate.htmlEscaped)</p>
            </header>
            \(toc)
            \(articlesHTML)
            <footer class="archive-footer">
                <p>Archived with FeedReader</p>
            </footer>
        </body>
        </html>
        """
    }
    
    private func buildCSS(theme: Theme) -> String {
        let custom = sanitizeCSS(options.customCSS ?? "")
        return """
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            background: \(theme.backgroundColor);
            color: \(theme.textColor);
            font-family: \(theme.fontFamily);
            line-height: 1.7;
            max-width: 720px;
            margin: 0 auto;
            padding: 2rem 1.5rem;
        }
        .archive-header { text-align: center; margin-bottom: 2rem; padding-bottom: 1rem; border-bottom: 2px solid \(theme.accentColor); }
        .archive-header h1 { font-size: 1.8rem; margin-bottom: 0.5rem; }
        .archive-header p { opacity: 0.7; font-size: 0.9rem; }
        .toc { margin-bottom: 2rem; padding: 1rem; border: 1px solid \(theme.accentColor)33; border-radius: 8px; }
        .toc h2 { font-size: 1.1rem; margin-bottom: 0.5rem; }
        .toc ol { padding-left: 1.5rem; }
        .toc li { margin: 0.3rem 0; }
        .toc a { color: \(theme.accentColor); text-decoration: none; }
        .toc a:hover { text-decoration: underline; }
        .archive-article { margin: 2rem 0; }
        .archive-article h1, .archive-article h2 { font-size: 1.5rem; margin-bottom: 0.5rem; }
        .meta { font-size: 0.85rem; opacity: 0.7; margin-bottom: 1.5rem; }
        .meta .meta-item { white-space: nowrap; }
        .article-body { margin-bottom: 1.5rem; }
        .article-body p { margin-bottom: 1rem; }
        footer { font-size: 0.85rem; opacity: 0.6; margin-top: 1rem; }
        .source-link { color: \(theme.accentColor); text-decoration: none; margin-right: 1rem; }
        .source-link:hover { text-decoration: underline; }
        .back-to-top { color: \(theme.accentColor); text-decoration: none; }
        .article-divider { border: none; border-top: 1px solid \(theme.accentColor)33; margin: 2rem 0; }
        .archive-footer { text-align: center; margin-top: 3rem; padding-top: 1rem; border-top: 1px solid \(theme.accentColor)33; font-size: 0.8rem; opacity: 0.5; }
        .archive-note { margin-top: 0.5rem; font-size: 0.8rem; }
        @media print {
            body { max-width: 100%; padding: 1rem; }
            .back-to-top, .toc { display: none; }
            .archive-article { page-break-inside: avoid; }
        }
        \(custom)
        """
    }
    
    // MARK: - Private: Utilities
    
    private func countWords(_ text: String) -> Int {
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return words.count
    }
    
    private func estimateReadTime(wordCount: Int) -> Int {
        return max(1, wordCount / 200)
    }
    
    private func formatBody(_ body: String) -> String {
        // Split into paragraphs on double newlines, wrap each in <p>
        let paragraphs = body.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "<p>\($0.htmlEscaped)</p>" }
        
        return paragraphs.isEmpty ? "<p>\(body.htmlEscaped)</p>" : paragraphs.joined(separator: "\n")
    }
    
    private func sanitizeFilename(_ title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let sanitized = title.unicodeScalars.filter { allowed.contains($0) }.map { Character($0) }
        let result = String(sanitized).trimmingCharacters(in: .whitespaces)
        let truncated = String(result.prefix(80))
        return truncated.isEmpty ? "article" : truncated.replacingOccurrences(of: " ", with: "_")
    }
    
    /// Sanitize custom CSS to prevent style-tag breakout (XSS).
    /// A malicious customCSS string like `</style><script>...</script><style>`
    /// could escape the `<style>` element and inject arbitrary JavaScript
    /// into the exported HTML archive. This strips `</style` sequences and
    /// CSS expressions/imports that can execute code (CWE-79).
    private func sanitizeCSS(_ css: String) -> String {
        var result = css
        // Strip any closing style tag (case-insensitive) — prevents breaking
        // out of the <style> element. Matches `</style` with optional
        // whitespace and `>`.
        let styleClosePattern = try? NSRegularExpression(
            pattern: "<\\s*/\\s*style",
            options: .caseInsensitive
        )
        result = styleClosePattern?.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "/* blocked */"
        ) ?? result
        // Strip opening script/html tags that could be injected
        let dangerousTagPattern = try? NSRegularExpression(
            pattern: "<\\s*(?:script|iframe|object|embed|link|meta|svg|img)",
            options: .caseInsensitive
        )
        result = dangerousTagPattern?.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "/* blocked */"
        ) ?? result
        // Strip CSS expressions and imports (legacy IE expression(), @import
        // which can load external resources)
        let cssExprPattern = try? NSRegularExpression(
            pattern: "expression\\s*\\(|@import\\s",
            options: .caseInsensitive
        )
        result = cssExprPattern?.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "/* blocked */"
        ) ?? result
        return result
    }

    private func _ text: String.htmlEscaped -> String {
        return text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
